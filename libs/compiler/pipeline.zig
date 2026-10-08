//! Public language-independent compiler backend and publication boundary.

const types = @import("pipeline_types.zig");
pub const Request = types.Request;
pub const Input = types.Input;
pub const Inspector = types.Inspector;
pub const HostInterface = types.HostInterface;
pub const Finalizer = types.Finalizer;
pub const Output = types.Output;
pub const Compiled = types.Compiled;
pub const Built = types.Built;
pub const Diagnostic = types.Diagnostic;
pub const SourceMap = types.SourceMap;
pub const SourceMapFile = types.SourceMapFile;
pub const Location = types.Location;
pub const ObjectKind = types.ObjectKind;
pub const source_map = @import("pipeline_source_map.zig");
pub const IntegrationError = types.IntegrationError;
pub const Error = types.Error;
pub const compile = @import("pipeline_compile.zig").compile;
pub const build = @import("pipeline_build.zig").build;

test {
    _ = @import("pipeline_test.zig");
}
