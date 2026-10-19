#!/bin/bash
set -euo pipefail

# Called only while constructing a fresh staging bundle in the build scripts.
if [[ "$#" -ne 3 ]]; then
    printf 'Usage: bash scripts/embed-sparkle.sh project-directory staged-app signing-identity\n' >&2
    exit 2
fi

project_dir="$1"
bundle_path="$2"
signing_identity="$3"
artifact_dir="$project_dir/.build/artifacts/sparkle/Sparkle"
source_framework="$artifact_dir/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
framework="$bundle_path/Contents/Frameworks/Sparkle.framework"
license_path="$project_dir/packaging/Sparkle-LICENSE"

if [[ ! -d "$source_framework" || -L "$source_framework" ]]; then
    printf 'Missing Sparkle binary artifact. Resolve and build the Swift package first.\n' >&2
    exit 1
fi
framework_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$source_framework/Resources/Info.plist")"
if [[ "$framework_version" != "2.10.0" ]]; then
    printf 'Recheck the nested signing layout before packaging Sparkle %s.\n' "$framework_version" >&2
    exit 1
fi
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle_path/Contents/Info.plist")"
if [[ -L "$bundle_path" || "$bundle_id" != "nl.wamelink.MenuStats" || -e "$framework" || -L "$framework" ]]; then
    printf 'Expected a fresh Menu Stats staging bundle without Sparkle.\n' >&2
    exit 1
fi
if [[ ! -s "$license_path" ]] || ! /usr/bin/cmp -s "$artifact_dir/LICENSE" "$license_path"; then
    printf 'Sparkle license notice is missing or does not match the pinned artifact.\n' >&2
    exit 1
fi

# SwiftPM verifies the artifact checksum; verify its existing nested code seals too.
/usr/bin/codesign --verify --deep --strict --all-architectures "$source_framework"
mkdir -p -- "$bundle_path/Contents/Frameworks" "$bundle_path/Contents/Resources"
# ditto retains framework symlinks, executable permissions, and resource contents.
/usr/bin/ditto "$source_framework" "$framework"
cp -- "$license_path" "$bundle_path/Contents/Resources/Sparkle-LICENSE"

sign_options=(--force --sign "${signing_identity:--}")
if [[ -n "$signing_identity" ]]; then
    sign_options+=(--options runtime --timestamp)
else
    # Debug ad-hoc signing must not turn on hardened-runtime library validation.
    sign_options+=(--options 0 --timestamp=none)
fi

# Fixed, inside-out signing order for Sparkle 2.10.0. Do not use --deep to sign:
# helpers have different entitlements, including Autoupdate's application identity.
# https://sparkle-project.org/documentation/sandboxing/#code-signing
nested_code=(
    "$framework/Versions/B/XPCServices/Installer.xpc"
    "$framework/Versions/B/XPCServices/Downloader.xpc"
    "$framework/Versions/B/Autoupdate"
    "$framework/Versions/B/Updater.app"
)
for code_path in "${nested_code[@]}"; do
    /usr/bin/codesign "${sign_options[@]}" --preserve-metadata=entitlements "$code_path"
    /usr/bin/codesign --verify --strict --all-architectures "$code_path"
done
/usr/bin/codesign "${sign_options[@]}" "$framework"
/usr/bin/codesign --verify --deep --strict --all-architectures "$framework"
/usr/bin/lipo "$framework/Versions/B/Sparkle" -verify_arch arm64
/usr/bin/lipo "$framework/Versions/B/Sparkle" -verify_arch x86_64

printf 'Embedded and signed Sparkle %s.\n' "$framework_version"
