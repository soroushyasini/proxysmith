Place the built Windows pipeline binary here as:

    proxysmith-pipeline-windows-amd64.exe

Build it from `proxysmith/go/`:

    GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="-s -w" -o proxysmith-pipeline-windows-amd64.exe .

This folder is copied into `build/windows/x64/runner/Release/bin/` by
`scripts/bundle_desktop_binaries.ps1` — see that script for the build-time
hook. `DesktopPipelineService._binaryPath` (lib/services/pipeline_service_desktop.dart)
expects it there, next to the built .exe.
