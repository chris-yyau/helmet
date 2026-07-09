// Merged from the former commitlint.config.js + .mjs (audit 2026-07-10).
// - subject-case relaxed so Dependabot's start-case "Bump ..." titles pass: the
//   PR-title lint sees only the title, which carries no dependabot trailer, so
//   the `ignores` rule below cannot cover it. PascalCase/UPPER-CASE still blocked.
// - body-max-line-length is off (Dependabot commit bodies run long); the `ignores`
//   rule skips lint entirely for Dependabot-signed commits, so hand-written commits
//   still get every rule except body length. The trailer is not cryptographically
//   bound — this is a commit-message format gate, not a security control.
export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'subject-case': [2, 'never', ['pascal-case', 'upper-case']],
    'body-max-line-length': [0, 'always'],
  },
  ignores: [
    (message) => message.includes('Signed-off-by: dependabot[bot]'),
  ],
};
