// Command k8s-crd-driver is a go/packages external driver that answers entirely
// from a frozen list of Bazel-produced pkg.json files.
//
// WHY THIS EXISTS
//
// controller-gen loads Go types through go/packages, which normally shells out
// to `go list` and needs the whole module graph on disk. That cannot run in a
// Bazel action: the sandbox has no network and no module cache. rules_go's own
// gopackagesdriver escapes that by shelling out to `bazel query` — which an
// action cannot do either, because you cannot run Bazel inside Bazel.
//
// But inside a rule we already know the package graph: `go_pkg_info_aspect`
// emits it as declared outputs (one pkg.json per package, plus the stdlib's).
// So this driver reads that list and never consults the go command, the network,
// the module cache, or Bazel. Point GOPACKAGESDRIVER at it and controller-gen
// runs as an ordinary, cacheable, remotable action.
//
// This works only because controller-tools asks go/packages for METADATA ONLY
// (NeedName|NeedFiles|NeedCompiledGoFiles|NeedImports|NeedTypesSizes — see
// controller-tools/pkg/loader/loader.go). It type-checks itself from
// CompiledGoFiles. go/packages is a pure metadata channel here, so a driver that
// serves file paths is a complete answer. A consumer that asked for NeedTypes
// with NeedDeps off would want export data instead, and this driver would need
// to grow ExportFile handling.
//
// PROTOCOL
//
// go/packages executes GOPACKAGESDRIVER as a bare program path with the patterns
// as argv, so there is nowhere to pass our own flags. The package-graph file list
// therefore arrives out of band, via the environment:
//
//	K8S_CRD_DRIVER_PKG_JSON  path to a params file, one pkg.json path per line
//	                         (required; a real operator's closure is hundreds of
//	                         paths, well past a comfortable env/arg limit)
//	RULES_GO_STDLIB_LABEL    optional; see stdlib.go
//	GOTAGS                   optional; build tags (read by build_context.go)
//
//	stdin   a packages.DriverRequest (JSON)
//	argv    the patterns to resolve (package IDs / labels)
//	stdout  a packages.DriverResponse (JSON), and nothing else
package main

import (
	"fmt"
	"os"

	"golang.org/x/tools/go/packages"
)

const pkgJSONEnv = "K8S_CRD_DRIVER_PKG_JSON"

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "k8s-crd-driver: %v\n", err)
		os.Exit(1)
	}
}

func run(patterns []string) error {
	paramsFile := os.Getenv(pkgJSONEnv)
	if paramsFile == "" {
		return fmt.Errorf("%s is unset: the driver has no package graph to serve. "+
			"It is meant to be invoked by go/packages from inside a k8s_crd_library "+
			"action, which sets it", pkgJSONEnv)
	}
	pkgJSONFiles, err := readParamsFile(paramsFile)
	if err != nil {
		return err
	}
	if len(pkgJSONFiles) == 0 {
		return fmt.Errorf("%s (%s) is empty: the rule collected no pkg.json files, so "+
			"the aspect saw no Go packages under deps", pkgJSONEnv, paramsFile)
	}

	// The DriverRequest must be consumed even though the fields we could act on
	// don't apply: the graph is already frozen, and rules_go's own driver ignores
	// BuildFlags too (it reads tags from GOTAGS). Overlays ARE honored — they cost
	// nothing and go/packages may legitimately send them.
	req, err := ReadDriverRequest(os.Stdin)
	if err != nil {
		return err
	}

	driver, err := NewJSONPackagesDriver(pkgJSONFiles, execrootResolver, newRegistryVersion(), req.Overlay)
	if err != nil {
		return fmt.Errorf("building the package registry: %w", err)
	}

	resp := driver.GetResponse(patterns)
	if len(resp.Roots) == 0 {
		return fmt.Errorf("no roots matched %q. The rule asked for a package that is not in "+
			"the graph the aspect collected — check it is reachable from deps via deps/embed. "+
			"(%d pkg.json files were loaded)", patterns, len(pkgJSONFiles))
	}
	if err := checkRootsAreUsable(resp); err != nil {
		return err
	}
	return writeJSON(os.Stdout, resp)
}

// newRegistryVersion returns the Bazel version PackageRegistry gates its
// external-repo path handling on. Inside an action there is no Bazel to ask, so
// we pass the zero value: isAtLeast treats it as "at least everything", which
// selects the >= 6.0.0 layout. Every Bazel that can run bzlmod is >= 6, so that
// is the only reachable branch anyway.
func newRegistryVersion() bazelVersion { return bazelVersion{} }


// checkRootsAreUsable rejects a response whose roots resolved by ID but carry no
// usable source.
//
// Matching a root is NOT evidence the graph is good: Match() looks packages up by
// ID, which never touches disk. But build_context.go's filterSourceFilesForTags
// calls buildContext.MatchFile, whose error return is discarded upstream — so a
// file that is MISSING is indistinguishable from one excluded by a build tag, and
// both silently vanish from CompiledGoFiles. ResolvePaths runs before
// ResolveImports, so pkg.Name (which is backfilled by PARSING those files) then
// vanishes too.
//
// The result was the worst possible outcome: exit 0, empty stderr, and
// controller-tools generating either nothing or a CRD under the wrong version —
// because it derives the CRD's version from pkg.Name.
//
// So assert the invariant that actually matters: every ROOT must have source to
// read and a name to derive a version from.
func checkRootsAreUsable(resp *packages.DriverResponse) error {
	byID := map[string]*packages.Package{}
	for _, p := range resp.Packages {
		byID[p.ID] = p
	}
	for _, id := range resp.Roots {
		p, ok := byID[id]
		if !ok {
			return fmt.Errorf("root %q resolved but is absent from the response — the package "+
				"graph is inconsistent", id)
		}
		if len(p.CompiledGoFiles) == 0 && len(p.GoFiles) == 0 {
			return fmt.Errorf("root %q has no source files. Its pkg.json named files that could "+
				"not be read (a missing input, or every file excluded by build tags). "+
				"controller-tools would emit nothing and exit 0, so failing here instead", id)
		}
		if p.Name == "" {
			return fmt.Errorf("root %q has no package name. It is backfilled by parsing the "+
				"package clause, so this means the source could not be read — and "+
				"controller-tools derives the CRD's VERSION from it, so it would emit a CRD "+
				"under the wrong apiVersion", id)
		}
	}
	return nil
}
