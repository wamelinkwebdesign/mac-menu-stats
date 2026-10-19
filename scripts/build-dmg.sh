#!/bin/bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: bash scripts/build-dmg.sh [app-path [output-directory]]
Default app: outputs/notarized-release/Menu Stats.app
Default output: outputs/dmg/Menu-Stats-<version>-universal.dmg
Requires CODE_SIGN_IDENTITY with a Developer ID Application certificate.
The app must already be universal, Developer ID signed, and notarized with a ticket.
This script signs the disk image. Notarization and stapling of the DMG are separate.

One-time local packaging dependency setup:
  uv venv work/dmg-build-env --python 3.14
  uv pip install --python work/dmg-build-env/bin/python -r packaging/dmg-requirements.txt
USAGE
}

fail() { printf '%s\n' "$*" >&2; exit 1; }

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi
if [[ "$#" -gt 2 ]]; then
    usage >&2
    exit 2
fi

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
app_path="${1:-$project_dir/outputs/notarized-release/Menu Stats.app}"
output_dir="${2:-$project_dir/outputs/dmg}"
python="$project_dir/work/dmg-build-env/bin/python"
signing_identity="${CODE_SIGN_IDENTITY:-}"
expected_id="nl.wamelink.MenuStats"
expected_team="2TCJ7766UL"

[[ "$(uname -s)" == "Darwin" ]] || fail 'Menu Stats packaging requires macOS.'
while [[ "$app_path" != '/' && "$app_path" == */ ]]; do app_path="${app_path%/}"; done
[[ -d "$app_path" && ! -L "$app_path" ]] || fail 'The input app must be a directory, not a symlink.'
app_path="$(cd -- "$app_path" && pwd -P)"
[[ -n "$signing_identity" ]] || fail 'Set CODE_SIGN_IDENTITY to a Developer ID Application certificate.'
[[ -x "$python" ]] || fail 'The local packaging environment is missing. See --help for setup commands.'

"$python" - "$project_dir/packaging/dmg-requirements.txt" <<'PY'
from importlib.metadata import version
from pathlib import Path
import sys

for requirement in Path(sys.argv[1]).read_text().splitlines():
    name, expected = requirement.split("==")
    if version(name) != expected:
        sys.exit(f"Packaging dependency {name} must be version {expected}. See --help.")
PY

validate_app() {
    local bundle="$1" signature identifier executable architectures
    identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")"
    [[ "$identifier" == "$expected_id" ]] || fail 'The input is not the Menu Stats app.'
    executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Contents/Info.plist")"
    [[ "$executable" == 'MenuStats' ]] || fail 'The app executable name is unexpected.'
    /usr/bin/codesign --verify --deep --strict --all-architectures --verbose=2 \
        -R "=anchor apple generic and certificate leaf[subject.OU] = \"$expected_team\" and identifier \"$expected_id\"" "$bundle"
    signature="$(/usr/bin/codesign --display --verbose=4 "$bundle" 2>&1)"
    /usr/bin/grep -q '^Authority=Developer ID Application:' <<< "$signature" || fail 'The app needs a Developer ID Application signature.'
    architectures="$(/usr/bin/lipo -archs "$bundle/Contents/MacOS/$executable")"
    [[ "$architectures" == 'x86_64 arm64' || "$architectures" == 'arm64 x86_64' ]] || fail 'The app must contain exactly arm64 and x86_64.'
    /usr/bin/xcrun stapler validate "$bundle"
    /usr/sbin/spctl --assess --type execute --verbose=2 "$bundle"
}

validate_app "$app_path"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
[[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]] || fail 'The app version is not a numeric dotted version.'
for asset in background.png background@2x.png; do
    asset_path="$project_dir/packaging/dmg/$asset"
    [[ -f "$asset_path" && ! -L "$asset_path" ]] || fail "Missing source background asset: $asset"
done

while [[ "$output_dir" != '/' && "$output_dir" == */ ]]; do output_dir="${output_dir%/}"; done
[[ ! -L "$output_dir" ]] || fail 'The output directory cannot be a symlink.'
output_dir="$("$python" -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve())' "$output_dir")"
[[ "$output_dir/" != "$app_path/"* ]] || fail 'The output directory cannot be inside the input app.'
mkdir -p -- "$output_dir"
dmg_path="$output_dir/Menu-Stats-$version-universal.dmg"
if [[ -e "$dmg_path" || -L "$dmg_path" ]]; then
    [[ -f "$dmg_path" && ! -L "$dmg_path" ]] || fail 'Refusing to replace a non-file or symlink at the output path.'
fi

staging_dir="$(mktemp -d "$output_dir/.menu-stats-dmg.XXXXXX")"
staged_dmg="$staging_dir/Menu-Stats-$version-universal.dmg"
mount_point="$staging_dir/mount"
mounted=false
cleanup() {
    result=$?
    if [[ "$mounted" == true ]]; then
        if ! /usr/bin/hdiutil detach "$mount_point"; then
            printf 'Could not detach the validation volume. Preserved at %s\n' "$staging_dir" >&2
            exit 1
        fi
    fi
    # This directory was created by mktemp above, never supplied by the caller.
    rm -rf -- "$staging_dir"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

"$python" -m dmgbuild -s "$project_dir/packaging/dmg-settings.py" \
    -D "app=$app_path" -D "project=$project_dir" "Menu Stats" "$staged_dmg"
/usr/bin/hdiutil verify "$staged_dmg"
mkdir -- "$mount_point"
/usr/bin/hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$mount_point" "$staged_dmg"
mounted=true
[[ -L "$mount_point/Applications" && "$(readlink "$mount_point/Applications")" == '/Applications' ]] || fail 'The Applications shortcut is invalid.'
validate_app "$mount_point/Menu Stats.app"
/usr/bin/diff -qr "$app_path" "$mount_point/Menu Stats.app"
/usr/bin/hdiutil detach "$mount_point"
mounted=false

/usr/bin/codesign --force --sign "$signing_identity" --identifier "$expected_id.dmg" --timestamp "$staged_dmg"
/usr/bin/codesign --verify --strict --verbose=2 "$staged_dmg"
signature="$(/usr/bin/codesign --display --verbose=4 "$staged_dmg" 2>&1)"
/usr/bin/grep -q '^Authority=Developer ID Application:' <<< "$signature" || fail 'The disk image needs a Developer ID Application signature.'
/usr/bin/grep -Fxq "TeamIdentifier=$expected_team" <<< "$signature" || fail 'The disk image must be signed by the Menu Stats developer team.'

# Move the complete validated image into place without removing an earlier build first.
if [[ -e "$dmg_path" || -L "$dmg_path" ]]; then
    [[ -f "$dmg_path" && ! -L "$dmg_path" ]] || fail 'Refusing to replace a non-file or symlink at the output path.'
fi
mv -f -- "$staged_dmg" "$dmg_path"
printf '\nBuilt and verified: %s\n' "$dmg_path"
printf 'The app ticket is preserved. Notarize and staple the DMG before publishing it.\n'
