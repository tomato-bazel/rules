// Minimal Next.js config — exercises rules_nextjs's `next_build` +
// `next_standalone`, not Next.js config behavior.
//
// `outputFileTracingRoot` must be the Bazel *output base* (the common ancestor
// of `/sandbox/` and `/execroot/`) so Next's standalone tracer captures the
// full aspect_rules_js content store. Anything narrower drops transitive deps
// (e.g. `styled-jsx`) from `.next/standalone`, and the standalone server fails
// to resolve them at runtime. The `next_build` action surfaces the (absolute)
// bindir as `BAZEL_BINDIR`; slice it at the first sandbox/execroot marker.
// Outside Bazel this falls back to the cwd.
const bazelBindir = process.env.BAZEL_BINDIR;
let outputFileTracingRoot = process.cwd();
if (bazelBindir) {
  const markers = ['/sandbox/', '/execroot/']
    .map((m) => bazelBindir.indexOf(m))
    .filter((i) => i !== -1);
  if (markers.length) {
    outputFileTracingRoot = bazelBindir.slice(0, Math.min(...markers));
  }
}

/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
  outputFileTracingRoot,
};

export default nextConfig;
