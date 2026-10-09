// Version-two authoring uses the public typed C API; JSON is backend output only.
package main

/*
#cgo CFLAGS: -I${SRCDIR}/../../../api/c
#cgo LDFLAGS: -lniobium_compiler
#cgo windows LDFLAGS: -lntdll
#include "compiler.h"
#include <stdlib.h>
*/
import "C"
import (
	"fmt"
	"go.starlark.net/starlark"
	"unsafe"
)

type author struct{ handle *C.nbc2_builder }
type object struct {
	owner *author
	value C.nbc2_object
}

func (o *object) String() string        { return "<niobium typed object>" }
func (o *object) Type() string          { return "niobium_object" }
func (o *object) Freeze()               {}
func (o *object) Truth() starlark.Bool  { return true }
func (o *object) Hash() (uint32, error) { return 0, fmt.Errorf("typed objects are not hashable") }

type arena struct {
	pointers []unsafe.Pointer
	bytes    uintptr
	err      error
}

func (s *arena) alloc(size uintptr) unsafe.Pointer {
	if s.err != nil {
		return nil
	}
	if size > (1<<20)-s.bytes {
		s.err = fmt.Errorf("author descriptor allocation limit")
		return nil
	}
	p := C.calloc(1, C.size_t(size))
	if p == nil {
		s.err = fmt.Errorf("author descriptor allocation failed")
		return nil
	}
	s.bytes += size
	s.pointers = append(s.pointers, p)
	return p
}
func (s *arena) close() {
	for _, p := range s.pointers {
		C.free(p)
	}
}
func (s *arena) view(text string) C.nbc2_view {
	if len(text) == 0 {
		return C.nbc2_view{}
	}
	p := s.alloc(uintptr(len(text)))
	if p == nil {
		return C.nbc2_view{}
	}
	copy(unsafe.Slice((*byte)(p), len(text)), text)
	return C.nbc2_view{data: (*C.uint8_t)(p), len: C.size_t(len(text))}
}
func (a *author) check(code C.int32_t) error {
	if code == 0 {
		return nil
	}
	var v C.nbc2_view
	if a.handle != nil {
		C.nbc2_last_error(a.handle, &v)
	}
	return fmt.Errorf("authoring (%d): %s", code, C.GoStringN((*C.char)(unsafe.Pointer(v.data)), C.int(v.len)))
}
func (a *author) close() { C.nbc2_destroy(a.handle); a.handle = nil }
func (a *author) emit() ([]byte, error) {
	var buffer C.nbc2_buffer
	if err := a.check(C.nbc2_emit(a.handle, &buffer)); err != nil {
		return nil, err
	}
	defer C.nbc2_buffer_free(&buffer)
	return C.GoBytes(unsafe.Pointer(buffer.data), C.int(buffer.len)), nil
}
func handle(a *author, v starlark.Value) (C.nbc2_object, error) {
	o, ok := v.(*object)
	if !ok || o.owner != a {
		return C.nbc2_object{}, fmt.Errorf("expected object from current product")
	}
	return o.value, nil
}
func (s *arena) objects(a *author, v starlark.Value) (C.nbc2_objects, error) {
	seq, ok := v.(starlark.Indexable)
	if !ok || seq.Len() > 4096 {
		return C.nbc2_objects{}, fmt.Errorf("bounded object sequence required")
	}
	if seq.Len() == 0 {
		return C.nbc2_objects{}, nil
	}
	ptr := (*C.nbc2_object)(s.alloc(uintptr(seq.Len()) * unsafe.Sizeof(C.nbc2_object{})))
	if ptr == nil {
		return C.nbc2_objects{}, s.err
	}
	dest := unsafe.Slice(ptr, seq.Len())
	for i := range dest {
		x, err := handle(a, seq.Index(i))
		if err != nil {
			return C.nbc2_objects{}, err
		}
		dest[i] = x
	}
	return C.nbc2_objects{data: ptr, len: C.size_t(seq.Len())}, nil
}
func (s *arena) names(v starlark.Value) (C.nbc2_views, error) {
	seq, ok := v.(starlark.Indexable)
	if !ok || seq.Len() > 64 {
		return C.nbc2_views{}, fmt.Errorf("bounded names required")
	}
	if seq.Len() == 0 {
		return C.nbc2_views{}, nil
	}
	ptr := (*C.nbc2_view)(s.alloc(uintptr(seq.Len()) * unsafe.Sizeof(C.nbc2_view{})))
	if ptr == nil {
		return C.nbc2_views{}, s.err
	}
	dest := unsafe.Slice(ptr, seq.Len())
	for i := range dest {
		text, ok := starlark.AsString(seq.Index(i))
		if !ok {
			return C.nbc2_views{}, fmt.Errorf("name must be string")
		}
		dest[i] = s.view(text)
	}
	return C.nbc2_views{data: ptr, len: C.size_t(seq.Len())}, nil
}
func (s *arena) fields(a *author, v starlark.Value) (C.nbc2_fields, error) {
	dict, ok := v.(*starlark.Dict)
	if !ok || dict.Len() > 64 {
		return C.nbc2_fields{}, fmt.Errorf("bounded field dictionary required")
	}
	if dict.Len() == 0 {
		return C.nbc2_fields{}, nil
	}
	ptr := (*C.nbc2_named)(s.alloc(uintptr(dict.Len()) * unsafe.Sizeof(C.nbc2_named{})))
	if ptr == nil {
		return C.nbc2_fields{}, s.err
	}
	dest := unsafe.Slice(ptr, dict.Len())
	for i, pair := range dict.Items() {
		name, ok := starlark.AsString(pair[0])
		if !ok {
			return C.nbc2_fields{}, fmt.Errorf("field name must be string")
		}
		value, err := handle(a, pair[1])
		if err != nil {
			return C.nbc2_fields{}, err
		}
		dest[i] = C.nbc2_named{name: s.view(name), object: value}
	}
	return C.nbc2_fields{data: ptr, len: C.size_t(dict.Len())}, nil
}
func (s *arena) requirements(v starlark.Value) (C.nbc2_requirements, error) {
	dict, ok := v.(*starlark.Dict)
	if !ok || dict.Len() > 64 {
		return C.nbc2_requirements{}, fmt.Errorf("bounded primitive-version dictionary required")
	}
	if dict.Len() == 0 {
		return C.nbc2_requirements{}, nil
	}
	ptr := (*C.nbc2_requirement)(s.alloc(uintptr(dict.Len()) * unsafe.Sizeof(C.nbc2_requirement{})))
	if ptr == nil {
		return C.nbc2_requirements{}, s.err
	}
	dest := unsafe.Slice(ptr, dict.Len())
	for i, pair := range dict.Items() {
		name, ok := starlark.AsString(pair[0])
		if !ok {
			return C.nbc2_requirements{}, fmt.Errorf("primitive name must be string")
		}
		var version uint32
		if err := starlark.AsInt(pair[1], &version); err != nil {
			return C.nbc2_requirements{}, err
		}
		dest[i] = C.nbc2_requirement{id: s.view(name), version: C.uint32_t(version)}
	}
	return C.nbc2_requirements{data: ptr, len: C.size_t(dict.Len())}, nil
}

