#!/usr/bin/env python3
"""Build a deterministic tar layer for `systemd_layer`.

Reads a manifest JSON describing regular files, symlinks, and the
directories they imply, and writes:
  * a reproducible USTAR tarball (sorted entries, mtime=0, uid/gid=0,
    empty uname/gname) consumable by `oci_image(tars=[...])`, and
  * a human-readable `.listing.txt` sidecar for golden tests.

Manifest schema:
  {
    "files":    [{"path": "/etc/systemd/system/x.service",
                  "src": "<exec path>", "mode": 420}],
    "symlinks": [{"path": "/etc/systemd/system/multi-user.target.wants/x.service",
                  "target": "../x.service"}]
  }

Determinism here is what makes the layer (and the golden tests over it)
stable across machines, independent of the host tar implementation.
"""

import io
import json
import sys
import tarfile


def _parents(path):
    """Yield each ancestor directory of an absolute path, shallow-to-deep."""
    parts = path.strip("/").split("/")
    cur = ""
    for part in parts[:-1]:
        cur += "/" + part
        yield cur.lstrip("/")


def _info(name, mode):
    ti = tarfile.TarInfo(name=name)
    ti.mode = mode
    ti.mtime = 0
    ti.uid = 0
    ti.gid = 0
    ti.uname = ""
    ti.gname = ""
    return ti


def main():
    manifest_path, tar_path, listing_path = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(manifest_path) as f:
        manifest = json.load(f)

    files = manifest.get("files", [])
    symlinks = manifest.get("symlinks", [])

    dirs = set()
    for entry in files:
        dirs.update(_parents(entry["path"]))
    for entry in symlinks:
        dirs.update(_parents(entry["path"]))

    listing = []
    with tarfile.open(tar_path, "w", format=tarfile.USTAR_FORMAT) as tar:
        for d in sorted(dirs):
            ti = _info(d + "/", 0o755)
            ti.type = tarfile.DIRTYPE
            tar.addfile(ti)
            listing.append("d 0755 /{}/".format(d))

        for entry in sorted(files, key=lambda e: e["path"]):
            with open(entry["src"], "rb") as sf:
                data = sf.read()
            mode = entry.get("mode", 0o644)
            ti = _info(entry["path"].lstrip("/"), mode)
            ti.size = len(data)
            tar.addfile(ti, io.BytesIO(data))
            listing.append("f {:04o} {}".format(mode, entry["path"]))

        for entry in sorted(symlinks, key=lambda e: e["path"]):
            ti = _info(entry["path"].lstrip("/"), 0o777)
            ti.type = tarfile.SYMTYPE
            ti.linkname = entry["target"]
            tar.addfile(ti)
            listing.append("l {} -> {}".format(entry["path"], entry["target"]))

    with open(listing_path, "w") as f:
        f.write("\n".join(listing) + "\n")


if __name__ == "__main__":
    main()
