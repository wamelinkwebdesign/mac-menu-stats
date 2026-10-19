#!/bin/bash
set -euo pipefail

usage() {
    printf 'Usage: bash scripts/build-app.sh [output-directory]\n'
    printf 'Builds a locally signed debug app. Default output: outputs/Menu Stats.app\n'
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi
if [[ "$#" -gt 1 ]]; then
    usage >&2
    exit 2
fi

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
output_dir="${1:-$project_dir/outputs}"

if [[ "$(uname -s)" != "Darwin" ]]; then
    printf 'Menu Stats requires macOS.\n' >&2
    exit 1
fi

icon_path="$project_dir/packaging/icon/AppIcon.icns"
if [[ ! -s "$icon_path" ]] || ! /usr/bin/sips -g format "$icon_path" 2>/dev/null | /usr/bin/grep -q 'format: icns'; then
    printf 'Missing or invalid macOS app icon: %s\n' "$icon_path" >&2
    exit 1
fi

# Finish and validate the build before touching an existing app bundle.
swift build --package-path "$project_dir" --configuration debug --product MenuStats
binary_dir="$(swift build --package-path "$project_dir" --configuration debug --show-bin-path)"
binary_path="$binary_dir/MenuStats"
if [[ ! -x "$binary_path" ]]; then
    printf 'Build did not produce an executable at %s\n' "$binary_path" >&2
    exit 1
fi
/usr/bin/plutil -lint "$project_dir/packaging/Info.plist"

mkdir -p -- "$output_dir"
output_dir="$(cd -- "$output_dir" && pwd -P)"
bundle_path="$output_dir/Menu Stats.app"
staging_dir="$(mktemp -d "$output_dir/.menu-stats-build.XXXXXX")"
staged_bundle="$staging_dir/Menu Stats.app"
previous_bundle="$staging_dir/previous.app"

cleanup() {
    result=$?
    # Restore the old app if replacing it was interrupted between the moves.
    if [[ -d "$previous_bundle" && ! -e "$bundle_path" ]]; then
        if ! mv -- "$previous_bundle" "$bundle_path"; then
            printf 'Could not restore the previous app. It is preserved at %s\n' "$previous_bundle" >&2
            exit 1
        fi
    fi
    # This path is created by mktemp above, never supplied by the caller.
    rm -rf -- "$staging_dir"
    exit "$result"
}
trap cleanup EXIT

mkdir -p -- "$staged_bundle/Contents/MacOS" "$staged_bundle/Contents/Resources"
cp -- "$binary_path" "$staged_bundle/Contents/MacOS/MenuStats"
cp -- "$project_dir/packaging/Info.plist" "$staged_bundle/Contents/Info.plist"
cp -- "$icon_path" "$staged_bundle/Contents/Resources/AppIcon.icns"
bash "$project_dir/scripts/embed-sparkle.sh" "$project_dir" "$staged_bundle" ""
/usr/bin/codesign --force --sign - --timestamp=none "$staged_bundle"
/usr/bin/codesign --verify --deep --strict --all-architectures --verbose=2 "$staged_bundle"

if [[ -e "$bundle_path" || -L "$bundle_path" ]]; then
    if [[ -L "$bundle_path" || ! -d "$bundle_path" ]]; then
        printf 'Refusing to replace a non-directory or symlink: %s\n' "$bundle_path" >&2
        exit 1
    fi
    existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle_path/Contents/Info.plist" 2>/dev/null || true)"
    if [[ "$existing_id" != "nl.wamelink.MenuStats" ]]; then
        printf 'Refusing to replace an unrelated app: %s\n' "$bundle_path" >&2
        exit 1
    fi
    mv -- "$bundle_path" "$previous_bundle"
fi
mv -- "$staged_bundle" "$bundle_path"

printf '\nBuilt and verified: %s\n' "$bundle_path"
printf 'Open the app with: open "%s"\n' "$bundle_path"
