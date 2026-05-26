# rules_cc_cross — Roadmap

Hermetic ARM/RISC-V/x86 cross-compiler toolchains.

## Shipped (v0.1.0)

- `aarch64-none-elf` via ARM GNU Toolchain 14.2.rel1.
- All four (host, target) sha256s pinned from arm.com's
  `.sha256asc` files.
- `cross_cc_toolchain_config` with `-ffreestanding`, `-nostdlib`,
  `-no-canonical-prefixes`, `-fno-canonical-system-headers` defaults
  — needed so gcc's `-MD` output uses exec-root-relative paths
  Bazel's "no absolute path inclusions" check can match.
- Smoke example: `//examples/aarch64_hello:hello` cross-compiles
  cleanly via `--platforms=//examples/aarch64_hello:aarch64_none_elf`.
- Verified end-to-end as the cc toolchain that compiles microkit
  PDs in the `rules_microkit` vertical slice.

## v0.2.0 — `riscv64-elf` target

- Add `riscv64-elf` to `_TARGET_CPU` in `cc_cross/private/arm_gnu_toolchain.bzl`.
  Riscv toolchain comes from a different upstream (`riscv-collab/riscv-gnu-toolchain`
  releases). URLs + sha256s per (host, target) follow the same
  pattern; add a `riscv_gnu_toolchain` repo rule or generalize
  `arm_gnu_toolchain` to dispatch.
- Same `cc_toolchain_config` works (just different `target_system_name`
  + `target_cpu = "riscv64"`).
- Smoke: cross-compile a RISC-V freestanding hello.

## v0.3.0 — `x86_64-elf` target

- Toolchain source TBD. Options:
  - llvm-mingw releases (x86_64-w64-mingw32 close, but not -elf).
  - Crosstool-NG generated tarballs hosted by fastverk.
  - Build from source via rules_foreign_cc (heavy).
- Useful for microkit's qemu_virt_x86_64 platform path.

## v0.4.0 — libc selectors

- `cross_cc_toolchain_config(libc = "newlib"|"newlib_nano"|"picolibc")`.
- Adds matching `-specs=...` linker flags.
- Today's default `-nostdlib` works for seL4/microkit PDs; libc
  matters for non-microkit bare-metal apps.

## v0.5.0 — Clang/LLD alternative

- Some PDs (rust-sel4, microkit Rust example) need clang. Add an
  `llvm_cross_toolchain` analogue using a pinned LLVM release.
- Compatible with the existing `cross_cc_toolchain_config` shape.

## Known issues / TODO

- **Hard-coded `gcc_version = "14.2.1"`** in `cross_cc_toolchain_config`'s
  attr default. Should auto-discover from the install dir at repo
  rule time — currently a consumer pinning a different ARM
  toolchain version (e.g. `13.3.rel1`) would silently get
  unresolved builtin-include paths.
- **No exec_compatible_with constraint** on the cc_toolchain. Could
  fail at toolchain-resolution time on unsupported hosts (only
  macOS arm64/x86_64 + Linux x86_64/aarch64 in `HOST_KEYS`). Add
  explicit `exec_compatible_with = [@platforms//cpu:...]` once we
  decide policy.
- **CI** ships the scaffold's macOS + Ubuntu matrix. No actual
  cross-compile job yet — should add an `examples/aarch64_hello`
  build under both runners to catch regressions.

## Cross-repo impact

- `rules_microkit` depends on `rules_cc_cross` (forwards its
  extension). Any breaking change to `cross_cc_toolchain_config`
  flows through.
- Future `rules_chisel`/`rules_riscv_core` builds may compile
  C/C++ glue using this toolchain — riscv64 target especially.

## Release checklist

- [ ] `bazel test //...` clean on the existing example.
- [ ] `bazel build //examples/aarch64_hello:hello --platforms=//examples/aarch64_hello:aarch64_none_elf`
      green on a fresh machine.
- [ ] `git tag v0.1.0 && git push --tags`.
- [ ] `rels release` against the registry.
