# Code Hygiene

- Keep the change surgical and match existing file/type ownership.
- Explain non-obvious lifecycle, concurrency, TCC, or AppKit bridge decisions;
  do not narrate self-evident code.
- Add focused logic tests and real GUI evidence for rendered behavior.
- Never commit secrets, `.codex`, generated Xcode projects, DerivedData,
  xcresults, or release artifacts.
- Remove only imports, helpers, or files made unused by the current change.
- Preserve clean-room and Swift-only product-code constraints.
