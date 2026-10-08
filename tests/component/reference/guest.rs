//! A product library chooses desired content and access; the host grants the effects.
wit_bindgen::generate!({ path: "wit", world: "reference",
    with: { "niobium:runtime/proposal@1.0.0": generate } });
use exports::niobium::reference::installer::{Guest, GuestToken, Request};
use niobium::runtime::proposal::{
    ContainerSource, DesiredContainer, Entry, EntryKind, ObjectKind, Plan, Policy, Rights,
};

struct Library;
struct Token(u32);

impl GuestToken for Token {
    fn new(value: u32) -> Self {
        Self(value)
    }
    fn value(&self) -> u32 {
        self.0
    }
}

impl Guest for Library {
    type Token = Token;
    fn build(input: Request) -> Result<Plan, String> {
        let Request {
            root,
            grant,
            prefix,
            content,
            label,
            platform,
            enabled,
            previous,
        } = input;
        if content.sha256.len() != 32 {
            return Err("invalid content digest".into());
        }
        if previous.as_deref() == Some("unsupported") {
            return Err("unsupported previous state".into());
        }
        if cfg!(feature = "revision-two")
            && previous
                .as_deref()
                .is_some_and(|old| !old.starts_with("v2:"))
        {
            return Err("previous state requires explicit migration".into());
        }
        let description = format!(
            "label={label}\nplatform={platform}\nsource-bytes={}\nprevious={}\n",
            content.bytes,
            previous.as_deref().unwrap_or("none")
        );
        let mut containers = Vec::new();
        if enabled {
            containers.push(DesiredContainer {
                root,
                grant,
                prefix,
                container: ContainerSource::Generated(vec![Entry {
                    path: "environment.txt".into(),
                    mode: 0o644,
                    kind: EntryKind::File(description.into_bytes()),
                }]),
                file_access: policy(ObjectKind::File),
                directory_access: policy(ObjectKind::Directory),
            });
        }
        let state = if enabled { "enabled" } else { "disabled" };
        let versioned = cfg!(feature = "revision-two")
            || previous
                .as_deref()
                .is_some_and(|old| old.starts_with("v2:"));
        Ok(Plan {
            containers,
            state: Some(if versioned {
                format!("v2:{state}")
            } else {
                state.into()
            }),
        })
    }

    fn upgrade_state(previous: String) -> String {
        format!("v2:{previous}")
    }

    fn exact(value: u64) -> u64 {
        value
    }

    fn amplify(count: u32) -> Vec<u8> {
        vec![0; count as usize]
    }

    fn encoded_output(count: u32) -> String {
        assert!(count <= 65536);
        "\0".repeat(count as usize)
    }
}

fn policy(kind: ObjectKind) -> Policy {
    Policy {
        schema: 1,
        kind,
        owner: Rights {
            read: true,
            write: true,
            execute: false,
        },
        everyone: Rights {
            read: true,
            write: false,
            execute: false,
        },
    }
}

export!(Library);
