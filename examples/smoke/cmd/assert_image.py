"""Assert the operator image is correct in the ways that fail SILENTLY.

Both checks here describe a build that is green, a push that is green, and a
CrashLoopBackOff at 3am:

  1. config.architecture/os say linux/amd64 AND the shipped binary really is an
     ELF x86-64 — the image config inherits arch from the BASE, so it can claim
     amd64 while carrying a host-arch binary if the platform transition stops
     firing.
  2. config.Entrypoint names a file that actually EXISTS in a layer. It used to
     be derived from the label name while the file was packaged under its real
     basename; an `alias` or an `out =` binary made those differ.

Written in Python rather than bash because the earlier bash version parsed the
config with sed, failed to find it, and would have been "fixed" by loosening the
grep — a test that cannot locate its subject is a test that passes for the wrong
reason.
"""
import json
import os
import pathlib
import sys
import tarfile


def fail(msg):
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def main():
    layout = pathlib.Path(os.environ["LAYOUT"])
    blobs = sorted((layout / "blobs" / "sha256").iterdir())
    if not blobs:
        fail(f"no blobs under {layout}")

    config = None
    for b in blobs:
        try:
            d = json.loads(b.read_text())
        except Exception:
            continue
        if isinstance(d, dict) and "architecture" in d and "config" in d:
            config = d
            break
    if config is None:
        fail(f"no image config among {len(blobs)} blobs under {layout}")

    # 1a. The image's declared platform.
    arch, osname = config.get("architecture"), config.get("os")
    if (osname, arch) != ("linux", "amd64"):
        fail(f"image declares {osname}/{arch}, want linux/amd64")

    entrypoint = config.get("config", {}).get("Entrypoint") or []
    if not entrypoint:
        fail("image config has no Entrypoint")
    want = entrypoint[0].lstrip("/")

    # 2. The entrypoint must exist in a layer.
    found_member, layer = None, None
    for b in blobs:
        try:
            with tarfile.open(b) as t:
                for m in t.getnames():
                    if m.lstrip("./") == want:
                        found_member, layer = m, b
                        break
        except Exception:
            continue
        if found_member:
            break

    if not found_member:
        contents = []
        for b in blobs:
            try:
                with tarfile.open(b) as t:
                    contents += [n for n in t.getnames() if "bin/" in n]
            except Exception:
                pass
        fail(
            f"Entrypoint is {entrypoint[0]!r}, but no layer contains it.\n"
            f"      This image builds and pushes green, then CrashLoopBackOffs.\n"
            f"      Layers carry: {contents}"
        )

    # 1b. The binary really is ELF x86-64 — not merely claimed by the base's config.
    with tarfile.open(layer) as t:
        data = t.extractfile(found_member).read(20)
    if data[:4] != b"\x7fELF":
        fail(
            f"the shipped binary is not ELF (magic={data[:4]!r}) — the platform "
            f"transition did not fire, so this image cannot exec in the cluster"
        )
    if data[18] != 0x3E:
        fail(f"ELF e_machine=0x{data[18]:02x}, want 0x3e (x86-64)")

    print(
        f"OK: image is {osname}/{arch}; Entrypoint {entrypoint[0]!r} exists in a layer "
        f"and is ELF x86-64 (built on {os.uname().machine}, no --platforms flag)."
    )


if __name__ == "__main__":
    main()
