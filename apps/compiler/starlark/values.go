package main

/*
#include "compiler.h"
*/
import "C"
import (
	"fmt"
	"go.starlark.net/starlark"
)

func valueBuiltin(a *author) *starlark.Builtin {
	return starlark.NewBuiltin("value", func(_ *starlark.Thread, _ *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
		var tag string
		data := starlark.Value(starlark.None)
		label := ""
		success := true
		if err := starlark.UnpackArgs("value", args, kwargs, "type", &tag, "data?", &data, "label?", &label, "success?", &success); err != nil {
			return nil, err
		}
		var memory arena
		defer memory.close()
		var desc C.nbc2_value_desc
		tags := map[string]uint32{"bool": 1, "u8": 2, "u16": 3, "u32": 4, "u64": 5, "s8": 6, "s16": 7, "s32": 8, "s64": 9, "f32": 10, "f64": 11, "char": 12, "string": 13, "bytes": 14, "list": 15, "tuple": 16, "record": 17, "variant": 18, "enum": 19, "option": 20, "result": 21, "flags": 22}
		code, ok := tags[tag]
		if !ok {
			return nil, fmt.Errorf("unknown value type %q", tag)
		}
		desc.tag = C.uint32_t(code)
		if err := fillValue(a, &memory, &desc, data, label, success); err != nil {
			return nil, err
		}
		if memory.err != nil {
			return nil, memory.err
		}
		var out C.nbc2_object
		if err := a.check(C.nbc2_value(a.handle, &desc, &out)); err != nil {
			return nil, err
		}
		return &object{a, out}, nil
	})
}
func fillValue(a *author, s *arena, d *C.nbc2_value_desc, v starlark.Value, label string, success bool) error {
	switch uint32(d.tag) {
	case 1:
		b, ok := v.(starlark.Bool)
		if !ok {
			return fmt.Errorf("bool required")
		}
		if b {
			d.flags = 1
		}
	case 2, 3, 4, 5, 12:
		var n uint64
		if err := starlark.AsInt(v, &n); err != nil {
			return err
		}
		d.unsigned_value = C.uint64_t(n)
	case 6, 7, 8, 9:
		var n int64
		if err := starlark.AsInt(v, &n); err != nil {
			return err
		}
		d.signed_value = C.int64_t(n)
	case 10, 11:
		n, ok := v.(starlark.Float)
		if !ok {
			return fmt.Errorf("float required")
		}
		d.number = C.double(n)
	case 13, 19:
		text, ok := starlark.AsString(v)
		if !ok {
			return fmt.Errorf("string required")
		}
		d.text = s.view(text)
	case 14:
		data, ok := v.(starlark.Bytes)
		if !ok {
			return fmt.Errorf("bytes required")
		}
		d.text = s.view(string(data))
	case 15, 16:
		items, err := s.objects(a, v)
		if err != nil {
			return err
		}
		d.items = items
	case 17:
		fields, err := s.fields(a, v)
		if err != nil {
			return err
		}
		d.fields = fields
	case 18, 20, 21:
		d.text = s.view(label)
		if success {
			d.flags = 1
		}
		if v != starlark.None {
			item, err := handle(a, v)
			if err != nil {
				return err
			}
			d.payload = item
		}
	case 22:
		names, err := s.names(v)
		if err != nil {
			return err
		}
		d.names = names
	}
	return nil
}
func bindingBuiltin(a *author) *starlark.Builtin {
	return starlark.NewBuiltin("binding", func(_ *starlark.Thread, _ *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
		var tag string
		data := starlark.Value(starlark.None)
		projection := starlark.Value(starlark.Tuple{})
		if err := starlark.UnpackArgs("binding", args, kwargs, "type", &tag, "data?", &data, "fields?", &projection); err != nil {
			return nil, err
		}
		tags := map[string]uint32{"literal": 1, "input": 2, "node_result": 3, "observation": 4, "previous_state": 5, "record": 6, "list": 7, "tuple": 8, "some": 9}
		code, ok := tags[tag]
		if !ok {
			return nil, fmt.Errorf("unknown binding type %q", tag)
		}
		var memory arena
		defer memory.close()
		desc := C.nbc2_binding_desc{tag: C.uint32_t(code)}
		var err error
		switch code {
		case 1, 9:
			desc.payload, err = handle(a, data)
		case 2, 3, 4:
			name, ok := starlark.AsString(data)
			if !ok {
				return nil, fmt.Errorf("binding reference must be string")
			}
			desc.reference = memory.view(name)
			desc.projection, err = memory.names(projection)
		case 6:
			desc.fields, err = memory.fields(a, data)
		case 7, 8:
			desc.items, err = memory.objects(a, data)
		}
		if err != nil {
			return nil, err
		}
		if memory.err != nil {
			return nil, memory.err
		}
		var out C.nbc2_object
		if err = a.check(C.nbc2_binding(a.handle, &desc, &out)); err != nil {
			return nil, err
		}
		return &object{a, out}, nil
	})
}
