// Copyright 2021 The Bazel Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Vendored from rules_go go/tools/gopackagesdriver/bazel.go — ONLY the version
// value type. The rest of that file drives a `bazel` subprocess, which is the
// exact thing this driver exists to not do.
//
// PackageRegistry gates one behavior on the Bazel version (>= 6.0.0 changed
// external-repo path layout). Inside an action we have no Bazel to ask, so
// callers pass the zero value, which isAtLeast treats as "newest" — see
// newRegistryVersion in main.go.

package main

type bazelVersion [3]int

func (a bazelVersion) compare(b bazelVersion) int {
	for i := 0; i < len(a); i++ {
		if c := a[i] - b[i]; c != 0 {
			return c
		}
	}
	return 0
}

// isAtLeast returns true if a.compare(b) >= 0 (that is, if a is greater than
// or equal to b) or if a is the zero value.
//
// Development versions of Bazel do not have valid version strings, not even a
// prerelease, so parseBazelVersion fails and returns the zero value. If we
// have such a version, we assume it's newer than whatever we're comparing
// it with.
func (a bazelVersion) isAtLeast(b bazelVersion) bool {
	return a.compare(b) >= 0 || a == bazelVersion{}
}
