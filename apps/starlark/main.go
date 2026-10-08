// niobium-starlark evaluates build-time author programs through authoring C ABI v1.
package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"go.starlark.net/starlark"
)

const sourceLimit = 1 << 20
const blobLimit = 256 << 10
const moduleLimit = 64

func main() {
	source := flag.String("source", "", "author program")
	output := flag.String("out", "", "new compiled-model file")
	library := flag.String("library", "", "library path supplied to the author program")
	version := flag.Uint("version", 1, "model version supplied to the author program")
	flag.Parse()
	if *source == "" || *output == "" || flag.NArg() != 0 || *version > 0xffffffff {
		fmt.Fprintln(os.Stderr, "usage: niobium-starlark --source FILE --out FILE",
			"[--library WASM --version N]")
		os.Exit(2)
	}
	bytes, err := evaluate(*source, *library, uint32(*version))
	if err == nil {
		err = writeOutput(*output, bytes)
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

func evaluate(source, library string, version uint32) ([]byte, error) {
	a := &author{}
	defer a.close()
	base, err := filepath.Abs(filepath.Dir(source))
	if err != nil {
		return nil, err
	}
	predeclared := builtins(a)
	predeclared["library_path"] = starlark.String(library)
	predeclared["model_version"] = starlark.MakeUint(uint(version))
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
	return a.emit()
}

func execSource(thread *starlark.Thread, path string,
	names starlark.StringDict) (starlark.StringDict, error) {
	bytes, err := readBounded(path, sourceLimit)
	if err != nil {
		return nil, err
	}
	return starlark.ExecFile(thread, path, bytes, names)
}
