//! Official file deployment uses the same public WIT proposal contract as product libraries.
wit_bindgen::generate!({ path: "wit", world: "files",
    with: { "niobium:runtime/proposal@1.0.0": generate } });
use exports::niobium::files::installer::{Guest, Request};
use niobium::runtime::proposal::{
    ContainerRef, ContainerSource, DesiredContainer, ObjectKind, Plan,
};
struct Files;
impl Guest for Files {
    fn select_content(
        primary: ContainerRef,
        fallback: ContainerRef,
        use_primary: bool,
    ) -> ContainerRef {
        // Selection does not acquire content; the consumer and host validate its use.
        if use_primary { primary } else { fallback }
    }

    fn build(input: Request) -> Result<Plan, String> {
        if input.content.sha256.len() != 32 {
            return Err("invalid content digest".into());
        }
        if input.file_access.kind != ObjectKind::File
            || input.directory_access.kind != ObjectKind::Directory
        {
            return Err("wrong access policy kind".into());
        }
        let containers = if input.enabled {
            vec![DesiredContainer {
                root: input.root,
                grant: input.grant,
                prefix: input.prefix,
                container: ContainerSource::Reference(input.content),
                file_access: input.file_access,
                directory_access: input.directory_access,
            }]
        } else {
            Vec::new()
        };
        Ok(Plan {
            containers,
            state: None,
        })
    }
}
export!(Files);
