## Release summary

- Version:
- Exact dev SHA:
- User-visible changes:
- Intentionally excluded scope:

## Required gate

- [ ] This is the single `dev` to `main` release pull request.
- [ ] Required `release-ci` completed successfully for this head SHA.
- [ ] No unresolved Codex P0/P1 review finding remains.
- [ ] The PR head was corrected at most once after its first gate.
- [ ] No GUI, installation, Computer Use, signing secret, tag, or publication ran in PR CI.

## Risk and release metadata

- Residual risk or blocked local coverage:
- Version/CHANGELOG/signing/packaging impact:
- [ ] Protected provider, history, defaults, pasteboard, and TCC state were not touched.
- [ ] No copied source/assets/UI, private reverse-engineered behavior, credentials, generated project, or build output is included.

## After merge

- [ ] Fast-forward `dev` to the merge commit.
- [ ] Manually dispatch the Release workflow with the exact version and SHA.
