# GUI acceptance

List and run explicit scenarios:

```bash
swift run lexiray-ops gui list
swift run lexiray-ops gui run panel_blank history_nav
```

Full GUI requires an audited reason:

```bash
swift run lexiray-ops gui run --all --reason shared-ui
swift run lexiray-ops gui run --all --reason runner-change
swift run lexiray-ops gui run --all --reason explicit
```

The runner blocks before work when Accessibility or Screen Recording is unavailable or any LexiRay process is already running. It never adopts or terminates an unrelated app. Every scenario uses an isolated repository-owned data root, UserDefaults suite, and mock fixtures; the root is deleted after the run.

Each invocation creates one JSON record under ignored `build/verification/<fingerprint>/` and indexes its logs and screenshots. There is no candidate receipt, PID manifest, reuse flag, or resumable matrix.

For a diagnosed retry:

```bash
swift run lexiray-ops gui run panel_blank --retry-of <evidence-id> --cause "specific root cause"
```
