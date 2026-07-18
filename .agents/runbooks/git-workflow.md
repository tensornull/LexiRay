# Git Workflow

The long-lived integration branch is `dev`; `main` represents released source.

## Normal task

1. Ensure `dev` contains the latest `main` release commit.
2. Create a dedicated linked worktree from `dev` as `feat/<task>`, `fix/<task>`,
   `chore/<task>`, or `docs/<task>`; primary checkout changes are rejected.
3. Keep one smallest-complete task per branch.
4. Open the task PR to `dev` and squash merge after local and PR gates pass.

Do not use `codex/<task>` or another agent-specific prefix.

## Repository settings

- `dev` task PRs must run the `build-test` check from `.github/workflows/ci.yml`;
  configure it as required when branch protection is available.
- `main` must require CI and conversation resolution, but CodeQL remains
  scheduled/manual and non-blocking. `required_linear_history` must be disabled
  so the release PR can create its required merge commit.
- `script/release.sh doctor` reads the effective branch rules and fails closed
  when they cannot be verified or still require linear history. Changing GitHub
  protection is an explicit repository administration action, not part of
  ordinary local implementation.

## Release

1. Open `dev` to `main` as the release PR.
2. Merge with a merge commit only—never squash or rebase this PR.
3. Complete the tagged release from `main` using `release.md`.
4. Before any next task, fast-forward `dev` to `main`. If protection prevents a
   direct update, use a dedicated sync PR and preserve the merge topology.

## Emergency hotfix

Branch `fix/<task>` from `main`, merge it to `main`, release if needed, and
immediately sync `main` back to `dev` before normal work resumes.

Ordinary implementation intent does not imply permission to commit, push, open
a PR, merge, tag, or publish. An explicit user request to release/publish a new
version authorizes the whole documented release chain without repeated prompts.

Use a temporary bare remote or dry-run harness when testing topology. Verify
task-to-dev squash, dev-to-main merge commit, main-to-dev fast-forward/sync, and
hotfix backflow without mutating the real remote.
