// A source with no violations under eslint.config.mjs. `eslint_test` over
// this file must exit 0 — the release gate for the macro wiring.
export function add(a, b) {
  const sum = a + b;
  return sum;
}
