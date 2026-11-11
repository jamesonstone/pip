# Testing Reference

## Purpose

- Record the project's durable commands, suites, environments, automation, and evidence expectations
- Follow `rules/testing-and-environment-validation.md` for the mandatory cross-project testing and production-safety contract
- Keep feature-specific testing details in the current feature's `SPEC.md` VALIDATION and OUTCOME sections; legacy staged flows may still use `PLAN.md` or `TASKS.md`

## Code-Level Validation

| Layer | Command | PR workflow or check | Required | Notes |
| --- | --- | --- | --- | --- |
| PipCore unit tests | `swift test --package-path Packages/PipCore` | CI job `Build and test` | yes | Payload, Keychain wrapper, image encoder, webhook request. No webhook credentials. |
| iOS compile | `xcodebuild -project Pip.xcodeproj -scheme Pip-iOS -destination 'generic/platform=iOS Simulator' -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=- build` | CI job `Build and test` | yes | Needs `xcodegen generate` and a local copy of the example signing file. |
| macOS compile | `xcodebuild -project Pip.xcodeproj -scheme Pip-macOS -destination 'generic/platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=- build` | CI job `Build and test` | yes | Same unsigned flags. |

`make test`, `make build-ios`, and `make build-macos` wrap those commands. `make generate` runs `xcodegen generate`.

## High-Level Suites

| Suite | Type | Environment | Command | Automation | Evidence |
| --- | --- | --- | --- | --- | --- |
| Share sheet on device | manual | Jameson's Mac and iPhone, after signing | Install from Xcode, enable Pip in the share sheet, send one link | not automated | Not collected in CI. There is no device farm. |

## Environment Preflights

- Commands run on macOS with Xcode 16 or newer and XcodeGen. Working directory is the repository root. Shell is the user's login shell. No project `.kit.yaml` shell override.
- Harmless checks: `xcodebuild -version`, `xcodegen --version`, `swift --version`.
- Before `xcodegen generate` or the Xcode builds, copy `Config/Signing.xcconfig.example` to `Config/Signing.xcconfig`. CI does this in the workflow. The copy is gitignored.
- Linux agents can edit the package but cannot compile the app or the ImageIO and Security tests. Those run on the macOS CI runner.
- Local installs need `DEVELOPMENT_TEAM` and `PRODUCT_BUNDLE_IDENTIFIER_PREFIX` in the untracked xcconfig. CI leaves the example values in place and disables signing, so the CI build is not an installable app.
- No production environment applies. Do not point tests at the real intake webhook.

## Credentials And Test Data

- Names only: webhook URL, bearer token, Apple Team ID, bundle-ID prefix. Values stay in the Keychain or the untracked xcconfig.
- Unit tests use `https://intake.example.test` and the stand-in token `test-token`.
- Nothing to clean up. Tests do not write to a remote service.

## Evidence And Retention

- Keep `tmp/` ignored and record CI artifact locations and retention
- CI logs are the evidence for the unsigned builds and the unit tests. No extra artifacts are uploaded.
- Keep `tests/RUN_STATUS.md` curated at meaningful validation milestones

## Automation And Fallbacks

- Pull requests run `.github/workflows/ci.yml` on `macos-latest`: package tests, unsigned iOS Simulator build, unsigned macOS build.
- When CI cannot run, the fallback is the same three commands on a Mac. Report them as local, not as CI.

## Known Gaps

- The share extension UI is not rendered in CI. Device install, Keychain sharing across the app and extension, and the system share sheet are manual.
- `ImageIOEncoder` and `SecurityKeychain` tests compile only on Apple platforms. They run in the macOS CI job.
