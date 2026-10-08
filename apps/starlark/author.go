package main

/*
#cgo CFLAGS: -I${SRCDIR}/../../api/c
#cgo LDFLAGS: -lniobium_compiler
#include "compiler.h"
#include <stdlib.h>
*/
import "C"

import (
	"fmt"
	"unsafe"
)

// author owns a single C builder. Its typed operations are the only model backend.
type author struct{ handle *C.nbc_builder }

func view(bytes []byte) (C.nbc_view, func()) {
	if len(bytes) == 0 {
		return C.nbc_view{}, func() {}
	}
	data := C.CBytes(bytes)
	return C.nbc_view{data: (*C.uint8_t)(data), len: C.size_t(len(bytes))}, func() { C.free(data) }
}

func (a *author) check(code C.int32_t) error {
	if code == C.NBC_OK {
		return nil
	}
	var message C.nbc_view
	if a.handle != nil && C.nbc_last_error(a.handle, &message) == C.NBC_OK {
		return fmt.Errorf("authoring (%d): %s", code, C.GoStringN(
			(*C.char)(unsafe.Pointer(message.data)), C.int(message.len)))
	}
	return fmt.Errorf("authoring (%d)", code)
}

func (a *author) create(id string, sequence uint64, version uint32) error {
	if a.handle != nil {
		return fmt.Errorf("product() must be called exactly once")
	}
	name, free := view([]byte(id))
	defer free()
	return a.check(C.nbc_create(C.NBC_ABI_VERSION, name, C.uint64_t(sequence),
		C.uint32_t(version), &a.handle))
}

func (a *author) close() {
	C.nbc_destroy(a.handle)
	a.handle = nil
}

func (a *author) pair(kind, id string, bytes []byte) error {
	name, freeName := view([]byte(id))
	defer freeName()
	data, freeData := view(bytes)
	defer freeData()
	var result C.int32_t
	switch kind {
	case "input":
		result = C.nbc_add_input(a.handle, name, data)
	case "library":
		result = C.nbc_add_library(a.handle, name, data)
	case "asset":
		result = C.nbc_add_asset(a.handle, name, data)
	case "resource":
		result = C.nbc_add_resource(a.handle, name, data)
	default:
		return fmt.Errorf("unknown author entry %q", kind)
	}
	return a.check(result)
}

func (a *author) instance(id, library string, version uint32) error {
	name, freeName := view([]byte(id))
	defer freeName()
	ref, freeRef := view([]byte(library))
	defer freeRef()
	return a.check(C.nbc_add_instance(a.handle, name, ref, C.uint32_t(version)))
}

func (a *author) bind(owner string, kind uint32, id string) error {
	name, freeName := view([]byte(owner))
	defer freeName()
	ref, freeRef := view([]byte(id))
	defer freeRef()
	return a.check(C.nbc_bind(a.handle, name, C.uint32_t(kind), ref))
}

func (a *author) migration(owner, id string, from, to uint32) error {
	instance, freeInstance := view([]byte(owner))
	defer freeInstance()
	name, freeName := view([]byte(id))
	defer freeName()
	return a.check(C.nbc_add_migration(a.handle, instance, name, C.uint32_t(from), C.uint32_t(to)))
}

func (a *author) emit() ([]byte, error) {
	var buffer C.nbc_buffer
	if err := a.check(C.nbc_emit(a.handle, &buffer)); err != nil {
		return nil, err
	}
	defer C.nbc_buffer_free(&buffer)
	return C.GoBytes(unsafe.Pointer(buffer.data), C.int(buffer.len)), nil
}
