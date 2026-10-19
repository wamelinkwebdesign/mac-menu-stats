#!/bin/bash
set -euo pipefail

if [[ "$#" != 2 ]]; then
    printf 'Usage: bash scripts/generate-appcast.sh <notarized-dmg> <release-notes.txt>\n' >&2
    exit 2
fi

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tools_dir="$project_dir/.build/artifacts/sparkle/Sparkle/bin"
plist="$project_dir/packaging/Info.plist"
account="nl.wamelink.MenuStats"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
archive_name="Menu-Stats-$version-universal.dmg"
download_prefix="https://github.com/wamelinkwebdesign/mac-menu-stats/releases/download/v$version/"

if [[ ! -x "$tools_dir/generate_appcast" || ! -x "$tools_dir/sign_update" ]]; then
    printf 'Resolve the pinned Sparkle package with swift package resolve first.\n' >&2
    exit 1
fi
if [[ ! -f "$1" || -L "$1" || "$(basename -- "$1")" != "$archive_name" || ! -s "$2" ]]; then
    printf 'Expected %s and a nonempty plain-text release notes file.\n' "$archive_name" >&2
    exit 1
fi
public_key="$("$tools_dir/generate_keys" --account "$account" -p)"
if [[ "$public_key" != "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist")" ]]; then
    printf 'The Keychain signing key does not match the app public key.\n' >&2
    exit 1
fi

/usr/bin/codesign --verify --strict --verbose=2 "$1"
/usr/bin/xcrun stapler validate "$1"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "$1"

mkdir -p -- "$project_dir/updates"
staging_dir="$(mktemp -d "$project_dir/updates/.appcast.XXXXXX")"
trap 'rm -rf -- "$staging_dir"' EXIT
cp -- "$1" "$staging_dir/$archive_name"
cp -- "$2" "$staging_dir/${archive_name%.dmg}.txt"
if [[ -f "$project_dir/updates/appcast.xml" ]]; then
    cp -- "$project_dir/updates/appcast.xml" "$staging_dir/appcast.xml"
fi
"$tools_dir/generate_appcast" --account "$account" \
    --download-url-prefix "$download_prefix" --maximum-deltas 0 \
    --embed-release-notes --link 'https://github.com/wamelinkwebdesign/mac-menu-stats' \
    -o "$staging_dir/appcast.xml" "$staging_dir"
"$tools_dir/sign_update" --account "$account" --verify "$staging_dir/appcast.xml"

# Refuse to publish an archive whose embedded version differs from this source checkout.
python3 - "$staging_dir/appcast.xml" "$build" "$version" "$download_prefix$archive_name" <<'PY'
import sys
import xml.etree.ElementTree as ET
feed, build, version, url = sys.argv[1:]
ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
items = ET.parse(feed).findall('./channel/item')
matches = [item for item in items if item.findtext('sparkle:version', namespaces=ns) == build]
if len(matches) != 1:
    raise SystemExit('Expected exactly one appcast item matching the source build.')
item = matches[0]
enclosure = item.find('enclosure')
if item.findtext('sparkle:shortVersionString', namespaces=ns) != version or enclosure is None or enclosure.get('url') != url:
    raise SystemExit('Appcast release version or download URL does not match this source checkout.')
if not enclosure.get('{%s}edSignature' % ns['sparkle']):
    raise SystemExit('Appcast archive signature is missing.')
PY
mv -- "$staging_dir/appcast.xml" "$project_dir/updates/appcast.xml"
printf '\nGenerated signed updates/appcast.xml. Upload the exact DMG before publishing this feed.\n'
