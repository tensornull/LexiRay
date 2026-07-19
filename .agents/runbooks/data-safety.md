# Data and credential safety

- GUI and Computer Use acceptance use only repository-owned ignored roots under `build/acceptance-data`, an acceptance-only UserDefaults suite, named pasteboards, fixtures, and mock providers.
- Never read or write real `~/.lexiray`, production defaults, provider keys/history, or the general pasteboard. This applies on success, failure, interruption, and forced termination.
- Capture only windows owned by the launched acceptance process. Do not persist unrelated desktop pixels.
- Never reset TCC as part of development. Missing permission is blocked evidence, not a reason to alter system privacy state.
- Never read credentials from another project or an environment file.
- Release P12 material and password are consumed only by the 20-minute GitHub publish job. The runner uses a unique ephemeral keychain and restores the original search list on exit.
