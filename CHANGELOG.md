# Changelog

## 2.4.0 - 2026-09-10

- Rank the globally best candidates using median latency, reliability, and jitter.
- Bound subscription downloads, reject unsafe URLs, deduplicate links, and sample exact counts.
- Add Hysteria2 support using the pinned Xray configuration format; explicitly reject unsupported TUIC.
- Keep Android testing alive with a foreground data-sync service.
- Pass desktop subscription and test URLs over standard input instead of exposing them in process arguments.
- Persist display and testing preferences, add advanced testing controls, and show result quality and QR codes.
- Validate saved sources, confirm deletion, provide undo, and refresh the source picker after edits.
- Add accessible tap targets, semantic labels, CI, dependency updates, deterministic release packaging, and checksums.
- Add a localized in-app privacy-policy link and Google Play publication documentation.
- Produce a signed, versioned Android App Bundle for Google Play alongside release APKs.
- Harden the Linux generator and deployment workflow with scoped cleanup, validation, and rollback.
