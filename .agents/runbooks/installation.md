# Installation

Installation is not part of ordinary delivery. Use it only for TCC, Login Item, global hotkey, selection/OCR/speech, signing/install/lifecycle changes, or an explicit request.

```bash
swift run lexiray-ops install --source /absolute/path/LexiRay.app
```

The installer validates the bundle, stages below `/Applications`, stops only the exact installed executable, atomically replaces the destination, verifies the installed copy, and rolls back immediately on failure. It stores no transaction or recovery state.

Perform the named Computer Use scenario with the isolated acceptance profile, then record the result and sealed captures:

```bash
swift run lexiray-ops accept launch --result passed --screenshot /absolute/path/capture.png
```

The JSON result is immutable and source-fingerprinted. A retry requires the earlier evidence ID and root cause.
