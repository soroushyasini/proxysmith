Place the built Linux pipeline binary here as:

    proxysmith-pipeline-linux-amd64

Build it from `proxysmith/go/`:

    GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="-s -w" -o proxysmith-pipeline-linux-amd64 .

This folder is copied into `build/linux/x64/release/bundle/bin/` by
`scripts/bundle_desktop_binaries.sh` — see that script for the build-time
hook. `DesktopPipelineService._binaryPath` (lib/services/pipeline_service_desktop.dart)
expects it there, next to the built executable.
