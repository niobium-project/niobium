//! Inspect standard binary sections with the same upstream parser as Wasmtime.
use wasmparser::{Encoding, Parser, Payload};

/// Returns 0, malformed (-1), automatic initialization (-2), or limits (-3).
/// The trusted host owns `bytes` for the duration of the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nb_component_profile(
    bytes: *const u8,
    len: usize,
    max_modules: u32,
    max_types: u32,
    max_depth: u32,
) -> i32 {
    if bytes.is_null() {
        return -3;
    }
    let input = unsafe { std::slice::from_raw_parts(bytes, len) };
    let mut modules = 0u32;
    let mut types = crate::type_budget::TypeBudget::new(max_types, max_depth);
    let mut depth = 0u32;
    for payload in Parser::new(0).parse_all(input) {
        let Ok(payload) = payload else {
            return -1;
        };
        match payload {
            Payload::Version { encoding, .. } => {
                if depth == 0 && encoding != Encoding::Component {
                    return -1;
                }
                depth += 1;
                if depth > max_depth {
                    return -3;
                }
                if encoding == Encoding::Module {
                    modules += 1;
                }
            }
            Payload::End(_) => {
                depth = depth.saturating_sub(1);
            }
            Payload::StartSection { .. } | Payload::ComponentStartSection { .. } => return -2,
            Payload::TypeSection(reader) => {
                for group in reader {
                    let Ok(group) = group else {
                        return -1;
                    };
                    if let Err(code) = types.group(&group) {
                        return code;
                    }
                }
            }
            Payload::CoreTypeSection(reader) => {
                for ty in reader {
                    let Ok(ty) = ty else {
                        return -1;
                    };
                    if let Err(code) = types.core(&ty, depth) {
                        return code;
                    }
                }
            }
            Payload::ComponentTypeSection(reader) => {
                for ty in reader {
                    let Ok(ty) = ty else {
                        return -1;
                    };
                    if let Err(code) = types.component(&ty, depth) {
                        return code;
                    }
                }
            }
            _ => {}
        }
        if modules > max_modules {
            return -3;
        }
    }
    0
}
