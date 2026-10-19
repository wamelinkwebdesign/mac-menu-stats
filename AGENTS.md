# Menu Stats

## Scope

Native macOS menu bar utility for CPU usage, physical memory usage, and free space on the startup data volume. Keep it small, local, and dependency-free. No network, telemetry, privileged helpers, or automatic startup registration.

## Implementation

- Swift Package Manager, SwiftUI content, and a narrow AppKit status item bridge.
- Minimum macOS 13. Use native system fonts, colors, symbols, controls, and light/dark appearance inside the app.
- The drag-to-Applications DMG uses WAMELINK branding, requested by Dennis on 19 October 2026. Use the approved custom open-W wordmark, Plus Jakarta Sans, and the white/ink/red palette in packaging/dmg. Keep the installation action clear and preserve the native app interface.
- Keep sampling and metric calculations in MenuStatsCore and UI in MenuStats.
- Show unknown/error states explicitly. Never turn failed samples into zero.
- CPU uses an interval sample over all cores. Document the memory and disk definitions.
- Bound history and polling; do not spawn shell commands to collect metrics.
- App quit requests require an explicit named confirmation and a revalidated application identity. Keep normal Quit available. Force Quit requires a separate confirmation warning about unsaved changes and must never run as an automatic fallback. Use NSRunningApplication APIs; do not terminate background services or target by display name alone.
- Do not use em dashes in authored copy.

## Verification and delivery

- Run swift test, swift build, a real metrics probe, and the packaged app smoke check.
- Inspect the actual native menu bar UI. Keep the app running for review.
- A browser development server is unnecessary for this native application; the runnable app is the interactive preview.
- Build the local app bundle with scripts/build-app.sh. Keep generated binaries and work files out of git.
- Work on your own branch, inspect the diff for secrets, commit and push that branch. Default-branch merges and public distribution need explicit approval.
- Keep the working checkout in a local development directory, outside cloud-managed Documents folders. Offloaded build files can stall Swift and Git.
