package main

import (
	"fmt"

	"go.starlark.net/starlark"
)

func builtins(a *author) starlark.StringDict {
	names := starlark.StringDict{}
	names["product"] = starlark.NewBuiltin("product", func(_ *starlark.Thread,
		_ *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
		var id string
		var sequence uint64
		var version uint32
		err := starlark.UnpackArgs("product", args, kwargs, "id", &id,
			"release_sequence", &sequence, "model_version", &version)
		if err == nil {
			err = a.create(id, sequence, version)
		}
		return starlark.None, err
	})
	for _, kind := range []string{"input", "library", "asset", "resource"} {
		names[kind] = entryBuiltin(a, kind)
	}
	names["read_blob"] = starlark.NewBuiltin("read_blob", readBlob)
	names["instance"] = instanceBuiltin(a)
	names["migration"] = migrationBuiltin(a)
	return names
}

func entryBuiltin(a *author, kind string) *starlark.Builtin {
	return starlark.NewBuiltin(kind, func(_ *starlark.Thread, _ *starlark.Builtin,
		args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
		var id string
		var data starlark.Value
		if err := starlark.UnpackArgs(kind, args, kwargs, "id", &id, "value", &data); err != nil {
			return nil, err
		}
		var bytes []byte
		switch value := data.(type) {
		case starlark.String:
			bytes = []byte(string(value))
		case starlark.Bytes:
			bytes = []byte(string(value))
		default:
			return nil, fmt.Errorf("%s: expected string or bytes, got %s", kind, data.Type())
		}
		return starlark.None, a.pair(kind, id, bytes)
	})
}

func readBlob(_ *starlark.Thread, _ *starlark.Builtin,
	args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
	var path string
	if err := starlark.UnpackArgs("read_blob", args, kwargs, "path", &path); err != nil {
		return nil, err
	}
	bytes, err := readBounded(path, blobLimit)
	return starlark.Bytes(bytes), err
}

func instanceBuiltin(a *author) *starlark.Builtin {
	return starlark.NewBuiltin("instance", func(_ *starlark.Thread, _ *starlark.Builtin,
		args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
		var id, library string
		version := uint32(1)
		inputs, assets, resources := starlark.NewList(nil), starlark.NewList(nil), starlark.NewList(nil)
		if err := starlark.UnpackArgs("instance", args, kwargs, "id", &id, "library", &library,
			"state_version?", &version, "inputs?", &inputs, "assets?", &assets,
			"resources?", &resources); err != nil {
			return nil, err
		}
		if err := a.instance(id, library, version); err != nil {
			return nil, err
		}
		for index, list := range []*starlark.List{inputs, assets, resources} {
			if list.Len() > 64 {
				return nil, fmt.Errorf("instance binding limit exceeded")
			}
			for i := 0; i < list.Len(); i++ {
				ref, ok := starlark.AsString(list.Index(i))
				if !ok {
					return nil, fmt.Errorf("instance binding must be a string")
				}
				if err := a.bind(id, uint32(index+1), ref); err != nil {
					return nil, err
				}
			}
		}
		return starlark.None, nil
	})
}

func migrationBuiltin(a *author) *starlark.Builtin {
	return starlark.NewBuiltin("migration", func(_ *starlark.Thread, _ *starlark.Builtin,
		args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
		var id, owner string
		var from, to uint32
		if err := starlark.UnpackArgs("migration", args, kwargs, "id", &id,
			"from_version", &from, "to_version", &to, "owner?", &owner); err != nil {
			return nil, err
		}
		return starlark.None, a.migration(owner, id, from, to)
	})
}
