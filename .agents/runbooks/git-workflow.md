# Git workflow

## Daily work

1. Fetch `origin` and ensure no other task is writing to `dev`.
2. Create a Git linked worktree from current `origin/dev`.
3. Implement and run changed-scope local verification.
4. With explicit delivery authorization, create one atomic commit and fast-forward push directly to `dev`.
5. Confirm the push created no Actions run, remove the linked worktree, and prune.

Do not open task pull requests to `dev`. Never leave a task worktree, dirty task branch, or detached checkout after delivery.

## Release

An explicit release opens one `dev` to `main` PR. Merge commits are required; squash and rebase are disabled. `main` is non-linear and non-strict, so the PR is not updated solely to rerun CI.

If the first gate finds a real blocking defect, make one diagnosed correction and allow one additional `release-ci` run. A second failure closes the release attempt. After merge, fast-forward `dev` to `main` before another task starts.
