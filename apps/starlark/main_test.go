package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// This valid module isolates authoring conformance from the capability engine.
var minimalLibrary = []byte("\x00asm\x01\x00\x00\x00" +
	"\x01\x05\x01\x60\x00\x01\x7f\x03\x02\x01\x00" +
	"\x05\x04\x01\x01\x01\x01" +
	"\x07\x17\x02\x06memory\x02\x00\x0anb_plan_v1\x00\x00" +
	"\x0a\x06\x01\x04\x00\x41\x00\x0b")

func TestAuthoring(t *testing.T) {
	directory := t.TempDir()
	library := filepath.Join(directory, "library.wasm")
	if err := os.WriteFile(library, minimalLibrary, 0600); err != nil {
		t.Fatal(err)
	}
	common := "def declare():\n    for name in [\"z\", \"a\"]:\n        input(name, \"value\")\n"
	if err := os.WriteFile(filepath.Join(directory, "common.star"), []byte(common), 0600); err != nil {
		t.Fatal(err)
	}
	base := "product(\"example.test\", 1, 1)\nlibrary(\"lib\", read_blob(library_path))\n" +
		"instance(\"instance\", \"lib\")\n"
	cases := []struct{ name, source, failure string }{
		{"modules", "load(\"common.star\", \"declare\")\n" + base + "declare()\n", ""},
		{"reference", base + "instance(\"invalid\", \"absent\")\n", "ProgramReference"},
		{"duplicate-product", base + "product(\"other\", 1, 1)\n", "exactly once"},
		{"cycle", "load(\"cycle.star\", \"value\")\n", "module cycle"},
		{"escape", "load(\"../escape.star\", \"value\")\n", "relative to the author root"},
		{"type", base + "input(\"bad\", 42)\n", "expected string or bytes"},
		{"budget", "value = [x for x in range(2000000)]\n", "too many steps"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			path := filepath.Join(directory, c.name+".star")
			if err := os.WriteFile(path, []byte(c.source), 0600); err != nil {
				t.Fatal(err)
			}
			output, err := evaluate(path, library, 1)
			if c.failure != "" {
				if err == nil || !strings.Contains(err.Error(), c.failure) {
					t.Fatalf("wanted %q, got %v", c.failure, err)
				}
			} else if err != nil || !bytes.Contains(output, []byte(`"id":"a"`)) {
				t.Fatalf("module authoring: %s, %v", output, err)
			}
		})
	}
}

func TestBoundedFilesAndExclusiveOutput(t *testing.T) {
	path := filepath.Join(t.TempDir(), "output")
	if err := writeOutput(path, []byte("existing")); err != nil {
		t.Fatal(err)
	}
	if err := writeOutput(path, []byte("replaced")); err == nil {
		t.Fatal("existing output was replaced")
	}
	if _, err := readBounded(path, 3); err == nil {
		t.Fatal("oversized source was accepted")
	}
}
