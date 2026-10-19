# Menu Stats

A small native macOS menu bar app showing CPU usage, physical memory usage, and free startup disk space. Requires macOS 13 or later and Swift 6 to build. It uses system APIs and has no package dependencies, network access, telemetry, privileged helpers, or automatic login registration.

## Build and run

```sh
bash scripts/build-app.sh
open "outputs/Menu Stats.app"
```

The build script creates a debug app bundle and verifies its local ad-hoc signature before replacing a previous Menu Stats bundle. You can pass a different output directory as the first argument. This is a local app build, not a notarized distribution release.

The app runs in the menu bar without a Dock icon. Click its CPU, RAM, and free disk text to open details. The popover includes Refresh now, Open Activity Monitor, Quit, and a refresh interval of 1, 2, or 5 seconds. The default is 2 seconds; your interval choice is saved locally. If the menu bar is crowded, macOS may hide the item until more space is available.

## Metrics

- **CPU:** The change in user, system, and nice CPU ticks divided by the change in all ticks, including idle. This is usage across all cores on a 0 to 100% scale. The first reading needs two samples.
- **Memory:** An estimate of physical memory used: anonymous resident pages minus purgeable pages, plus wired pages and the compressor's physical storage. File-backed cache is excluded. Total memory is the installed physical memory reported by macOS. The popover uses binary GiB (1 GiB = 1,073,741,824 bytes). This percentage is not memory pressure and may differ from Activity Monitor's reading.
- **Disk:** Space currently available to this user on `/System/Volumes/Data`, measured as `statfs.f_bavail` times the block size. Total capacity comes from the same volume. Values use decimal GB/TB (1 GB = 1,000,000,000 bytes). Free space excludes additional purgeable capacity that Finder may include. APFS volumes share container space, so this is not a dedicated capacity allocation.
- **Unavailable readings:** Displayed as unknown rather than zero.

All metrics are sampled at the selected refresh interval.

## Verify

```sh
swift test
swift build
swift run MenuStatsProbe
bash scripts/build-app.sh
open "outputs/Menu Stats.app" --args --show
```

The probe prints two real samples as JSON, one second apart, without opening the UI. Its first CPU reading is absent while the sampler establishes a baseline. It exits with a failure status if the second sample has missing metrics or errors. For the native smoke check, confirm the menu bar values update, click the item to inspect details, change the refresh interval, and open Activity Monitor. The running app is the interactive preview; no browser or development server is needed.

Sources are split into `MenuStatsCore` for sampling and calculations, `MenuStats` for the native interface, and `MenuStatsProbe` for the command-line probe. Generated bundles and Swift build artifacts are kept out of git.
