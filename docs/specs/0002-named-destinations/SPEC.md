---
kit_metadata_version: 1
artifact: "spec"
workflow_version: 3
phase: "implement"
feature:
  id: "0002"
  slug: "named-destinations"
  dir: "0002-named-destinations"
---
# SPEC

## PURPOSE

Make the macOS settings window and share sheet easier to use, and let one share go to a chosen Grok Bot bot. Each bot has its own webhook. Pip keeps a named destination for each bot and lets the person pick one in the sheet, or by starting the note with `@Name`.

## CONTEXT

- Issue #3 is the request. The screens today are one https URL and one bearer token. The macOS settings window is a tall, narrow, plain form. The share sheet leaves a large empty region under Send, and the note field is not a reliable keyboard target.
- Credentials already live in one shared Keychain item, account `intake`. The container app and the share extension both use `CredentialStore`. The POST body in `docs/specs/0001-share-intake/SPEC.md` does not change.
- The repository is public. Webhook URLs, bearer tokens, the Apple Team ID, and the bundle-ID prefix stay out of git.
- Kit v3.0.59 refuses `kit init` when `.kit.yaml` already exists and tells the caller to run `kit reconcile`. That refresh is the Kit half of this feature. `github.default_assignees` stays `jamesonstone` so reconcile cannot leave the auto-assign workflow with an empty maintainer list.

## REQUIREMENTS

- Settings on macOS is about 420 points wide and sizes to its content. It is not a tall empty window. It uses a dark field with a restrained accent, an icon on each field, and an info control whose hover text explains the field.
- Webhook URL hover text: where Pip POSTs shares, https only, stored in the Keychain and shared with the share extension.
- Key hover text: bearer token sent as `Authorization: Bearer`, stored in the Keychain and shared with the share extension.
- Name hover text: the name shown in the share sheet. A note that starts with `@Name` selects that bot, and Pip removes the prefix before sending.
- The share sheet uses more color and icons than settings, including a colored Send control that still says Send. The window fits the fields. There is no large empty region under Send.
- Enter sends. Shift-Enter inserts a newline. Escape closes the sheet. The note field is focused when the sheet opens and is in the Tab order.
- A destination is a name, an https URL, and a bearer token. Many destinations can be stored. The share sheet can pick one. An `@Name` prefix selects one and is not part of the sent note. The last destination used is the default next time. A single saved URL and key from the previous format still sends.
- No secrets in the repo. The intake JSON fields stay `url`, `text`, `image`, `filename`, `type`, and `source`.

Out of scope: the intake server, App Store submission, reordering the system share sheet, merging this branch, and pre-existing `kit check` warnings that this work did not cause.

## ACCEPTED PLAN

- Keep one Keychain item. Version 2 JSON stores the destinations and the last-used id. PipCore owns the book, the name rules, migration, and `@Name` routing. SwiftUI only displays them and calls the store.
- A legacy record `{webhookURL, bearerToken}` loads as one destination named `Default`. Its id is derived from the URL so the app and the extension agree before either one saves. The next save writes version 2.
- `@Name` matches the longest destination name, case-insensitive, only as a prefix. The character after the name must be the end of the note or whitespace. Spaces in names are allowed. A prefix that matches is removed, including the whitespace after it. A prefix that matches no bot stays in the note, and the picker selection is used.
- The picker shows the bot that will actually receive the share. Choosing a different bot while a matching prefix is present removes that prefix so the note and the picker agree.
- Removing a bot deletes that entry from the Keychain item after a confirmation that names the bot. There is no trash. Keeping a bearer token after the person removes the bot fights the secret-minimization rule.
- Settings edits one bot at a time under the list. The macOS window uses a fixed 420-point width and content-sized height. The share sheet drops the expanding spacer on macOS and sets `preferredContentSize` from the measured content. The hosting view accepts first responder so Tab, Enter, and Escape reach the SwiftUI fields.
- iOS uses the same screens. Settings scrolls. The share sheet can keep a bottom spacer there so the system sheet still opens with the fields at the top.

## DECISIONS

- Accepted one Keychain record for the whole book. Rejected one item per bot. Last-used and migration then need a second index, and a partial write can leave the index and the secrets disagreeing.
- Accepted longest-prefix `@Name` matching. Rejected single-token names. Bot names such as "Work Bot" are the names a person will actually type.
- Accepted leaving an unmatched `@` in the note. Rejected stripping every leading `@word`. A note may really start with `@`.
- Accepted a deterministic legacy id from the webhook URL. Rejected a new random id on every load. Two processes would otherwise save two different ids for the same bot and overwrite each other.
- Accepted immediate removal of a destination's secret after confirmation. Rejected a soft-delete tombstone. A tombstone would keep the bearer token on disk after the person asked to remove it. They can add the bot again if they still have the URL and key. This path has no restore.
- Accepted a colored Send control with the word Send and an icon. Rejected replacing the word with an emoji. The existing design rule still holds: the word is the label, and color is not the only cue.
- `load()` still returns the preferred destination as `IntakeCredentials`. `save(_: IntakeCredentials)` updates that destination, or creates `Default` when the book is empty. It does not delete other bots.

## DISCOVERIES

- `kit init` on this repo exits with an error because `.kit.yaml` is already present. `kit reconcile` is the write path that brings the project to Kit v3.0.59. An explicit `github.default_assignees` list of `jamesonstone` is what the auto-assign workflow renders. An empty list would not fall back to a global config.
- The empty region under Send is the share view's bottom spacer inside a fixed 360-point `preferredContentSize`. Removing the spacer on macOS and publishing the measured height removes that gap.
- A SwiftUI field inside the macOS share extension does not take keyboard focus until the hosting view accepts first responder.

## VALIDATION

- `swift test --package-path Packages/PipCore` on the macOS CI runner. The new tests cover legacy migration, a version 2 round trip, last-used preference, duplicate and invalid names, `@Name` longest-match and stripping, and that the stripped note is the payload `text`.
- The unsigned iOS and macOS builds in `.github/workflows/ci.yml` compile the settings and share-sheet changes.
- This environment has no Swift toolchain and no Mac. Rendered window size, hover tooltips, Tab, Enter, Shift-Enter, Escape, and a real Keychain send are not verified here.

## OUTCOME

- PipCore stores named destinations in the existing Keychain item, migrates the single-webhook record, and routes `@Name`.
- Settings is a 420-point content-sized window with field icons and info controls. The share sheet picks a bot, colors Send, and fits its fields.
- Signed Mac confirmation of the window, the tooltips, the keyboard, and a live send remains manual.

## REPOSITORY MEMORY

- This spec holds the destination book, the `@Name` rule, and the screen decisions.
- `docs/specs/0001-share-intake/SPEC.md` keeps the payload contract and points here for credentials.
- `DESIGN.md`, `SECURITY.md`, `README.md`, and `docs/references/testing.md` record the visible behavior, the secret rule, setup, and the test command.
