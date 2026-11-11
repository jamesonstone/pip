---
kit_metadata_version: 1
artifact: "spec"
workflow_version: 3
phase: "implement"
feature:
  id: "0001"
  slug: "share-intake"
  dir: "0001-share-intake"
---
# SPEC

## PURPOSE

Pip is the share-sheet courier for Jameson's personal intake webhook. From Safari, Photos, Files, or any other app, he shares a link, some text, an image, or a file, optionally adds a note, and Pip POSTs that parcel to the webhook he already uses from a Shortcut.

The container app exists to hold the webhook URL and bearer token. The share extension exists to show up as "Pip" so it can be moved to the top of the system share sheet on macOS and iPhone.

## CONTEXT

- The repository started as a one-line README. Kit now owns the agent contract. Issue #1 is the only ticket, and it is assigned to jamesonstone.
- The webhook already accepts `POST` JSON with `Authorization: Bearer <key>`. The receiver reads `url`, `text`, `image` (base64), `filename`, and `type`. This client also sends `source` (`ios` or `macos`), which the issue requires.
- The repository is public. The webhook URL, bearer token, Apple Team ID, and production bundle-ID prefix must not be committed.
- GitHub Actions on macOS builds the app targets with signing disabled and runs PipCore tests. Local macOS validation also covers native attachment representations without sending test payloads to the intake webhook.

## REQUIREMENTS

- A SwiftUI container app for iOS (iPhone required, iPad included) and macOS, plus a share extension embedded in each.
- The extension is named Pip in the share sheet and accepts a URL, text, one image, or one file.
- Settings asks for an https webhook URL and a bearer token and stores them in the Keychain. The extension reads the same item through a shared keychain access group.
- The POST body can include `url` (the link, or the shared text when there is no link), `text` (the optional note), `image` (base64), `filename`, `type`, and `source`.
- Images are downscaled and JPEG-compressed so the bytes stay under 750 KB before base64.
- Image inputs, including file-URL images, are capped at 25 MB before conversion. Other files retain the 750 KB input cap.
- The share UI is a dark, sparse sheet: what is being sent, an optional note, and Send. Success reads "Delivered! 📬". Failure reads "Pip tripped, try again 🩹".
- Signing team and bundle-ID prefix live in `Config/Signing.xcconfig`, which is gitignored. `Config/Signing.xcconfig.example` is committed.
- The Xcode project is generated from `project.yml`. CI builds the iOS Simulator and macOS destinations unsigned and runs `swift test` for PipCore.
- The README explains signing, first run, and how to enable Pip and move it to the top of the share sheet on Mac and iPhone.

Out of scope: the intake server, the existing Shortcut, App Store submission, and any attempt to reorder the system share sheet from inside the app.

## ACCEPTED PLAN

- Keep payload construction, image encoding, the Keychain wrapper, and the webhook client in the `PipCore` Swift package. Keep SwiftUI in the app and extension targets.
- Describe the app and extension with XcodeGen (`project.yml`) for iOS 17 and macOS 14. Do not commit the generated project.
- Share the secret with a keychain access group `$(TeamID).$(prefix).pip.shared`. Do not also create an App Group. One sharing mechanism is enough, and the Keychain is the right store for a bearer token.
- Read the service name and access group from Info.plist build settings so the source stays free of team and bundle identifiers. Treat an access group that is empty or starts with `.` as unset.
- Require `https`, reject URLs with userinfo, and reject tokens that contain a newline. On redirect, keep the Authorization header only when the host is unchanged.
- Map shares as follows:
  - An http(s) URL becomes `url`. Accompanying plain text becomes `text` when the note is empty.
  - Plain text with no URL becomes `url`. The note, when present, becomes `text`.
  - An image is re-encoded as JPEG, then sent as `image` with `type` `image/jpeg`.
  - A text-like file becomes the text body (the `url` field when nothing else claimed it) and sets `filename` and `type`.
  - Any other file at or under 750 KB is base64 in `image`, with its own `filename` and `type`. Larger files fail in the sheet.
- Cap the note at 4,000 characters and other text at 100,000 characters.
- Generate the project in CI, copy the example xcconfig, and build with `CODE_SIGNING_ALLOWED=NO`.

## DECISIONS

