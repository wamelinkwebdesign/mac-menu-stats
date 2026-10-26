# Menu Stats: development notes

Technical details for building, verifying and releasing Menu Stats. For installing and using the app, see the [README](../README.md).

## Build a local debug app

Requires a Swift 6 or newer compiler and the macOS SDK (Xcode or Command Line Tools). Clone into a folder outside cloud-managed Documents folders:

```sh
git clone https://github.com/wamelinkwebdesign/mac-menu-stats.git
cd mac-menu-stats
bash scripts/build-app.sh
open outputs
```

The script creates `outputs/Menu Stats.app` with an ad-hoc signature. Pass another folder as the first argument to change the output location.

## Tested hardware

The 1.4.0 release was run on Apple silicon. The Intel slice is included and signature-checked, but has not been run on an Intel Mac. Release notes and SHA-256 checksums are on the [releases page](https://github.com/wamelinkwebdesign/mac-menu-stats/releases).

## What the readings mean

Menu Stats and Activity Monitor may show different values because they use different definitions and sampling intervals.

| Reading | Definition |
| --- | --- |
| System CPU | The change in user, system, and nice CPU ticks divided by the change in all ticks, including idle. Usage across all cores is shown on a 0 to 100% scale. |
| System memory | An estimate of physical memory used: anonymous resident pages minus purgeable pages, plus wired pages and the compressor's physical storage. File-backed cache is excluded. This percentage is not memory pressure. |
| Free disk space | Space currently available to the user on `/System/Volumes/Data`, using `statfs.f_bavail` times the block size. Purgeable capacity that Finder may include is excluded. APFS volumes share container space. |
| App CPU | Interval CPU time divided by elapsed time and the logical core count, using Mach absolute-time ticks. It uses the same whole-machine scale as the menu bar. Activity Monitor commonly uses 100% per core, so its percentages can be higher. |
| App memory | The physical footprint reported by `proc_pid_rusage`, including compressed memory. These figures do not sum directly to the system memory estimate. |

Memory uses binary GiB, where 1 GiB is 1,073,741,824 bytes. Total memory is the installed physical memory reported by macOS. Disk capacity uses decimal GB/TB, where 1 GB is 1,000,000,000 bytes; total capacity comes from the same startup data volume.

Helpers inside an app bundle are grouped under the outermost app. Standalone background processes are also listed. Unrelated processes are not merged simply because their names match.

Unavailable readings are shown as unknown, never as zero. Protected or exited processes may be unavailable, and the panel indicates partial coverage. A fresh app CPU baseline is collected whenever the panel opens, followed by a second sample after one second and then the chosen refresh interval.

## Privacy and app control in detail

Resource collection stays on your Mac and uses system APIs rather than shell commands. Update checks contact a signed feed hosted on GitHub; approved updates download from GitHub Releases. GitHub receives ordinary request information such as IP address and app/version user agent. CPU, memory, disk, and app-usage readings are never uploaded. Sparkle's system profiling is disabled.

[Sparkle](https://sparkle-project.org/) verifies the signed update feed and the archive before extraction, then handles installation and relaunch. The app asks for no additional monitoring permissions. macOS may request administrator approval if the installed app is not writable by your account.

Normal Quit and Force Quit use `NSRunningApplication`. Each request rechecks the originally selected application instance, including its identity and lifetime. It never substitutes a newly launched app or a process that reused the selected app's PID. There is no raw PID signaling, shell-based process killing, or elevated access.

## Verification

```sh
swift test
swift build
swift run MenuStatsProbe
swift run MenuStatsProbe --apps
bash scripts/build-app.sh
open "outputs/Menu Stats.app" --args --show
```

The probe prints two real samples as JSON, one second apart, without opening the UI. Its first CPU reading is absent while the sampler establishes a baseline. It exits with a failure status if the second sample has missing metrics or errors. `--apps` selects app/process readings and fails on enumeration errors or missing usable CPU readings.

For a native smoke check, confirm that menu bar values update, inspect both app rankings, close and reopen the panel, change the refresh interval, and open Activity Monitor. Validate Cancel, normal Quit, and Force Quit with a disposable test application that refuses normal termination. Do not use an app containing unsaved work for this check. The running app is the interactive preview; no browser or development server is needed.

| Component | Responsibility |
| --- | --- |
| `MenuStatsCore` | System and app sampling, grouping, and metric calculations. |
| `MenuStatsAppControl` | Verified normal and force quit requests. |
| `MenuStats` | Native menu bar interface and panel. |
| `MenuStatsProbe` | Command-line probes for live readings. |
| `CProcessStats` | C bridge to macOS process APIs. |

Generated app bundles, work files, and Swift build artifacts are kept out of git.

## Build a release bundle

```sh
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" bash scripts/build-release.sh
```

This creates `outputs/release/Menu Stats.app` with optimized Apple silicon and Intel executables and validates its signature. Signing with Developer ID enables the hardened runtime and a secure timestamp. Without `CODE_SIGN_IDENTITY`, the script creates an explicitly ad-hoc signed local build. The script does not notarize or upload the app.

The build scripts embed the pinned Sparkle framework and its license, preserve its symlinks and helper entitlements, and sign nested code before the app. See [the update release guide](../updates/README.md) for notarizing, generating the signed feed, testing an upgrade, and publishing future versions.

## Build the branded DMG

The DMG packages an already notarized and stapled release app. Its build tools run in a local environment under `work/`; they are not included in the application. With `uv` available, set them up once:

```sh
uv venv work/dmg-build-env --python 3.14
uv pip install --python work/dmg-build-env/bin/python -r packaging/dmg-requirements.txt
```

Build and sign the disk image:

```sh
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  bash scripts/build-dmg.sh "outputs/notarized-release/Menu Stats.app"
```

The script validates the app's signature and ticket, creates the WAMELINK Finder layout, verifies the Applications shortcut and copied app, and signs `outputs/dmg/Menu-Stats-<version>-universal.dmg`. It requires the Menu Stats developer team and preserves an earlier output if validation fails. Submit that final DMG to Apple's notary service and staple its ticket before publishing:

```sh
xcrun notarytool submit outputs/dmg/Menu-Stats-1.4.0-universal.dmg \
  --keychain-profile YOUR_NOTARY_PROFILE --wait
xcrun stapler staple outputs/dmg/Menu-Stats-1.4.0-universal.dmg
xcrun stapler validate outputs/dmg/Menu-Stats-1.4.0-universal.dmg
```

The editable background renderer, brand sources, and font license are documented in [packaging/dmg/README.md](../packaging/dmg/README.md).

## App icon

The native app icon is included in both local and release bundles. Its editable renderer and all macOS sizes are documented in [packaging/icon/README.md](../packaging/icon/README.md).
