//! Upstream Component C API with worker-local allocation accounting.
pub use wasmtime_c_api::*;

mod allocator;
mod profile;
mod type_budget;