- Accepted a shared keychain access group and rejected an App Group container for the token. The issue allows either. A container would put the secret in a file and would add a second capability to register.
- Accepted XcodeGen and rejected a hand-maintained pbxproj. The generated project is gitignored so `project.yml` stays the source of truth.
- Accepted reusing the `image` field for a non-image file's bytes. The webhook has one binary field. `type` and `filename` say what the bytes are. A new field would be invisible to the receiver.
- Rejected `TRUEPREDICATE` as the activation rule. The extension declares support for a web URL, text, one image, and one file.
- Accepted playful status lines and rejected playful controls. Send, Save, and Close stay plain so the sheet stays sleek.
- Accepted `https` only. The bearer token must not be sent to an unencrypted URL. App Transport Security already blocks plain HTTP on Apple platforms.

## DISCOVERIES

- A file URL conforms to `public.url`. The extractor treats `public.file-url` as a file and only treats a non-file URL as a link, so a shared file is not posted as a `file://` string.
- `kSecUseDataProtectionKeychain` is set on the Security-backed store so macOS uses the data-protection keychain, which is the one keychain access groups apply to.
- XcodeGen splits one `platform: [iOS, macOS]` target into names the scheme cannot depend on. The project uses separate Pip-iOS, Pip-macOS, PipShare-iOS, and PipShare-macOS targets instead.
- PipCore declares iOS 17 and macOS 14. Without that, `swift test` on the CI Mac tries to compile `URLSession.data(for:)`, `UTType`, and `kSecUseDataProtectionKeychain` against the package default of macOS 10.13.
- The macOS share controller keeps its `NSHostingController` as a child. A local controller is released when `loadView` returns, and the sheet is blank.
- Shared files are read only after `startAccessingSecurityScopedResource()`, because the sandboxed Mac extension cannot read a Finder or Files URL otherwise.
- Safari can supply a URL as UTF-8 `Data`. The URL decoder accepts that representation as well as native URLs and strings.
- Selected text can arrive in `NSExtensionItem.attributedContentText` without an attachment. It is a fallback when no attachment text is available. Plain-text providers also conform to `public.data`, so the generic binary fallback must exclude them.
- A legacy macOS image provider can serialize an `NSImage` from `loadDataRepresentation`. Use `loadItem` and convert its native image, data, or security-scoped file URL instead. Do not manually unarchive provider bytes.
- Native image objects are resized before intermediate PNG conversion, so a compressed photo does not exceed the input cap only because its native bitmap expands into a large TIFF.
- Image file URLs follow the same JPEG conversion path as image attachments. Their actual file extension determines the image MIME type; a suggested display name does not change classification.

## VALIDATION

- `swift test --package-path Packages/PipCore` on macOS with Xcode 27.2: 46 tests passed, 0 failures. This covers payloads, Keychain wrappers, URL data, inline text, native image providers, file-URL image compression, and input caps.
- Both unsigned platform builds passed using the commands in `docs/references/testing.md`, with isolated derived-data directories, placeholder signing values, and `REGISTER_APP=NO`. The only build warning was that App Intents metadata extraction was skipped because the app has no AppIntents dependency.
- A synthetic integration harness compiled the actual `ExtensionAttachment` adapter and PipCore. Legacy native-image, modern native-image, and image-file providers each produced a 28,771-byte JPEG. A native text provider produced text without a binary attachment. No network requests were sent.
- Before the fixes, regression tests reproduced the plain-text binary fallback and oversized file-URL image failures. A legacy `NSImage` provider reproduced the earlier image failure with the same 3,154,778-byte serialized representation. The corrected path loads the typed image instead.
- `kit check --project` passed with two non-blocking notices for preserved project-owned design and security guidance. `git diff --check` passed.
- Fresh-context review found attachment type, native image resizing, UIKit pixel-scale, and README target-name issues. All findings were fixed; the final review found no further actionable blockers.
- Historical manual evidence: a signed Mac install, shared Keychain setup, and link delivery succeeded before these final fixes. The user confirmed receipt of that link. Final signed share-sheet text/image delivery, UIKit runtime behavior, iPhone installation, and distribution were not tested in this merge pass.

## OUTCOME

- PipCore builds the intake JSON, compresses images, stores credentials, and POSTs them.
- The container app and the share extension are generated from `project.yml` for iOS 17 and macOS 14.
- The whimsical README has the setup steps. Signing values and the webhook secret stay out of git.
- The current source passes local package tests, both unsigned builds, and synthetic adapter integration. Final signed device flows and distribution remain separate validation work.

## REPOSITORY MEMORY

- This spec holds the payload contract and the choices above.
- `docs/CONSTITUTION.md` should gain only the public-repo secret rule once the code demonstrates it.
- `docs/references/testing.md` should record the macOS commands once they exist.
- `DESIGN.md` and `SECURITY.md` project sections should record the UI tone and the secret-handling rules.
