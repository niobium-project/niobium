package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestTypedAuthor(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "product.star")
	source := `product(id="reference", release_sequence=1, target="aarch64-macos", profile="niobium.user", primitives={})
def option(enabled):
    if enabled:
        return value("u64", 18446744073709551615)
    return value("u64", 0)
input("count", option(True))
`
	if err := os.WriteFile(path, []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
	bytes, err := evaluate(path, nil)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(bytes), `"uint64":18446744073709551615`) {
		t.Fatal(string(bytes))
	}
}
func TestInvalidTarget(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "invalid.star")
	if err := os.WriteFile(path, []byte(`product(id="reference",release_sequence=1,target="host",profile="x",primitives={})`), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := evaluate(path, nil); err == nil {
		t.Fatal("invalid target accepted")
	}
}

func TestAuthorArgumentsAreBoundedAndImmutable(t *testing.T) {
	var arguments authorArguments
	if err := arguments.Set("target=aarch64-macos"); err != nil {
		t.Fatal(err)
	}
	if err := arguments.Set("target=x86_64-linux"); err == nil {
		t.Fatal("duplicate argument accepted")
	}
	if err := arguments.Set("too_large=" + strings.Repeat("x", 65536)); err == nil {
		t.Fatal("oversize argument accepted")
	}
	directory := t.TempDir()
	path := filepath.Join(directory, "args.star")
	source := `args["target"] = "x86_64-windows"`
	if err := os.WriteFile(path, []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := evaluate(path, arguments.values); err == nil {
		t.Fatal("mutable argument dictionary")
	}
}

func TestInvalidGraphReference(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "reference.star")
	source := `product(id="reference", release_sequence=1, target="aarch64-macos", profile="niobium.user", primitives={})
call(id="missing", library="absent", interface="", function="build")
`
	if err := os.WriteFile(path, []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := evaluate(path, nil); err == nil {
		t.Fatal("missing library reference accepted")
	}
}

func TestSourceMapUsesCallerPositionAndDoesNotChangeModel(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "source.star")
	source := `product(id="reference", release_sequence=1, target="aarch64-macos", profile="niobium.user", primitives={})
input("choice", value("bool", True))
`
	if err := os.WriteFile(path, []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
	var sidecar []byte
	model, err := evaluateOutput(path, nil, &sidecar)
	if err != nil {
		t.Fatal(err)
	}
	expected, err := evaluate(path, nil)
	if err != nil {
		t.Fatal(err)
	}
	if string(model) != string(expected) {
		t.Fatal("source map changed model")
	}
	var decoded struct {
		Schema    uint32 `json:"schema"`
		Locations []struct {
			Object string `json:"object"`
			Source struct {
				File         string `json:"file"`
				Line, Column uint32
			} `json:"source"`
		} `json:"locations"`
	}
	if err := json.Unmarshal(sidecar, &decoded); err != nil {
		t.Fatal(err)
	}
	if len(decoded.Locations) != 2 {
		t.Fatal(string(sidecar))
	}
	if decoded.Locations[1].Object != "author-input:choice" || decoded.Locations[1].Source.File != path || decoded.Locations[1].Source.Line != 2 {
		t.Fatal(string(sidecar))
	}
}
