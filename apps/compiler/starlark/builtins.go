package main

/*
#include "compiler.h"
*/
import "C"
import (
	"encoding/hex"
	"fmt"
	"go.starlark.net/starlark"
	"go.starlark.net/starlarkstruct"
	"unsafe"
)

func builtins(a *author) starlark.StringDict {
	names := starlark.StringDict{"value": valueBuiltin(a), "binding": bindingBuiltin(a)}
	for _, name := range []string{"product", "input", "library", "container", "root", "state_root", "grant", "observe", "call", "upgrade"} {
		names[name] = starlark.NewBuiltin(name, func(thread *starlark.Thread, b *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
			var memory arena
			defer memory.close()
			err := entry(a, &memory, b.Name(), args, kwargs)
			if memory.err != nil {
				return nil, memory.err
			}
			if err == nil {
				err = a.location(thread, b.Name(), args, kwargs)
			}
			return starlark.None, err
		})
	}
	names["migration"] = starlark.NewBuiltin("migration", migrationBuiltin)
	names["rights"] = starlark.NewBuiltin("rights", func(_ *starlark.Thread, _ *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
		var read, write, execute bool
		if err := starlark.UnpackArgs("rights", args, kwargs, "read?", &read, "write?", &write, "execute?", &execute); err != nil {
			return nil, err
		}
		var bits int
		if read {
			bits |= 1
		}
		if write {
			bits |= 2
		}
		if execute {
			bits |= 4
		}
		return starlark.MakeInt(bits), nil
	})
	return names
}
func entry(a *author, s *arena, name string, args starlark.Tuple, kwargs []starlark.Tuple) error {
	switch name {
	case "product":
		return product(a, s, args, kwargs)
	case "input":
		var id string
		var v starlark.Value
		if err := starlark.UnpackArgs(name, args, kwargs, "id", &id, "value", &v); err != nil {
			return err
		}
		object, err := handle(a, v)
		if err != nil {
			return err
		}
		return a.check(C.nbc2_input(a.handle, s.view(id), object))
	case "root", "state_root":
		var id string
		scope := "user"
		var err error
		if name == "root" {
			err = starlark.UnpackArgs(name, args, kwargs, "id", &id, "scope?", &scope)
		} else {
			err = starlark.UnpackArgs(name, args, kwargs, "id", &id)
		}
		if err != nil {
			return err
		}
		if name == "state_root" {
			return a.check(C.nbc2_state_root(a.handle, s.view(id)))
		}
		code := uint32(1)
		if scope == "machine" {
			code = 2
		} else if scope != "user" {
			return fmt.Errorf("unknown scope %q", scope)
		}
		return a.check(C.nbc2_root(a.handle, s.view(id), C.uint32_t(code)))
	case "library":
		return library(a, s, args, kwargs)
	case "container":
		return container(a, s, args, kwargs)
	case "grant":
		return grant(a, s, args, kwargs)
	case "observe":
		return observe(a, s, args, kwargs)
	case "call":
		return call(a, s, args, kwargs)
	case "upgrade":
		var id string
		var from, to uint32
		if err := starlark.UnpackArgs(name, args, kwargs, "id", &id, "from_version", &from, "to_version", &to); err != nil {
			return err
		}
		return a.check(C.nbc2_upgrade(a.handle, s.view(id), C.uint32_t(from), C.uint32_t(to)))
	}
	return fmt.Errorf("unknown author operation")
}
func product(a *author, s *arena, args starlark.Tuple, kwargs []starlark.Tuple) error {
	var id, target, profile string
	var sequence uint64
	version := uint32(1)
	primitives := starlark.NewDict(0)
	if err := starlark.UnpackArgs("product", args, kwargs, "id", &id, "release_sequence", &sequence, "target", &target, "profile", &profile, "primitives", &primitives, "model_version?", &version); err != nil {
		return err
	}
	if a.handle != nil {
		return fmt.Errorf("product must be constructed exactly once")
	}
	requirements, err := s.requirements(primitives)
	if err != nil {
		return err
	}
	desc := C.nbc2_profile{id: s.view(profile), target: s.view(target), primitives: requirements}
	if s.err != nil {
		return s.err
	}
	return a.check(C.nbc2_create(2, s.view(id), C.uint64_t(sequence), C.uint32_t(version), &desc, &a.handle))
}
func library(a *author, s *arena, args starlark.Tuple, kwargs []starlark.Tuple) error {
	var id, member, sha string
	var bytes uint64
	requires := starlark.NewDict(0)
	if err := starlark.UnpackArgs("library", args, kwargs, "id", &id, "member", &member, "sha256", &sha, "bytes", &bytes, "requires?", &requires); err != nil {
		return err
	}
	requirements, err := s.requirements(requires)
	if err != nil {
		return err
	}
	desc := C.nbc2_library{id: s.view(id), member: s.view(member), sha256: s.view(sha), bytes: C.uint64_t(bytes), requires: requirements}
	if s.err != nil {
		return s.err
	}
	return a.check(C.nbc2_library_add(a.handle, &desc))
}
func container(a *author, s *arena, args starlark.Tuple, kwargs []starlark.Tuple) error {
	var id, member, sha string
	var bytes uint64
	if err := starlark.UnpackArgs("container", args, kwargs, "id", &id, "member", &member, "sha256", &sha, "bytes", &bytes); err != nil {
		return err
	}
	digest, err := hex.DecodeString(sha)
	if err != nil || len(digest) != 32 {
		return fmt.Errorf("container digest must be 32-byte hex")
	}
	desc := C.nbc2_container{id: s.view(id), member: s.view(member), sha256: s.view(string(digest)), bytes: C.uint64_t(bytes)}
	if s.err != nil {
		return s.err
	}
	return a.check(C.nbc2_container_add(a.handle, &desc))
}
func access(v starlark.Tuple, kind uint32) (C.nbc2_policy, error) {
	if len(v) != 2 {
		return C.nbc2_policy{}, fmt.Errorf("access is (owner rights, everyone rights)")
	}
	var owner, everyone uint32
	if err := starlark.AsInt(v[0], &owner); err != nil {
		return C.nbc2_policy{}, err
	}
	if err := starlark.AsInt(v[1], &everyone); err != nil {
		return C.nbc2_policy{}, err
	}
	return C.nbc2_policy{kind: C.uint32_t(kind), owner: C.uint32_t(owner), everyone: C.uint32_t(everyone)}, nil
}
func grant(a *author, s *arena, args starlark.Tuple, kwargs []starlark.Tuple) error {
	var id, root, prefix, primitive string
	var version, maxEntries uint32
	var maxBytes uint64
	var fileAccess, directoryAccess starlark.Tuple
	if err := starlark.UnpackArgs("grant", args, kwargs, "id", &id, "root", &root, "primitive", &primitive, "version", &version, "max_entries", &maxEntries, "max_bytes", &maxBytes, "file_access", &fileAccess, "directory_access", &directoryAccess, "prefix?", &prefix); err != nil {
		return err
	}
	files, err := access(fileAccess, 1)
	if err != nil {
		return err
	}
	directories, err := access(directoryAccess, 2)
	if err != nil {
		return err
	}
	desc := C.nbc2_grant{id: s.view(id), root: s.view(root), prefix: s.view(prefix), primitive: C.nbc2_requirement{id: s.view(primitive), version: C.uint32_t(version)}, max_entries: C.uint32_t(maxEntries), max_bytes: C.uint64_t(maxBytes), file_access: files, directory_access: directories}
	if s.err != nil {
		return s.err
	}
	return a.check(C.nbc2_grant_add(a.handle, &desc))
}
func observe(a *author, s *arena, args starlark.Tuple, kwargs []starlark.Tuple) error {
	var id, primitive, function, grant string
	var version uint32
	arguments := starlark.Value(starlark.Tuple{})
	if err := starlark.UnpackArgs("observe", args, kwargs, "id", &id, "primitive", &primitive, "version", &version, "function", &function, "arguments?", &arguments, "grant?", &grant); err != nil {
		return err
	}
	objects, err := s.objects(a, arguments)
	if err != nil {
		return err
	}
	desc := C.nbc2_observation{id: s.view(id), function: s.view(function), grant: s.view(grant), primitive: C.nbc2_requirement{id: s.view(primitive), version: C.uint32_t(version)}, arguments: objects}
	if s.err != nil {
		return s.err
	}
	return a.check(C.nbc2_observe(a.handle, &desc))
}
func call(a *author, s *arena, args starlark.Tuple, kwargs []starlark.Tuple) error {
	var id, library, iface, function string
	role := "value"
	version := uint32(1)
	arguments, grants, after, migrations := starlark.Value(starlark.Tuple{}), starlark.Value(starlark.Tuple{}), starlark.Value(starlark.Tuple{}), starlark.Value(starlark.Tuple{})
	if err := starlark.UnpackArgs("call", args, kwargs, "id", &id, "library", &library, "interface", &iface, "function", &function, "arguments?", &arguments, "grants?", &grants, "after?", &after, "state_version?", &version, "result_role?", &role, "migrations?", &migrations); err != nil {
		return err
	}
	objects, err := s.objects(a, arguments)
	if err != nil {
		return err
	}
	grantNames, err := s.names(grants)
	if err != nil {
		return err
	}
	afterNames, err := s.names(after)
	if err != nil {
		return err
	}
	converters, err := s.migrations(migrations)
	if err != nil {
		return err
	}
	var roleCode uint32
	if role == "plan" {
		roleCode = 1
	} else if role != "value" {
		return fmt.Errorf("unknown result role")
	}
	desc := C.nbc2_call{id: s.view(id), library: s.view(library), interface_name: s.view(iface), function: s.view(function), arguments: objects, grants: grantNames, after: afterNames, state_version: C.uint32_t(version), result_role: C.uint32_t(roleCode), migrations: converters}
	if s.err != nil {
		return s.err
	}
	return a.check(C.nbc2_call_add(a.handle, &desc))
}
func migrationBuiltin(_ *starlark.Thread, _ *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
	var id, library, iface, function, sha string
	var from, to uint32
	if err := starlark.UnpackArgs("migration", args, kwargs, "id", &id, "from_version", &from, "to_version", &to, "library", &library, "interface", &iface, "function", &function, "implementation_sha256", &sha); err != nil {
		return nil, err
	}
	return starlarkstruct.FromStringDict(starlark.String("migration"), starlark.StringDict{"id": starlark.String(id), "library": starlark.String(library), "interface": starlark.String(iface), "function": starlark.String(function), "sha256": starlark.String(sha), "from": starlark.MakeUint64(uint64(from)), "to": starlark.MakeUint64(uint64(to))}), nil
}
func (s *arena) migrations(v starlark.Value) (C.nbc2_migrations, error) {
	seq, ok := v.(starlark.Indexable)
	if !ok || seq.Len() > 64 {
		return C.nbc2_migrations{}, fmt.Errorf("bounded migrations required")
	}
	if seq.Len() == 0 {
		return C.nbc2_migrations{}, nil
	}
	ptr := (*C.nbc2_migration)(s.alloc(uintptr(seq.Len()) * unsafe.Sizeof(C.nbc2_migration{})))
	if ptr == nil {
		return C.nbc2_migrations{}, s.err
	}
	dest := unsafe.Slice(ptr, seq.Len())
	for i := range dest {
		item, ok := seq.Index(i).(*starlarkstruct.Struct)
		if !ok || item.Constructor() != starlark.String("migration") {
			return C.nbc2_migrations{}, fmt.Errorf("migration() value required")
		}
		fields := starlark.StringDict{}
		item.ToStringDict(fields)
		text := func(name string) C.nbc2_view { return s.view(string(fields[name].(starlark.String))) }
		var from, to uint32
		if err := starlark.AsInt(fields["from"], &from); err != nil {
			return C.nbc2_migrations{}, err
		}
		if err := starlark.AsInt(fields["to"], &to); err != nil {
			return C.nbc2_migrations{}, err
		}
		dest[i] = C.nbc2_migration{id: text("id"), library: text("library"), interface_name: text("interface"), function: text("function"), implementation_sha256: text("sha256"), from_version: C.uint32_t(from), to_version: C.uint32_t(to)}
	}
	return C.nbc2_migrations{data: ptr, len: C.size_t(seq.Len())}, s.err
}
