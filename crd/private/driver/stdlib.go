package main

import "os"

// RulesGoStdlibLabel is the meta-label PackageRegistry.Match special-cases: when
// a caller asks for it, every stdlib subpackage becomes a root, because the
// label itself never appears as an ID in the stdlib pkg.json.
//
// In rules_go this is `rulesGoRepositoryName + "//:stdlib"`, where the repo name
// is injected via x_defs at link time. We can't do that — the value depends on
// the CONSUMER's module graph, not ours — so it's an env var the rule sets, with
// a default that matches bzlmod's canonical name for rules_go.
//
// In practice this is inert: k8s_crd_library asks for the operator's API package
// as the root, never for the stdlib. The stdlib pkg.json is supplied so imports
// RESOLVE (gotcha: the aspect's Imports map omits stdlib edges), not so it can be
// requested. It's kept faithful anyway — a driver that silently mishandles a
// documented pattern is worse than one that never sees it.
var RulesGoStdlibLabel = stdlibLabel()

func stdlibLabel() string {
	if v := os.Getenv("RULES_GO_STDLIB_LABEL"); v != "" {
		return v
	}
	return "@@rules_go~//:stdlib"
}
