# In-app updates

Menu Stats 1.4.0 and later use [Sparkle](https://sparkle-project.org/) to check, download, verify, install, and relaunch updates. The pinned version is in `Package.swift` and `Package.resolved`. The feed is `appcast.xml` in this folder, served from the repository's `main` branch over HTTPS. Archives are hosted in GitHub Releases.

Automatic checks run approximately once a day by default. Users can turn them off in the panel and can always choose **Check for Updates…**. Installation requires their approval. System profiling is disabled and resource readings are never sent. GitHub receives ordinary update requests, including IP address and an app/version user agent.

Version 1.3.2 and earlier do not contain an updater, so those users need one manual upgrade to 1.4.0 or later.

## Trust and signing

Both the feed and downloaded archive require Ed25519 signatures. Archive validation runs before extraction. The release app and DMG also use Developer ID signing and Apple notarization. The signed-feed fallback timeout is disabled, so an invalid feed never becomes trusted after waiting.

The private Sparkle key is stored in the release Mac's login Keychain under account `nl.wamelink.MenuStats`. It is separate from the Apple notarization credential. Never commit, log, or pass the private key in command-line arguments. The corresponding public key is in `packaging/Info.plist`.

Do not generate a replacement key for an existing release. Retain a secure backup of the Keychain and follow [Sparkle's key rotation guidance](https://sparkle-project.org/documentation/#rotating-signing-keys) if a signing key needs to change. Using signed DMGs preserves the Developer ID recovery path for archive verification.

## Publish a release

1. Increment both the displayed version and the strictly increasing `CFBundleVersion` in `packaging/Info.plist`. Resolve packages and run the tests and native smoke checks.
2. Build with `scripts/build-release.sh` and your Developer ID Application identity. The script embeds Sparkle and signs its nested helpers before signing the app.
3. Submit the app archive to Apple's notary service, wait for acceptance, and staple and validate the app. Re-create the ZIP after stapling.
4. Build the DMG with `scripts/build-dmg.sh`. Notarize, staple, and validate the DMG. Do not modify the archive after signing the update feed.
5. Write plain-text release notes and generate the signed feed:

   ```sh
   bash scripts/generate-appcast.sh outputs/release/Menu-Stats-1.4.0-universal.dmg updates/1.4.0.txt
   ```

6. Test an actual update using a disposable Developer ID signed, notarized copy with a lower build number and an isolated test feed. Verify install, relaunch, final version, signatures, and preserved preferences. Also test the current-version result, failed requests, and rejection of a modified signed feed. Never redirect the production installation to a test feed.
7. Review and commit the source, notes, and generated feed. Upload the exact DMG, ZIP, and checksums to the matching GitHub release, then publish `updates/appcast.xml` on `main`. The archives must be available before clients see the new feed.
8. Download the public artifacts and feed, verify checksums and signatures, and check the public feed from the installed app. A raw GitHub feed can take a few minutes to refresh through its cache.

The generator uses Sparkle's official `generate_appcast` and `sign_update` tools. It verifies the Keychain/public-key match, checks the signed and stapled DMG, preserves recent feed entries, embeds the release notes, and rejects mismatched release versions before replacing the feed. Editing the generated XML invalidates its signature; regenerate it instead.
