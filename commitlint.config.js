// Extends conventional commits with a relaxed subject-case rule so
// Dependabot's "Bump ..." subjects (start-case) pass without manual edits.
// Still blocks PascalCase and UPPER-CASE subjects, which indicate real anti-patterns.
module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'subject-case': [2, 'never', ['pascal-case', 'upper-case']],
  },
};