func (a *author) sourceMap() ([]byte, error) {
	var buffer C.nbc2_buffer
	if err := a.check(C.nbc2_emit_source_map(a.handle, &buffer)); err != nil {
		return nil, err
	}
	defer C.nbc2_buffer_free(&buffer)
	return C.GoBytes(unsafe.Pointer(buffer.data), C.int(buffer.len)), nil
}
func (a *author) location(thread *starlark.Thread, kind string, args starlark.Tuple, kwargs []starlark.Tuple) error {
	switch kind {
	case "input":
		kind = "author-input"
	case "observe":
		kind = "observation"
	case "state_root":
		kind = "root"
	case "upgrade":
		return nil
	}
	var id string
	if len(args) > 0 {
		id, _ = starlark.AsString(args[0])
	} else {
		for _, pair := range kwargs {
			if pair[0] == starlark.String("id") {
				id, _ = starlark.AsString(pair[1])
				break
			}
		}
	}
	if id == "" || thread.CallStackDepth() < 2 {
		return fmt.Errorf("missing source identity")
	}
	frame := thread.CallFrame(1)
	if frame.Pos.Line <= 0 || frame.Pos.Col <= 0 {
		return fmt.Errorf("missing source position")
	}
	var memory arena
	defer memory.close()
	object := memory.view(kind + ":" + id)
	file := memory.view(frame.Pos.Filename())
	if memory.err != nil {
		return memory.err
	}
	return a.check(C.nbc2_location(a.handle, object, file, C.uint32_t(frame.Pos.Line), C.uint32_t(frame.Pos.Col)))
}
