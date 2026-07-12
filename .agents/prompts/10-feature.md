# Implement One LexiRay Feature

Implement the smallest complete user outcome. Follow `AGENTS.md` and the
relevant `.agents/runbooks/`.

Before editing, record:

- User goal and product assumptions.
- State-based acceptance matrix.
- Files likely to change and tests/scenarios that cover them.
- Relevant roadmap ID only when the item already exists or is durable beyond
  this task.

Run `./script/preflight.sh change`, implement in small batches, and use
`./script/verify.sh changed` after each batch. Add unit coverage for logic and a
new/extended GUI scenario plus accessibility identifiers for visible behavior.

At candidate, run `./script/verify.sh candidate`. For app-binary changes,
automatically install the verified candidate and complete the acceptance matrix
with Computer Use on the installed app's isolated acceptance profile. Run
`./script/verify.sh pr` before any push or PR.

Finish with changed scope, receipt/artifact paths, evidence states, uncovered
states, and residual risk. Do not substitute a manual user checklist for agent
acceptance.
