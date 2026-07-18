# CI and Review Runbook

Run `./script/verify.sh pr` before every push or PR. It first requires the
applicable local handoff evidence, then provides context lint and CI-equivalent
evidence, reusing only evidence bound to the unchanged source fingerprint.

The GitHub CI workflow runs on pushes and PRs for both `dev` and `main`, cancels
superseded runs, and always executes `script/context_lint.sh`. Swift/build input
changes run the full Xcode lane; script/workflow changes run control-plane
tests; documentation and prototype-only changes do not start Xcode. A task PR
to `dev` without `build-test` is a repository-configuration blocker.
Script control-plane tests run through `script/run_control_plane_tests.sh` with
four isolated workers by default; use the same runner locally so CI and local
gates retain the same coverage without the former serial four-minute delay.
CI downloads the repository-pinned SwiftFormat release and verifies its
published SHA-256 before use. Local gates use `script/swiftformat_tool.sh` and
fail closed on a version mismatch; do not use an unpinned Homebrew latest binary
as evidence.
Branch protection on `dev` and `main` requires only `build-test`; CodeQL alerts
are triaged asynchronously as repair work and are never added to the blocking
merge or release chain.

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

CI, scheduled/manual CodeQL, and the Release Build workflow use `macos-26`.
CodeQL is diagnostic and never a required PR, merge, or release check. The
earlier `macos-15`/Xcode 16.4 Swift 6.1.2
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
