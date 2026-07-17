package main

import (
	"path/filepath"
	"strings"
)

// Placeholders rules_go's aspect bakes into every path it emits. See
// gopackagesdriver/pkgjson/pkg_json.bzl:file_path — the prefix is chosen by
// FILE KIND:
//
//	generated file        -> __BAZEL_EXECROOT__/<f.path>
//	main-repo source      -> __BAZEL_WORKSPACE__/<f.path>
//	external-repo source  -> __BAZEL_OUTPUT_BASE__/<f.path>
const (
	execrootPlaceholder   = "__BAZEL_EXECROOT__"
	workspacePlaceholder  = "__BAZEL_WORKSPACE__"
	outputBasePlaceholder = "__BAZEL_OUTPUT_BASE__"
)

// execrootResolver rewrites all three placeholders to the current directory.
//
// The three exist because rules_go's driver serves an IDE, which runs OUTSIDE
// the execroot and must therefore be told three different absolute roots (via
// `bazel info`, another subprocess we can't make). We are not an IDE: we run
// INSIDE a sandboxed action, whose cwd IS the execroot.
//
// And `file_path` joins each prefix to `f.path`, which is always
// execroot-relative — `bazel-out/...` for generated files, `examples/...` for
// main-repo sources, `external/<repo>/...` for external ones. Every input is
// staged at exactly that path under the sandbox root. So all three collapse to
// the same answer here: ".".
//
// This is the one place the design depends on running as an action rather than
// via `bazel run`, and it is why it gets simpler rather than harder.
func execrootResolver(p string) string {
	for _, placeholder := range []string{execrootPlaceholder, workspacePlaceholder, outputBasePlaceholder} {
		if strings.HasPrefix(p, placeholder) {
			// filepath.Clean drops the "./" that a naive Replace would leave,
			// so paths compare equal to the ones controller-tools derives.
			return filepath.Clean(strings.Replace(p, placeholder, ".", 1))
		}
	}
	return p
}
