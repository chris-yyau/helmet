# [1.26.0](https://github.com/chris-yyau/helmet/compare/v1.25.2...v1.26.0) (2026-07-17)


### Features

* **ci:** add pinned-tool staleness sweep and refresh stale pins ([#67](https://github.com/chris-yyau/helmet/issues/67)) ([#85](https://github.com/chris-yyau/helmet/issues/85)) ([df9c7ac](https://github.com/chris-yyau/helmet/commit/df9c7ac8ce1888a46e46c58560018a6b87574c68))

## [1.25.2](https://github.com/chris-yyau/helmet/compare/v1.25.1...v1.25.2) (2026-07-17)


### Bug Fixes

* **security:** URL-encode the ref in the CVE sweep's close-on-green path ([#84](https://github.com/chris-yyau/helmet/issues/84)) ([ee5dfbc](https://github.com/chris-yyau/helmet/commit/ee5dfbc5cb37e1f7a1d82aa1811c54edb517d241))

## [1.25.1](https://github.com/chris-yyau/helmet/compare/v1.25.0...v1.25.1) (2026-07-17)


### Bug Fixes

* **skill:** close A0 precondition gap; add scheduled CVE re-scan ([#82](https://github.com/chris-yyau/helmet/issues/82), [#64](https://github.com/chris-yyau/helmet/issues/64)) ([#83](https://github.com/chris-yyau/helmet/issues/83)) ([ce5f2cd](https://github.com/chris-yyau/helmet/commit/ce5f2cd3d61e3bdfb22057f7846df4188624cc49))

# [1.25.0](https://github.com/chris-yyau/helmet/compare/v1.24.0...v1.25.0) (2026-07-15)


### Features

* **scripts:** fleet scanner-invariant check with fail-closed asserter ([#76](https://github.com/chris-yyau/helmet/issues/76)) ([#79](https://github.com/chris-yyau/helmet/issues/79)) ([e530d0d](https://github.com/chris-yyau/helmet/commit/e530d0d3433c8e3123ce5698ee030222c59ab93b)), closes [#66-style](https://github.com/chris-yyau/helmet/issues/66-style) [#66](https://github.com/chris-yyau/helmet/issues/66) [#66](https://github.com/chris-yyau/helmet/issues/66)

# [1.24.0](https://github.com/chris-yyau/helmet/compare/v1.23.0...v1.24.0) (2026-07-15)


### Features

* **security:** broaden Section N dep-path coverage to Rust/Swift manifests ([#70](https://github.com/chris-yyau/helmet/issues/70)) ([#78](https://github.com/chris-yyau/helmet/issues/78)) ([59014d6](https://github.com/chris-yyau/helmet/commit/59014d6c9b104bef68a1338351fbc40307b37eba))

# [1.23.0](https://github.com/chris-yyau/helmet/compare/v1.22.7...v1.23.0) (2026-07-14)


### Features

* **scripts:** dissolve [#66](https://github.com/chris-yyau/helmet/issues/66) content-parity parser via byte-identical convergence ([#77](https://github.com/chris-yyau/helmet/issues/77)) ([99e7f13](https://github.com/chris-yyau/helmet/commit/99e7f13baa387a8d61215c834779be159ac0662c))

## [1.22.7](https://github.com/chris-yyau/helmet/compare/v1.22.6...v1.22.7) (2026-07-13)


### Bug Fixes

* **scripts:** honest (c)-surface tally, exhaustion states, help + pin regex ([#73](https://github.com/chris-yyau/helmet/issues/73)) ([73c616f](https://github.com/chris-yyau/helmet/commit/73c616f9d4db0be0da8859b824a209d671088d96))

## [1.22.6](https://github.com/chris-yyau/helmet/compare/v1.22.5...v1.22.6) (2026-07-13)


### Bug Fixes

* **security:** sync live security.yml permissions/paths + pin release toolchain ([#72](https://github.com/chris-yyau/helmet/issues/72)) ([c2b9880](https://github.com/chris-yyau/helmet/commit/c2b9880c3e745586a46ebc3a1900d0e6501b2a3d)), closes [#67](https://github.com/chris-yyau/helmet/issues/67)

## [1.22.5](https://github.com/chris-yyau/helmet/compare/v1.22.4...v1.22.5) (2026-07-12)


### Bug Fixes

* **security:** always scan in security.yml + pin scanners to close [#63](https://github.com/chris-yyau/helmet/issues/63) ([#69](https://github.com/chris-yyau/helmet/issues/69)) ([c92f874](https://github.com/chris-yyau/helmet/commit/c92f874d47f4670aaa293d2bf6cabfc6b77930c0)), closes [#66](https://github.com/chris-yyau/helmet/issues/66) [#67](https://github.com/chris-yyau/helmet/issues/67)

## [1.22.4](https://github.com/chris-yyau/helmet/compare/v1.22.3...v1.22.4) (2026-07-10)


### Bug Fixes

* **security:** harden .github/ detector guard to fail-closed on grep error ([#62](https://github.com/chris-yyau/helmet/issues/62)) ([dda4d08](https://github.com/chris-yyau/helmet/commit/dda4d0800644bebd71c89fcc55c4bcdcfebf68de)), closes [#318](https://github.com/chris-yyau/helmet/issues/318)

## [1.22.3](https://github.com/chris-yyau/helmet/compare/v1.22.2...v1.22.3) (2026-07-10)


### Bug Fixes

* complete bump-version.sh jq-injection and semver hardening ([#60](https://github.com/chris-yyau/helmet/issues/60)) ([4520429](https://github.com/chris-yyau/helmet/commit/45204295b5c2feec56d0c6518696c03141701857)), closes [#57](https://github.com/chris-yyau/helmet/issues/57)

## [1.22.2](https://github.com/chris-yyau/helmet/compare/v1.22.1...v1.22.2) (2026-07-09)


### Bug Fixes

* harden bump-version.sh, dedupe commitlint config, correct CI drift ([#57](https://github.com/chris-yyau/helmet/issues/57)) ([0833db6](https://github.com/chris-yyau/helmet/commit/0833db605b8560515aedcc355b119c161eef189c))

## [1.22.1](https://github.com/chris-yyau/helmet/compare/v1.22.0...v1.22.1) (2026-06-05)


### Bug Fixes

* **ci:** backport canonical bypass-audit v1.21.2 hardening ([#52](https://github.com/chris-yyau/helmet/issues/52)) ([43b73aa](https://github.com/chris-yyau/helmet/commit/43b73aa5df48e0bc58fdc50a76670e91d7b6db91))

# [1.22.0](https://github.com/chris-yyau/helmet/compare/v1.21.0...v1.22.0) (2026-06-05)


### Features

* **ci:** canonical bypass-audit standard + pipeline drift detection ([#51](https://github.com/chris-yyau/helmet/issues/51)) ([cd8b160](https://github.com/chris-yyau/helmet/commit/cd8b160bc6d308c00252c9423416f7474a80901b))

# [1.21.0](https://github.com/chris-yyau/helmet/compare/v1.20.1...v1.21.0) (2026-06-03)


### Features

* **helmet:** make phase d codegraph index-only, wiring is one-time prereq ([#49](https://github.com/chris-yyau/helmet/issues/49)) ([b57a192](https://github.com/chris-yyau/helmet/commit/b57a1923f2f14f756bbbad44b7d5921d1e57a189))

## [1.20.1](https://github.com/chris-yyau/helmet/compare/v1.20.0...v1.20.1) (2026-05-25)


### Bug Fixes

* **scorecard:** remove top-level defaults block + skill audit exemption ([#45](https://github.com/chris-yyau/helmet/issues/45)) ([9db0533](https://github.com/chris-yyau/helmet/commit/9db05338bfb23f35eed95fe9ca6d5df077eb701d))

# [1.20.0](https://github.com/chris-yyau/helmet/compare/v1.19.2...v1.20.0) (2026-05-24)


### Features

* **helmet:** add Phase D — CodeGraph index for code intelligence ([#44](https://github.com/chris-yyau/helmet/issues/44)) ([fbf9891](https://github.com/chris-yyau/helmet/commit/fbf9891049eb00acef1dfd39f8354870e17ea30f))

## [1.19.2](https://github.com/chris-yyau/helmet/compare/v1.19.1...v1.19.2) (2026-05-10)


### Bug Fixes

* **helmet:** SC2001 parameter expansion + matrix_value doc polish ([#42](https://github.com/chris-yyau/helmet/issues/42)) ([746e646](https://github.com/chris-yyau/helmet/commit/746e64670512bf938583e25d14cba705933ac1fc)), closes [#40](https://github.com/chris-yyau/helmet/issues/40)

## [1.19.1](https://github.com/chris-yyau/helmet/compare/v1.19.0...v1.19.1) (2026-05-09)


### Bug Fixes

* **helmet:** print [c] Skipped lines under --local-only and missing-gh paths ([#41](https://github.com/chris-yyau/helmet/issues/41)) ([1fdbae8](https://github.com/chris-yyau/helmet/commit/1fdbae8d70a1b5bd350df42bdcf1634275006987))

# [1.19.0](https://github.com/chris-yyau/helmet/compare/v1.18.3...v1.19.0) (2026-05-09)


### Features

* **helmet:** support matrix-derived required check names in lock ([#40](https://github.com/chris-yyau/helmet/issues/40)) ([f62a9bc](https://github.com/chris-yyau/helmet/commit/f62a9bc8c9bb7f6f6794ec2fc8f676f02942c414))

## [1.18.3](https://github.com/chris-yyau/helmet/compare/v1.18.2...v1.18.3) (2026-05-09)


### Bug Fixes

* **helmet:** --strict-remote hard-fails on missing remote/gh; validate lock shape ([#39](https://github.com/chris-yyau/helmet/issues/39)) ([3aa8fb3](https://github.com/chris-yyau/helmet/commit/3aa8fb34f899b303d9be9e5a17378d5a0ccc5e65)), closes [Dive-And-Dev/jikdak#128](https://github.com/Dive-And-Dev/jikdak/issues/128) [#CLI](https://github.com/chris-yyau/helmet/issues/CLI)

## [1.18.2](https://github.com/chris-yyau/helmet/compare/v1.18.1...v1.18.2) (2026-05-09)


### Bug Fixes

* **helmet:** validate --owner/--repo flags reject missing/flag values ([#38](https://github.com/chris-yyau/helmet/issues/38)) ([4e5298f](https://github.com/chris-yyau/helmet/commit/4e5298f6f002d827613bfd653cbd75cc0c1edfce)), closes [Dive-And-Dev/jikdak#128](https://github.com/Dive-And-Dev/jikdak/issues/128)

## [1.18.1](https://github.com/chris-yyau/helmet/compare/v1.18.0...v1.18.1) (2026-05-09)


### Bug Fixes

* **helmet:** per-surface ok-guards in check-required-checks ([#37](https://github.com/chris-yyau/helmet/issues/37)) ([87b491b](https://github.com/chris-yyau/helmet/commit/87b491bb60929dd06d2bcbcb402650572ffed805)), closes [Dive-And-Dev/jikdak#128](https://github.com/Dive-And-Dev/jikdak/issues/128)

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
