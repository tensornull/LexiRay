# Acceptance Data and TCC Safety

Real LexiRay data is out of bounds for automated verification. This rule is
absolute on success, ordinary failure, SIGINT, and SIGKILL.

## Protected state

Never read, move, copy, replace, delete, seed, or write:

- `~/.lexiray` (provider configuration, API keys, and history);
- the normal `io.github.tensornull.lexiray` defaults domain;
- any provider credential or `.env` file outside this repository;
- another repository's test fixtures, certificates, or secrets.

Automated verification also must not read, clear, or overwrite the general
pasteboard, and must not persist pixels outside windows owned by the exact
acceptance PIDs. Use UUID-named pasteboards and PID-bound window captures. OCR
coverage records PID-bound overlay window identities and geometry without
capturing pixels through the translucent overlay.

Do not build a backup/restore scheme around these paths. A backup is already an
unauthorized read and a killed process can make restoration impossible.

## Acceptance profile

GUI scenarios and installed-app Computer Use must launch LexiRay with its
explicit acceptance profile. The profile must supply:

- an isolated data root under the repository's ignored
  `build/acceptance-data/` area, bound to the workspace path and created with
  the harness marker file; installed acceptance roots are transaction-UUID
  scoped and exclusively created, never deleted or reused by path alone;
- an isolated UserDefaults suite;
- a canonical `preferences-home` inside that acceptance root, supplied through
  matching `HOME` and `CFFIXED_USER_HOME` values with
  `CFPREFERENCES_AVOID_DAEMON=1`; the app rejects acceptance mode unless all
  three process-level controls are present;
- deterministic mock providers and fixtures;
- a process identity that the harness can target without touching normal app
  state.

Before trusting the harness, run normal, failing, deliberately SIGINTed, and
deliberately SIGKILLed
cases inside a disposable synthetic home that contains user-shaped sentinel
data, then verify the sentinel bytes are unchanged. Build that sentinel plist
as a file; never use the `defaults` CLI for this test because its shared
`cfprefsd` process can ignore a synthetic `HOME`. Do not inspect or hash the real
protected paths to prove isolation. Never silently downgrade to the default
profile if acceptance-profile launch fails.

## TCC and app identity

- Use the canonical workspace or installed bundle defined by the active stage;
  never an arbitrary DerivedData copy.
- Development runnable builds use `LexiRay Local Development`; ad hoc signing
  is not valid evidence for Accessibility or Screen Recording.
- Normal builds verify the pinned development fingerprint and fail closed. Run
  `script/development_identity.sh doctor` outside a keychain-restricted sandbox;
  never generate or import a replacement as part of a build.
- Do not run `tccutil reset` during normal development or acceptance.
- Do not inspect or unlock the obsolete random-password release keychain in a
  way that prompts for a password. Treat it as an unrecoverable build artifact.
- A missing release identity is a normal signal for GitHub packaging fallback,
  not permission to generate a new identity or search other projects.

The real Login Item probe is the sole acceptance exception to full system
isolation. It may mutate only LexiRay's own `SMAppService.mainApp` record, at
most once per run, and must restore an observed initial off state. It still uses
the isolated data root/defaults/mock provider and never reads production
defaults or TCC state.

Live-provider smoke tests are separate from acceptance and run only with a key
the user explicitly supplies for that run. Report accepted/responded/effective
states separately; an HTTP success alone is not translation correctness.
