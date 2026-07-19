# Release

An explicit release creates the only PR path: `dev` to `main`. Confirm `release-ci` succeeded and no unresolved Codex P0/P1 remains. Merge with a merge commit and fast-forward `dev` to `main`.

Manually dispatch `.github/workflows/release.yml` with the exact version and SHA. Do not create a tag locally or start any fallback path. The workflow is solely responsible for building, signing, verifying, tagging, and publishing.
