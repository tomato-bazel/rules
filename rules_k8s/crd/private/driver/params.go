package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"
)

// readParamsFile reads a Bazel "multiline" params file: one path per line,
// verbatim, no quoting. Matches what ctx.actions.args() writes with
// set_param_file_format("multiline").
//
// The pkg.json list rides in a file rather than the environment because a real
// operator's transitive closure is several hundred packages (the prototype's was
// 267), which is well past a comfortable env-var size.
func readParamsFile(path string) ([]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("opening params file %q: %w", path, err)
	}
	defer f.Close()

	var out []string
	scanner := bufio.NewScanner(f)
	// Paths are long and numerous; grow the buffer so a deep bazel-out path
	// can't trip the 64KiB default token limit.
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		out = append(out, line)
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("reading params file %q: %w", path, err)
	}
	return out, nil
}

// writeJSON emits the DriverResponse. go/packages reads stdout as JSON and
// nothing else, so anything chatty must go to stderr or it corrupts the reply.
func writeJSON(w io.Writer, v any) error {
	enc := json.NewEncoder(w)
	if err := enc.Encode(v); err != nil {
		return fmt.Errorf("encoding driver response: %w", err)
	}
	return nil
}
