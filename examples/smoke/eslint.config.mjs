// Minimal flat config for the smoke example — core rules only, no plugins,
// so eslint's built-in espree parser handles plain JS and the example stays
// self-contained (real plugin/TS setups are the consumer's concern; see the
// rules_eslint README).
export default [
  {
    files: ['**/*.js'],
    rules: {
      'no-var': 'error',
      'prefer-const': 'error',
      'no-unused-vars': 'error',
    },
  },
];
