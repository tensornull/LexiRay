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

3. Launch the installed copy through the operations tool. It prints the live PID but does not persist it:

   ```bash
   swift run lexiray-ops accept launch <scenario>
   ```

4. Use Computer Use only for that mapped scenario. Never read or seed production data or reset TCC.
5. Record the result with the printed PID:

   ```bash
   swift run lexiray-ops accept record <scenario> --pid 12345 --result passed
   ```

The recorder accepts a pass only from the exact installed process launched with the isolated profile, captures only its windows, then terminates it and cleans its isolated data. Installation uses a crash-safe atomic exchange; there is no transaction receipt, saved PID, or resumable state. A diagnosed failed acceptance may be retried once with `--retry-of <id> --cause <root-cause>`.
