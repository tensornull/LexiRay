# CI and Review Runbook

Run `./script/verify.sh pr` before every push or PR. It first requires the
applicable local handoff evidence, then provides context lint and CI-equivalent
evidence, reusing only evidence bound to the unchanged source fingerprint.

The GitHub CI workflow runs on pushes and PRs for both `dev` and `main`, and
executes `script/context_lint.sh` before generation/build/test. A task PR to
`dev` without that check is a repository-configuration blocker, not a reason to
retarget the PR to `main`.

## Failure discipline

1. Read the failing step before retrying:

   ```bash
   gh run view <run-id> --log-failed
   ```

2. Separate workflow/toolchain failure from an app regression.
3. Reproduce or isolate the smallest practical local step.
4. Fix the root cause; do not bypass validation, delete tests, weaken signing,
   or hide errors to make a check green.
5. Report the run URL, failing step, smallest useful log excerpt, local result,
   and resume command.

Do not burn an interactive session on sleep polling. Use the repository's
resumable status/monitor flow and return to the same run after interruption.

CI, CodeQL, and the Release Build workflow currently require `macos-26` and
`/Applications/Xcode.app`. The earlier `macos-15`/Xcode 16.4 Swift 6.1.2
module-emission crash was a runner/toolchain failure. Do not revert the runner
choice without fresh runner evidence.

## Review

After local PR evidence and an open PR, request the configured reviews:

```bash
./script/request_ai_review.sh <PR_NUMBER>
```

Prioritize actionable P0/P1 findings. Address each with the smallest fix and
rerun the gate it touches. AI review supplements local verification, GitHub
checks, and real GUI acceptance; it replaces none of them.
