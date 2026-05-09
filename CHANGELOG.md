# [1.18.0](https://github.com/chris-yyau/helmet/compare/v1.17.0...v1.18.0) (2026-05-09)


### Features

* **helmet:** detect cross-workflow check-name collisions in required-checks lint ([#36](https://github.com/chris-yyau/helmet/issues/36)) ([9bd0fa8](https://github.com/chris-yyau/helmet/commit/9bd0fa88daea432043c4e7dd5b6bef806d4d5b10)), closes [#35](https://github.com/chris-yyau/helmet/issues/35)
* **helmet:** required-checks lock + drift detector + spec-precision pass ([#35](https://github.com/chris-yyau/helmet/issues/35)) ([c80dd39](https://github.com/chris-yyau/helmet/commit/c80dd39c97a94b6962c49817be55e57622a01d80)), closes [Dive-And-Dev/perch#38](https://github.com/Dive-And-Dev/perch/issues/38) [#1](https://github.com/chris-yyau/helmet/issues/1) [#2](https://github.com/chris-yyau/helmet/issues/2) [#api](https://github.com/chris-yyau/helmet/issues/api)

# [1.17.0](https://github.com/chris-yyau/helmet/compare/v1.16.0...v1.17.0) (2026-05-08)


### Features

* **helmet:** per-repo opt-in via vars.DEPENDABOT_AUTO_APPROVE; annotate-only on opted-out tiers ([#34](https://github.com/chris-yyau/helmet/issues/34)) ([561ca7f](https://github.com/chris-yyau/helmet/commit/561ca7fff3ae1c853ea5f56b6eeee9bd81af2a83)), closes [Dive-And-Dev/perch#38](https://github.com/Dive-And-Dev/perch/issues/38) [perch#38](https://github.com/perch/issues/38) [perch#38](https://github.com/perch/issues/38) [#4](https://github.com/chris-yyau/helmet/issues/4)

# [1.16.0](https://github.com/chris-yyau/helmet/compare/v1.15.2...v1.16.0) (2026-05-08)


### Features

* **helmet:** tier-portable Dependabot auto-merge via in-workflow auto-approve ([#33](https://github.com/chris-yyau/helmet/issues/33)) ([5b471e2](https://github.com/chris-yyau/helmet/commit/5b471e2ebad4f849ff787a032a7eba2c0361ddda)), closes [hi#confidence](https://github.com/hi/issues/confidence)

## [1.15.2](https://github.com/chris-yyau/helmet/compare/v1.15.1...v1.15.2) (2026-05-08)


### Bug Fixes

* **helmet:** replace empty `permissions: {}` with `contents: read` baseline ([#31](https://github.com/chris-yyau/helmet/issues/31)) ([9dd0a46](https://github.com/chris-yyau/helmet/commit/9dd0a46c8998554baf79c54c7d5d1fd84db4d921)), closes [#23](https://github.com/chris-yyau/helmet/issues/23) [#22](https://github.com/chris-yyau/helmet/issues/22)

## [1.15.1](https://github.com/chris-yyau/helmet/compare/v1.15.0...v1.15.1) (2026-05-07)


### Bug Fixes

* **helmet:** YAML parse error in Dependabot auto-merge comment body ([#30](https://github.com/chris-yyau/helmet/issues/30)) ([0f52754](https://github.com/chris-yyau/helmet/commit/0f527549ed3af02a95c0dab47ff4005c4dd93872)), closes [#29](https://github.com/chris-yyau/helmet/issues/29) [#22](https://github.com/chris-yyau/helmet/issues/22)

# [1.15.0](https://github.com/chris-yyau/helmet/compare/v1.14.3...v1.15.0) (2026-05-07)


### Features

* **helmet:** tiered Dependabot auto-merge gating, drop auto-approve ([#29](https://github.com/chris-yyau/helmet/issues/29)) ([24bc7f7](https://github.com/chris-yyau/helmet/commit/24bc7f7bd47ded65a1bdecf66cc97cd9c34a73b2)), closes [#23](https://github.com/chris-yyau/helmet/issues/23)

## [1.14.3](https://github.com/chris-yyau/helmet/compare/v1.14.2...v1.14.3) (2026-05-07)


### Bug Fixes

* **security:** also close grep-in-if residual fail-open ([#28](https://github.com/chris-yyau/helmet/issues/28)) ([bcbc6e4](https://github.com/chris-yyau/helmet/commit/bcbc6e4c52c050c8accc28b392830b39121dca6f)), closes [#27](https://github.com/chris-yyau/helmet/issues/27) [chris-yyau/busdriver#74](https://github.com/chris-yyau/busdriver/issues/74) [Dive-And-Dev/growth-engine#49](https://github.com/Dive-And-Dev/growth-engine/issues/49)

## [1.14.2](https://github.com/chris-yyau/helmet/compare/v1.14.1...v1.14.2) (2026-05-07)


### Bug Fixes

* **security:** close fail-open from set -e suspension in if-condition ([#27](https://github.com/chris-yyau/helmet/issues/27)) ([a9791a5](https://github.com/chris-yyau/helmet/commit/a9791a5ca5b34725d9bf1eb7a9f4766cd2760b37)), closes [#26](https://github.com/chris-yyau/helmet/issues/26) [growth-engine#45](https://github.com/growth-engine/issues/45) [chrisyau.me#105](https://github.com/chrisyau.me/issues/105)

## [1.14.1](https://github.com/chris-yyau/helmet/compare/v1.14.0...v1.14.1) (2026-05-07)


### Bug Fixes

* **security:** canonical pattern hardening — pipefail, fail-closed if:, comment ([#26](https://github.com/chris-yyau/helmet/issues/26)) ([f5fb377](https://github.com/chris-yyau/helmet/commit/f5fb377099109dc7a19811eba3a5de47792d98ac))

# [1.14.0](https://github.com/chris-yyau/helmet/compare/v1.13.1...v1.14.0) (2026-05-06)


### Features

* **helmet:** make security scanners required-checks by default ([#25](https://github.com/chris-yyau/helmet/issues/25)) ([accdf9a](https://github.com/chris-yyau/helmet/commit/accdf9a00a98a85ba2a88cdf078d223347ac4e0b))

## [1.13.1](https://github.com/chris-yyau/helmet/compare/v1.13.0...v1.13.1) (2026-05-06)


### Bug Fixes

* **helmet:** make Dependabot auto-merge workflow idempotent on re-runs ([#24](https://github.com/chris-yyau/helmet/issues/24)) ([2c9d23b](https://github.com/chris-yyau/helmet/commit/2c9d23b2e35b0283ae5f20c07623527eff9c69af)), closes [#23](https://github.com/chris-yyau/helmet/issues/23) [#1](https://github.com/chris-yyau/helmet/issues/1)

# [1.13.0](https://github.com/chris-yyau/helmet/compare/v1.12.1...v1.13.0) (2026-05-06)


### Features

* **helmet:** add Dependabot auto-merge workflow for patch+minor bumps ([#23](https://github.com/chris-yyau/helmet/issues/23)) ([5f4d81f](https://github.com/chris-yyau/helmet/commit/5f4d81f91c458e8dd852f54be21a03718f98e79a))

## [1.12.1](https://github.com/chris-yyau/helmet/compare/v1.12.0...v1.12.1) (2026-04-16)


### Bug Fixes

* **security:** add harden-runner to reports summary job ([#21](https://github.com/chris-yyau/helmet/issues/21)) ([782ff69](https://github.com/chris-yyau/helmet/commit/782ff69bc2525924c89557269cf851f1a226100e))

# [1.12.0](https://github.com/chris-yyau/helmet/compare/v1.11.0...v1.12.0) (2026-04-16)


### Features

* add property-based test templates (5 languages) ([#18](https://github.com/chris-yyau/helmet/issues/18)) ([75f3c37](https://github.com/chris-yyau/helmet/commit/75f3c3711056ebe61788ac170b3afb71eeaed8db))

# [1.11.0](https://github.com/chris-yyau/helmet/compare/v1.10.0...v1.11.0) (2026-04-16)


### Features

* admin bypass audit workflow ([#17](https://github.com/chris-yyau/helmet/issues/17)) ([e748539](https://github.com/chris-yyau/helmet/commit/e748539950d98c186ccc01c81f5d8539e415e7f9))

# [1.10.0](https://github.com/chris-yyau/helmet/compare/v1.9.0...v1.10.0) (2026-04-16)


### Features

* document job-level skip pattern in onboarding skill ([#15](https://github.com/chris-yyau/helmet/issues/15)) ([f01ec78](https://github.com/chris-yyau/helmet/commit/f01ec78f9be8c19f1dddd211389575d55d71d957))

# [1.9.0](https://github.com/chris-yyau/helmet/compare/v1.8.0...v1.9.0) (2026-04-16)


### Features

* make zizmor a required check via job-level skip pattern ([#14](https://github.com/chris-yyau/helmet/issues/14)) ([58b5326](https://github.com/chris-yyau/helmet/commit/58b5326dcc71124ed8ff37b8431ce5e0d5fba07b))

# [1.8.0](https://github.com/chris-yyau/helmet/compare/v1.7.1...v1.8.0) (2026-04-16)


### Features

* dynamic required checks + GitHub plan caveats ([#13](https://github.com/chris-yyau/helmet/issues/13)) ([bbb127e](https://github.com/chris-yyau/helmet/commit/bbb127eaca104f14a66793cc6be17ad08aab1e18))

## [1.7.1](https://github.com/chris-yyau/helmet/compare/v1.7.0...v1.7.1) (2026-04-09)


### Bug Fixes

* address PR [#10](https://github.com/chris-yyau/helmet/issues/10) review comments ([#11](https://github.com/chris-yyau/helmet/issues/11)) ([c5753b8](https://github.com/chris-yyau/helmet/commit/c5753b8a3b4d09750854b1bfd0e256f58fd2a82d))

# [1.7.0](https://github.com/chris-yyau/helmet/compare/v1.6.0...v1.7.0) (2026-04-09)


### Features

* add commitlint CI job, concurrency, and refresh CLAUDE.md ([#10](https://github.com/chris-yyau/helmet/issues/10)) ([17d0dba](https://github.com/chris-yyau/helmet/commit/17d0dbaadd81e555b8281d4ee630245a7bb8f5c4))

# [1.6.0](https://github.com/chris-yyau/helmet/compare/v1.5.0...v1.6.0) (2026-04-09)


### Features

* add Phase C (CLAUDE.md generation) to helmet onboarding skill ([#9](https://github.com/chris-yyau/helmet/issues/9)) ([59c4bba](https://github.com/chris-yyau/helmet/commit/59c4bba22d9599e90b54cc5259bc9f8ee0f28ddb))

# [1.5.0](https://github.com/chris-yyau/helmet/compare/v1.4.2...v1.5.0) (2026-04-09)


### Features

* auto-set CODECOV_TOKEN secret during helmet onboarding ([#8](https://github.com/chris-yyau/helmet/issues/8)) ([3171294](https://github.com/chris-yyau/helmet/commit/3171294dc0551b936806b74fde99579b98ccdd3d))

## [1.4.2](https://github.com/chris-yyau/helmet/compare/v1.4.1...v1.4.2) (2026-04-09)


### Bug Fixes

* scope RELEASE_TOKEN to release environment ([9f9084e](https://github.com/chris-yyau/helmet/commit/9f9084e90448fb108487d5cb5311840f8a15f869))

## [1.4.1](https://github.com/chris-yyau/helmet/compare/v1.4.0...v1.4.1) (2026-04-09)


### Bug Fixes

* use RELEASE_TOKEN for semantic-release push ([e189690](https://github.com/chris-yyau/helmet/commit/e189690b5167ab84b8f6e36118f603643c0ff6f4))

# [1.4.0](https://github.com/chris-yyau/helmet/compare/v1.3.0...v1.4.0) (2026-04-09)


### Features

* wire automatic version sync into release pipeline ([c18cf1b](https://github.com/chris-yyau/helmet/commit/c18cf1b2433251bdddf4564e947882d05ed69814))
