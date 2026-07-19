---
name: lexiray-install-applications
description: Install a verified LexiRay app into /Applications only for mapped macOS system-boundary acceptance or an explicit user request, then record immutable evidence.
---

# LexiRay installation

Use this skill only for TCC, Login Item, global hotkey, selection/OCR/speech, signing/install/lifecycle changes, or when the user explicitly asks to install.

1. Confirm the source app is the exact locally verified artifact and no build is still running.
2. Install through the single operations tool:

   ```bash
   swift run lexiray-ops install --source /absolute/path/LexiRay.app
   ```

3. Use Computer Use only for the mapped installed-app scenario with the isolated acceptance profile. Never read or seed production data, reset TCC, or capture unrelated windows.
4. Record the result and sealed screenshot paths:

   ```bash
   swift run lexiray-ops accept <scenario> --result passed --screenshot /absolute/path/capture.png
   ```

Installation is an immediate stage/verify/replace operation with rollback; there is no transaction receipt or resumable state. A diagnosed failed acceptance may be retried once with `--retry-of <id> --cause <root-cause>`.
