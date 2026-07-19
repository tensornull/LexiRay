# Installation

Installation is not part of ordinary delivery. Use it only for TCC, Login Item, global hotkey, selection/OCR/speech, signing/install/lifecycle changes, or an explicit request.

```bash
swift run lexiray-ops install --source /absolute/path/LexiRay.app
```

The installer requires the pinned local-development or release certificate, stages below `/Applications`, stops only the exact installed executable, and uses an APFS atomic exchange. The old app therefore remains at the canonical path until the new app is committed; verification failure swaps it back. It stores no transaction or recovery state.

Launch the installed app through the operations tool, perform only the named Computer Use scenario, then record it with the live PID printed by `launch`:

```bash
swift run lexiray-ops accept launch launch
swift run lexiray-ops accept record launch --pid 12345 --result passed
```

`record` verifies the exact installed executable, pinned signature, acceptance arguments, repository-owned data root, isolated preferences home and defaults suite, and named pasteboard contract. It captures only windows owned by that live PID, terminates only that verified process, removes the ephemeral acceptance data, and writes one immutable source-fingerprinted JSON. The PID is handed off on stdout only and is never stored as workflow state. A retry requires the earlier evidence ID and root cause.
