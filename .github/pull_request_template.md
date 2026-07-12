## Summary

- User outcome:
- Scope intentionally excluded:
- Roadmap ID (if applicable):

## Acceptance Matrix

| State / interaction | Expected result | Evidence |
| --- | --- | --- |
|  |  |  |

## Verification Receipt

- Source fingerprint:
- Candidate receipt:
- GUI scenarios:
- Screenshot/contact-sheet directory:
- Installed version/build/CDHash:
- Computer Use evidence:

- [ ] `./script/preflight.sh change`
- [ ] `./script/verify.sh changed`
- [ ] `./script/verify.sh candidate`
- [ ] `./script/verify.sh pr`
- [ ] Every relevant screenshot/contact sheet was visually inspected
- [ ] App-binary changes were atomically installed and accepted with Computer Use
- [ ] Protected real provider/history/defaults data was not touched
- [ ] Blocked or uncovered states are named below

## Review and Risk

- [ ] GitHub Copilot and Codex reviews requested when required
- [ ] Actionable findings addressed with the affected gate rerun
- Residual risk / blocked coverage:

## Release Impact

- Version, CHANGELOG, README, release notes, signing, or packaging impact:
- [ ] Gatekeeper and SHA-256 guidance remains accurate for release changes

## Clean-Room Check

- [ ] No copied GPL source/assets/UI, Objective-C, private reverse-engineered
      behavior, generated project edits, secrets, or generated build output
