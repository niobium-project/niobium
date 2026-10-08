//! Shared host-only worker wire contract.
const worker = @import("program").worker;
pub const FileSource = worker.FileSource;
pub const RangeSource = worker.RangeSource;
pub const Source = worker.Source;
pub const Request = worker.Request;
pub const Diagnostic = worker.Diagnostic;
pub const Response = worker.Response;
