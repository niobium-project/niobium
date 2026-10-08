//! The worker owns this allocator; quota exhaustion intentionally terminates it.
use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicUsize, Ordering::Relaxed};

static LIVE: AtomicUsize = AtomicUsize::new(0);
static LIMIT: AtomicUsize = AtomicUsize::new(usize::MAX);
static PEAK: AtomicUsize = AtomicUsize::new(0);

struct Quota;
#[global_allocator]
static ALLOCATOR: Quota = Quota;

#[cfg(unix)]
unsafe extern "C" {
    fn write(fd: i32, bytes: *const u8, size: usize) -> isize;
}

#[cfg(windows)]
unsafe extern "C" {
    fn _write(fd: i32, bytes: *const u8, size: u32) -> i32;
}

fn reserve(size: usize) -> bool {
    let old = LIVE.fetch_add(size, Relaxed);
    if size > LIMIT.load(Relaxed).saturating_sub(old) {
        LIVE.fetch_sub(size, Relaxed);
        let marker = b"NIOBIUM_COMPONENT_ALLOCATION_LIMIT\n";
        // Allocation-free diagnostic; parent also observes abnormal termination.
        unsafe {
            #[cfg(unix)]
            write(2, marker.as_ptr(), marker.len());
            #[cfg(windows)]
            _write(2, marker.as_ptr(), marker.len() as u32);
        }
        return false;
    }
    PEAK.fetch_max(old.saturating_add(size), Relaxed);
    true
}

unsafe impl GlobalAlloc for Quota {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        if !reserve(layout.size()) {
            return std::ptr::null_mut();
        }
        let ptr = unsafe { System.alloc(layout) };
        if ptr.is_null() {
            LIVE.fetch_sub(layout.size(), Relaxed);
        }
        ptr
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        unsafe {
            System.dealloc(ptr, layout);
        }
        LIVE.fetch_sub(layout.size(), Relaxed);
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, size: usize) -> *mut u8 {
        let growth = size.saturating_sub(layout.size());
        if !reserve(growth) {
            return std::ptr::null_mut();
        }
        let next = unsafe { System.realloc(ptr, layout, size) };
        if next.is_null() {
            LIVE.fetch_sub(growth, Relaxed);
        } else if size < layout.size() {
            LIVE.fetch_sub(layout.size() - size, Relaxed);
        }
        next
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn nb_component_allocation_limit(additional_bytes: usize) {
    LIMIT.store(LIVE.load(Relaxed).saturating_add(additional_bytes), Relaxed);
}

#[unsafe(no_mangle)]
pub extern "C" fn nb_component_allocation_peak() -> usize {
    PEAK.load(Relaxed)
}
