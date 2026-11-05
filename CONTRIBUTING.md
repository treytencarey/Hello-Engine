# Contributing to Hello

This repository takes contributions to the Hello Library's mods and to the docs in `agent-docs/`. The engine's source is not in this repository.

## Proposing a mod or a fix

- **A new mod:** open an issue that says the one job the mod does, the components it exposes and the mods it depends on. Then open a pull request with the mod.
- **A fix:** open a pull request that says what was wrong and how the fix shows it. If you aren't sure something is wrong, open an issue first.

## What a mod needs

Mods follow [`agent-docs/mod-standard.md`](agent-docs/mod-standard.md). Read it in full, including its Common mistakes and its Design review checklist. It changes, so check your mod against what it says today, including its "Today differs" notes.

A mod in the library:

- lives in its own folder under `Hello-Library/assets/modules/`, does one job and is named for it;
- has `agent-docs/manifest.md`: front matter (`depends_on`, `conflicts_with`, `exposes`), then the sections Components, Systems, Use and Notes, describing the mod as it is now;
- has its suites in a `tests/` folder.

Before you open a pull request, go through [`agent-docs/mod-audit.md`](agent-docs/mod-audit.md) for your mod. It says how to check a mod against the standard and how to rate what you find.

Don't put credentials, environment reads or a copy of the engine's test helper in a mod or a suite.

## Test suites

The Tests section of the standard says what a suite must do. In short:

- A suite proves the real effect, not just that a component is present.
- A mutation of the code under test must turn the suite red. A fix comes with a case that fails without it.
- A suite is green only if its log also has zero Lua errors.
- A mod that renders, or reads the window's input, runs a windowed suite and says so in the suite's first ten lines.

This repository has no test runner and no CI, so there are no instructions here for running them.

## Commits

Keep commits small, one change each, with a short message that says what changed.

## Licence

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in this repository by you, as defined in the Apache-2.0 license, shall be licensed as `MIT OR Apache-2.0`, as in [LICENSE-MIT](LICENSE-MIT) and [LICENSE-APACHE](LICENSE-APACHE), without any additional terms or conditions.
