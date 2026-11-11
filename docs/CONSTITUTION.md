# CONSTITUTION

## PRINCIPLES

- The intake webhook URL, bearer token, Apple Team ID, and production bundle-ID prefix stay off the public git history.

## CONSTRAINTS

- Credentials are stored in the shared Keychain. `Config/Signing.xcconfig` is the only place for the Team ID and bundle-ID prefix, and that file stays untracked. The committed example is a placeholder.

### Kit-Managed Baseline Rules

<!-- BEGIN KIT-MANAGED BASELINE RULES -->
- Kit's universal agent rules live in the Kit-managed block of `AGENTS.md` (rendered identically into `CLAUDE.md` and `.github/copilot-instructions.md`), and contextual rules live in `docs/references/rules/`. This Constitution records project-specific invariants and does not restate them.
<!-- END KIT-MANAGED BASELINE RULES -->

## CHANGE CLASSIFICATION

<!-- all work falls into one of two tracks — classify before acting -->

### Repository-Memory Work

<!-- use when: consequential product rationale, architecture, cross-component behavior, or historical decisions must survive -->
<!-- workflow: native plan → create/adopt SPEC.md before code → implement → validate → curate repository memory -->
<!-- legacy staged documents: BRAINSTORM.md, legacy SPEC.md, PLAN.md, TASKS.md only when explicitly chosen -->

### Ad Hoc (Lightweight)

<!-- use when: bug fixes, security reviews, refactors, dependency updates, config changes, small refinements -->
<!-- workflow: understand → implement → verify -->
<!-- docs: update practical canonical docs when behavior changes -->
<!-- do not create feature SPEC.md solely for ceremony; report a justified not-required memory decision -->

### Ad Hoc with Existing Specs

<!-- if change touches code with existing spec docs: update them when rationale, behavior, requirements, or approach changes -->
<!-- leave them unchanged when code and tests communicate the complete durable truth -->

## NON-GOALS

- Pip does not host the intake webhook.
- Pip does not reorder the system share sheet. The person using it does that in the system editor.

## DEFINITIONS

- Intake payload: the JSON POST defined in `docs/specs/0001-share-intake/SPEC.md`.
- Signing config: the untracked `Config/Signing.xcconfig`, copied from `Config/Signing.xcconfig.example`.
