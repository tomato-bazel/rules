"""Pinned upstream toolchain tarballs.

ARM publishes its GNU Toolchain at developer.arm.com under a stable
URL pattern, one tarball per (host, target) pair:

    https://developer.arm.com/-/media/Files/downloads/gnu/
        <version>/binrel/arm-gnu-toolchain-<version>-<host>-<target>.tar.xz

`host_key` is the (os, cpu) pair we resolve from `repository_ctx.os`.
Values are the URL `<host>` segment.

Checksums below are the values arm.com publishes in the
corresponding `.sha256asc` files (one per (host, target) tarball).
Downstream consumers can override per-install via the `integrity`
attr on `arm_gnu_toolchain` if they need a different pin.
"""

# (os, cpu) -> URL host segment as published by arm.com.
HOST_KEYS = {
    ("mac os x", "aarch64"): "darwin-arm64",
    ("mac os x", "x86_64"): "darwin-x86_64",
    ("linux", "x86_64"): "x86_64",
    ("linux", "aarch64"): "aarch64",
}

# version -> {host_segment: sha256}. Pinned from arm.com's
# `.sha256asc` files.
KNOWN_ARM_GNU_VERSIONS = {
    "14.2.rel1": {
        "darwin-arm64": "fc111bb4bb4871e521e3c8a89bd0af51cddfd00fe3f526f4faa09398b7c613f5",
        "darwin-x86_64": "c02735606d69ed000cc8fae2c1467e489e1325c14a7874f553c42f7ef193fc21",
        "x86_64": "eb54c4727440d03199a6af9a6d021e77f45410cad39effce4e5a1c10a88b7f04",
        "aarch64": "c4f0daab43f78e0d56ec2bdad76b98a0223ce12ce7fc51a6ce82f9cc6c6dfba0",
    },
}

# arm.com strips `arm-gnu-toolchain-<version>-<host>-<target>` as the
# top-level dir inside the tarball.
def arm_gnu_url(version, host_segment, target):
    return ("https://developer.arm.com/-/media/Files/downloads/gnu/" +
            "{v}/binrel/arm-gnu-toolchain-{v}-{h}-{t}.tar.xz").format(
        v = version,
        h = host_segment,
        t = target,
    )

def arm_gnu_strip_prefix(version, host_segment, target):
    return "arm-gnu-toolchain-{v}-{h}-{t}".format(
        v = version,
        h = host_segment,
        t = target,
    )
