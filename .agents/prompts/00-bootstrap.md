# Bootstrap

Inspect `AGENTS.md`, current Git/worktree state, relevant source, tests, and history. Create one temporary linked worktree from current `origin/dev` only when the task is authorized to change code. Preserve unrelated dirty work.

Use `swift run lexiray-ops verify changed --base <sha>` for final local scope selection. Unknown paths are a mapping defect and must not trigger broad fallback verification.
