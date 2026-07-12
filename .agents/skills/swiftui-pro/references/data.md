# State and Observation

- A view owns local state with private `@State`; pass mutable state with a
  binding only where two-way ownership is intentional.
- Follow the project's existing Observation/ObservableObject architecture.
  Do not migrate an entire subsystem merely to modernize one view.
- Keep UI-facing mutable models main-actor isolated unless their ownership and
  synchronization prove another design safe.
- Split observation scope so frequently changing provider/streaming state does
  not invalidate unrelated windows or large view trees.
- Give collection elements stable identity derived from domain data. Never
  create identity during `body` evaluation.
- Avoid side effects inside binding getters, `body`, and layout callbacks.
  Make persistence and async work explicit and cancellable.
- Ensure persisted settings update the rendered state and external/defaults
  changes do not silently leave stale UI.
- Never put API keys or other secrets in `@AppStorage` or ordinary defaults.
