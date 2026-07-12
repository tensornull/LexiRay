# Bootstrap LexiRay

Bootstrap only the requested repository capability. Follow `AGENTS.md` and the
applicable `.agents/runbooks/` procedure.

Before editing:

- Inspect branch/worktree state and run `./script/preflight.sh change`.
- State the user-visible goal, acceptance matrix, and smallest file scope.
- Preserve clean-room, Swift-only product code, SwiftUI/AppKit boundaries, and
  XcodeGen ownership.

After each edit batch run `./script/verify.sh changed`. Finish with
`./script/verify.sh candidate`; install and Computer Use-accept app changes by
default. Before PR work run `./script/verify.sh pr`.

Report evidence states, checks blocked or skipped, and residual risk.
