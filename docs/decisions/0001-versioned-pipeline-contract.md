# ADR-0001: Use one additive pipeline contract across platforms

## Status

Accepted

## Date

2026-09-09

## Context

The Flutter UI consumes nested Method/EventChannel data on Android and prefixed JSON lines from a Go child process on desktop. Sampling, supported protocols, measurement attempts, and error behavior had drifted between those implementations. Replacing either backend would make the release substantially riskier.

## Decision

Keep Go as the desktop/CLI engine and Kotlin/libv2ray as the Android engine, but define one Dart-facing options/event contract. Extend result and done events with optional metrics while retaining old fields. Validate options at every external boundary. Align protocol filtering, exact sampling, ranking, and measurement policy in both backends.

Pass the desktop subscription and test URLs over stdin rather than process arguments. Run Android work under a data-sync foreground-service lifetime. Treat TUIC as unsupported because Xray has no TUIC outbound; implement Hysteria2 using the pinned Xray configuration shape.

## Alternatives considered

### Replace the Android backend with the Go executable

Rejected for this release: packaging and launching an Android Go executable adds ABI, sandbox, process-lifecycle, and IPC work beyond the existing verified AAR integration.

### Make Dart fetch and normalize subscriptions

Rejected: it would duplicate sensitive parsing across three layers and would not remove backend validation requirements.

### Break the event protocol and release a new version

Rejected: additive fields preserve compatibility with already bundled desktop binaries and keep failures understandable during staged upgrades.

## Consequences

- The same acceptance tests are mirrored in Go, Kotlin, and Dart where practical.
- Protocol support remains intentionally narrower than generic subscription formats.
- The two engines may still differ internally, but user-visible ranking semantics and errors are consistent.
- Native JNI hard hangs remain a documented limitation until process isolation is implemented.
