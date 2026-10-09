//! An independent Rust consumer of the same upstream WIT generator.
wit_bindgen::generate!({ path: "../../../api/wit/qualification", world: "qualification" });

use exports::niobium::qualification::guest::{Failure, Guest, GuestCounter, Request, Response};

struct Library;
struct Count(u32);

impl GuestCounter for Count {
    fn new(value: u32) -> Self {
        Self(value)
    }
    fn value(&self) -> u32 {
        self.0
    }
}

impl Guest for Library {
    type Counter = Count;

    fn evaluate(input: Request) -> Result<Response, Failure> {
        if input.enabled == Some(false) {
            return Err(Failure::InvalidInput("disabled".into()));
        }
        Ok(Response {
            name: niobium::qualification::host::fact(),
            total: input.values.into_iter().map(u64::from).sum(),
        })
    }

    fn burn() {
        loop {
            core::hint::spin_loop();
        }
    }

    fn allocate(bytes: u32) -> u32 {
        core::arch::wasm32::memory_grow::<0>((bytes / 65536) as usize) as u32
    }

    fn output(bytes: u32) -> String {
        assert!(bytes <= 1 << 20);
        "x".repeat(bytes as usize)
    }

    fn amplify(bytes: u32) -> Vec<u8> {
        assert!(bytes <= 1 << 20);
        vec![1; bytes as usize]
    }

    fn many(calls: u32) {
        assert!(calls <= 2048);
        for _ in 0..calls {
            niobium::qualification::host::fact();
        }
    }
}

export!(Library);
