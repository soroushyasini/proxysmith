# ProxySmith contributor instructions

Read [CONSTRAINTS.md](CONSTRAINTS.md) before changing production code.

- Keep the Go desktop pipeline, Android Kotlin pipeline, and Dart event model behaviorally aligned.
- Treat subscription bodies and proxy URIs as untrusted input. Validate at boundaries and never log full subscription URLs or proxy credentials.
- Add or update a focused test before changing behavior.
- Work backend-first, then update the Flutter contract and UI.
- Do not commit IDE state, build output, signing material, generated release archives, or locally bundled pipeline binaries.
- Run the applicable checks documented in the root README before committing.
