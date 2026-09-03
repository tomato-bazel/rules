// Package params reads Bazel "multiline" params files.
//
// Bazel switches to a params file when a command line would exceed the OS arg
// limit. Every tool here takes a file list that can grow past it — the driver's
// package graph is several hundred pkg.json paths on a real operator — so they
// all need this. It lives in one place rather than being copy-pasted per tool:
// this repo exists partly because the org's one shared image macro got copied
// repeatedly and the copies drifted.
package params

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

// Expand replaces any @file argument with that file's lines, leaving other
// arguments untouched. The format is one argument per line, verbatim, no quoting
// — what ctx.actions.args() writes with set_param_file_format("multiline").
func Expand(args []string) ([]string, error) {
	out := make([]string, 0, len(args))
	for _, arg := range args {
		if !strings.HasPrefix(arg, "@") {
			out = append(out, arg)
			continue
		}
		lines, err := ReadFile(arg[1:])
		if err != nil {
			return nil, err
		}
		out = append(out, lines...)
	}
	return out, nil
}

// ReadFile reads a params file directly, for tools handed a path rather than an
// @-prefixed argument.
func ReadFile(path string) ([]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("opening params file %q: %w", path, err)
	}
	defer f.Close()

	var out []string
	scanner := bufio.NewScanner(f)
	// Paths are long and numerous; grow the buffer so a deep bazel-out path
	// cannot trip the 64KiB default token limit.
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		if line := strings.TrimSpace(scanner.Text()); line != "" {
			out = append(out, line)
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("reading params file %q: %w", path, err)
	}
	return out, nil
}
