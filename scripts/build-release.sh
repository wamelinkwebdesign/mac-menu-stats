#!/bin/bash
set -euo pipefail

usage() {
    printf 'Usage: bash scripts/build-release.sh [output-directory]\n'
    printf 'Builds a universal release app. Default output: outputs/release/Menu Stats.app\n'
    printf 'Set CODE_SIGN_IDENTITY to a Developer ID Application identity for distribution.\n'
    printf 'Without it, the app is ad-hoc signed for local testing only.\n'
    printf 'Notarization and stapling are separate steps; this script does not perform them.\n'
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
output_dir="${1:-$project_dir/outputs/release}"
signing_identity="${CODE_SIGN_IDENTITY:-}"

if [[ "$(uname -s)" != "Darwin" ]]; then
    printf 'Menu Stats requires macOS.\n' >&2
    exit 1
fi

icon_path="$project_dir/packaging/icon/AppIcon.icns"
if [[ ! -s "$icon_path" ]] || ! /usr/bin/sips -g format "$icon_path" 2>/dev/null | /usr/bin/grep -q 'format: icns'; then
    printf 'Missing or invalid macOS app icon: %s\n' "$icon_path" >&2
    exit 1
fi

# Keep debug information and local source paths out of the distributed executable.
build_options=(
    --package-path "$project_dir"
    --configuration release
    --arch arm64 --arch x86_64
    -debug-info-format none
    --disable-index-store
    -Xswiftc -file-prefix-map -Xswiftc "$project_dir=."
    -Xcc "-ffile-prefix-map=$project_dir=."
)
swift build "${build_options[@]}" --product MenuStats
binary_dir="$(swift build "${build_options[@]}" --show-bin-path)"
binary_path="$binary_dir/MenuStats"
if [[ ! -x "$binary_path" ]]; then
    printf 'Build did not produce an executable at %s\n' "$binary_path" >&2
    exit 1
fi
/usr/bin/plutil -lint "$project_dir/packaging/Info.plist"

mkdir -p -- "$output_dir"
output_dir="$(cd -- "$output_dir" && pwd -P)"
bundle_path="$output_dir/Menu Stats.app"
staging_dir="$(mktemp -d "$output_dir/.menu-stats-release.XXXXXX")"
staged_bundle="$staging_dir/Menu Stats.app"
previous_bundle="$staging_dir/previous.app"
replacement_complete=false

cleanup() {
    result=$?
    if [[ -d "$previous_bundle" && "$replacement_complete" == false ]]; then
        if [[ ! -e "$bundle_path" && ! -L "$bundle_path" ]]; then
            if ! mv -- "$previous_bundle" "$bundle_path"; then
                printf 'Could not restore the previous app. It is preserved at %s\n' "$previous_bundle" >&2
                exit 1
            fi
        else
            printf 'Replacement was interrupted. The previous app is preserved at %s\n' "$previous_bundle" >&2
            exit 1
        fi
    fi
    # This directory is created by mktemp above, never supplied by the caller.
    rm -rf -- "$staging_dir"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

mkdir -p -- "$staged_bundle/Contents/MacOS" "$staged_bundle/Contents/Resources"
executable="$staged_bundle/Contents/MacOS/MenuStats"
cp -- "$binary_path" "$executable"
cp -- "$project_dir/packaging/Info.plist" "$staged_bundle/Contents/Info.plist"
cp -- "$icon_path" "$staged_bundle/Contents/Resources/AppIcon.icns"
/usr/bin/xcrun strip -S -x "$executable"
/usr/bin/lipo "$executable" -verify_arch arm64
/usr/bin/lipo "$executable" -verify_arch x86_64
/usr/bin/strings "$executable" > "$staging_dir/executable-strings.txt"
if /usr/bin/grep -Fq -- "$project_dir" "$staging_dir/executable-strings.txt"; then
    printf 'Refusing to package an executable containing its local project path.\n' >&2
    exit 1
fi

bash "$project_dir/scripts/embed-sparkle.sh" "$project_dir" "$staged_bundle" "$signing_identity"
if [[ -n "$signing_identity" ]]; then
    /usr/bin/codesign --force --sign "$signing_identity" --options runtime --timestamp "$staged_bundle"
    /usr/bin/codesign --display --verbose=4 "$staged_bundle" > "$staging_dir/signature.txt" 2>&1
    if ! /usr/bin/grep -q '^Authority=Developer ID Application:' "$staging_dir/signature.txt"; then
        printf 'CODE_SIGN_IDENTITY must identify a Developer ID Application certificate.\n' >&2
        exit 1
    fi
else
    /usr/bin/codesign --force --sign - --timestamp=none "$staged_bundle"
fi
/usr/bin/codesign --verify --deep --strict --all-architectures --verbose=2 "$staged_bundle"

# Only replace a matching app after the new universal bundle has passed validation.
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
replacement_complete=true

printf '\nBuilt and verified universal release app: %s\n' "$bundle_path"
if [[ -n "$signing_identity" ]]; then
    printf 'Developer ID signed with hardened runtime. This script does not notarize the app.\n'
else
    printf 'Ad-hoc signed for local testing only. This app is not notarized.\n'
fi
