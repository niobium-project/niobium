// nb-starlark evaluates build-time author programs through authoring C ABI v2.
package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"unicode/utf8"

	"go.starlark.net/starlark"
)

const sourceLimit = 1 << 20
const blobLimit = 256 << 10
const moduleLimit = 64

func main() {
	source := flag.String("source", "", "author program")
	output := flag.String("out", "", "new compiled-model file")
	sourceMap := flag.String("source-map", "", "optional new diagnostic sidecar file")
	var arguments authorArguments
	flag.Var(&arguments, "arg", "immutable author argument key=value (repeatable)")
	flag.Parse()
	if *source == "" || *output == "" || flag.NArg() != 0 {
		fmt.Fprintln(os.Stderr, "usage: nb-starlark --source FILE --out FILE",
			"[--arg KEY=VALUE ...]")
		os.Exit(2)
	}
	var locations []byte
	var sidecar *[]byte
	if *sourceMap != "" {
		sidecar = &locations
	}
	bytes, err := evaluateOutput(*source, arguments.values, sidecar)
	if err == nil {
		err = writeOutput(*output, bytes)
	}
	if err == nil && *sourceMap != "" {
		err = writeOutput(*sourceMap, locations)
	}
	if err != nil {
		if evaluation, ok := err.(*starlark.EvalError); ok {
			fmt.Fprintln(os.Stderr, evaluation.Backtrace())
		} else {
			fmt.Fprintln(os.Stderr, err)
		}
		os.Exit(1)
	}
}

func writeOutput(path string, bytes []byte) error {
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0644)
	if err != nil {
		return err
	}
	_, writeErr := file.Write(bytes)
	closeErr := file.Close()
	if writeErr != nil {
		return writeErr
	}
	return closeErr
}

func readBounded(path string, limit int64) ([]byte, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	bytes, err := io.ReadAll(io.LimitReader(file, limit+1))
	if err == nil && int64(len(bytes)) > limit {
		err = fmt.Errorf("input exceeds %d bytes: %s", limit, path)
	}
	return bytes, err
}

func evaluate(source string, arguments map[string]string) ([]byte, error) {
	return evaluateOutput(source, arguments, nil)
}
func evaluateOutput(source string, arguments map[string]string, sourceMap *[]byte) ([]byte, error) {
	a := &author{}
	defer a.close()
	base, err := filepath.Abs(filepath.Dir(source))
	if err != nil {
		return nil, err
	}
	predeclared := builtins(a)
	input := starlark.NewDict(len(arguments))
	keys := make([]string, 0, len(arguments))
	for key := range arguments {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		if err := input.SetKey(starlark.String(key), starlark.String(arguments[key])); err != nil {
			return nil, err
		}
	}
	input.Freeze()
	predeclared["args"] = input
	thread := &starlark.Thread{Name: "niobium-author"}
	thread.SetMaxExecutionSteps(1_000_000)
	modules := map[string]starlark.StringDict{}
	thread.Load = func(thread *starlark.Thread, module string) (starlark.StringDict, error) {
		if !filepath.IsLocal(module) {
			return nil, fmt.Errorf("module path must be relative to the author root: %q", module)
		}
		key := filepath.Clean(module)
		if globals, found := modules[key]; found {
			if globals == nil {
				return nil, fmt.Errorf("module cycle: %s", module)
			}
			return globals, nil
		}
		if len(modules) >= moduleLimit {
			return nil, fmt.Errorf("module limit exceeded")
		}
		modules[key] = nil
		globals, err := execSource(thread, filepath.Join(base, key), predeclared)
		if err == nil {
			modules[key] = globals
		}
		return globals, err
	}
	if _, err := execSource(thread, source, predeclared); err != nil {
		return nil, err
	}
	model, err := a.emit()
	if err != nil {
		return nil, err
	}
	if sourceMap != nil {
		*sourceMap, err = a.sourceMap()
		if err != nil {
			return nil, err
		}
	}
	return model, nil
}

func execSource(thread *starlark.Thread, path string,
	names starlark.StringDict) (starlark.StringDict, error) {
	bytes, err := readBounded(path, sourceLimit)
	if err != nil {
		return nil, err
	}
	return starlark.ExecFile(thread, path, bytes, names)
}

// Flags supply generic immutable data; products define their own argument vocabulary.
type authorArguments struct {
	values map[string]string
	bytes  int
}

func (a *authorArguments) String() string { return "" }
func (a *authorArguments) Set(input string) error {
	if len(input) > 65536 || len(a.values) >= 64 || a.bytes+len(input) > sourceLimit || !utf8.ValidString(input) {
		return fmt.Errorf("author argument limit or encoding")
	}
	key, value, ok := strings.Cut(input, "=")
	if !ok || len(key) == 0 || len(key) > 256 {
		return fmt.Errorf("argument must be key=value")
	}
	if a.values == nil {
		a.values = map[string]string{}
	}
	if _, found := a.values[key]; found {
		return fmt.Errorf("duplicate argument %q", key)
	}
	a.values[key] = value
	a.bytes += len(input)
	return nil
}
