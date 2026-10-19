# Menu Stats

A small native macOS menu bar app showing CPU usage, physical memory usage, and free startup disk space. Requires macOS 13 or later and Swift 6 to build. It uses system APIs and has no package dependencies, network access, telemetry, privileged helpers, or automatic login registration.

## Build and run

```sh
bash scripts/build-app.sh
open "outputs/Menu Stats.app"
```

The build script creates a debug app bundle and verifies its local ad-hoc signature before replacing a previous Menu Stats bundle. You can pass a different output directory as the first argument. This is a local app build, not a notarized distribution release.

The app runs in the menu bar without a Dock icon. Click its CPU, RAM, and free disk text to open details. The Top apps table shows five entries with CPU and memory readings; select CPU or Memory to change the ranking. The popover includes Refresh now, Open Activity Monitor, Quit, and a refresh interval of 1, 2, or 5 seconds. The default is 2 seconds; your interval choice is saved locally. If the menu bar is crowded, macOS may hide the item until more space is available.

Use **Quit** beside a desktop app to request that it quit. The panel names the selected app and offers Cancel, Force Quit, or normal Quit. Normal Quit lets the app show its save dialog or decline to exit. If that does not work, choose **Force Quit…** and confirm on the separate screen warning that unsaved changes may be lost. Force Quit uses macOS `NSRunningApplication.forceTerminate()`; it never runs automatically after a failed normal request.

The selection stays fixed while live rankings change, and closing the panel cancels a pending confirmation. A request is not reported as a completed exit. Both actions are disabled for background processes, apps without a verifiable running identity, and Menu Stats itself; the bottom **Quit Menu Stats** button closes this utility. Actions target the selected desktop app instances, so separately running helpers may remain in the statistics. There is no raw PID signaling, shell-based process killing, or elevated access.

## Metrics

- **CPU:** The change in user, system, and nice CPU ticks divided by the change in all ticks, including idle. This is usage across all cores on a 0 to 100% scale. The first reading needs two samples.
- **Memory:** An estimate of physical memory used: anonymous resident pages minus purgeable pages, plus wired pages and the compressor's physical storage. File-backed cache is excluded. Total memory is the installed physical memory reported by macOS. The popover uses binary GiB (1 GiB = 1,073,741,824 bytes). This percentage is not memory pressure and may differ from Activity Monitor's reading.
- **Disk:** Space currently available to this user on `/System/Volumes/Data`, measured as `statfs.f_bavail` times the block size. Total capacity comes from the same volume. Values use decimal GB/TB (1 GB = 1,000,000,000 bytes). Free space excludes additional purgeable capacity that Finder may include. APFS volumes share container space, so this is not a dedicated capacity allocation.
- **Unavailable readings:** Displayed as unknown rather than zero.
- **Top apps CPU:** Interval CPU time divided by elapsed time and the logical core count, on the same whole-machine scale as the menu bar. Both times use Mach absolute-time ticks. Activity Monitor commonly uses 100% per core instead, so its CPU percentages can be higher. A fresh baseline is collected each time the panel opens.
- **Top apps memory:** The physical footprint reported by `proc_pid_rusage`, including compressed memory. Helpers inside an app bundle are grouped under the outermost app. Standalone background processes are also shown; unrelated processes are not merged just because their names match. These figures do not sum directly to the system memory estimate.

System metrics are sampled at the selected refresh interval. Detailed process sampling runs only while the popover is open. Its initial CPU baseline is followed by a second sample after one second, then the selected interval. Protected or exited processes may be unavailable, and the panel indicates partial coverage. The app asks for no additional permissions. A quit request rechecks the originally selected application instance and never substitutes a newly launched app or a process that reused its PID.

For automatic startup, add the installed copy of Menu Stats to System Settings > General > Login Items & Extensions > Open at Login. The app does not register itself automatically.

## Verify

```sh
swift test
swift build
swift run MenuStatsProbe
swift run MenuStatsProbe --apps
bash scripts/build-app.sh
open "outputs/Menu Stats.app" --args --show
```

The probe prints two real samples as JSON, one second apart, without opening the UI. Its first CPU reading is absent while the sampler establishes a baseline. It exits with a failure status if the second sample has missing metrics or errors. `--apps` selects app/process readings and fails on enumeration errors or missing usable CPU readings. For the native smoke check, confirm the menu bar values update, inspect the Top apps table in both sort modes, close and reopen the popover, change the refresh interval, and open Activity Monitor. Validate Cancel, normal Quit, and Force Quit using a disposable test application that refuses normal termination, never another app containing user work. The running app is the interactive preview; no browser or development server is needed.

Sources are split into `MenuStatsCore` for sampling and calculations, `MenuStatsAppControl` for verified quit requests, `MenuStats` for the native interface, and `MenuStatsProbe` for the command-line probe. Generated bundles and Swift build artifacts are kept out of git.
