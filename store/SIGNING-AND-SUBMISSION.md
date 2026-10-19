# Signing and submission handoff

Prepared update: 0.9.1. Its player/screensaver packages include hidden diagnostics and distinct screensaver artwork. Signed 0.9.1 packages are available. Player startup and diagnostic retrieval passed on hardware; screensaver Preview and Store analysis remain pending. Do not reuse the signed 0.9.0 packages. See release-status.json.

1. Use the publisher's Roku Developer account and public support contacts. Confirm region choices, privacy/terms URLs, and classification. Publish using the organization's account. Do not include credentials or signing secrets in Git or the release ZIP.
2. Use a spare developer Roku, or arrange a time to interrupt the current test device. Installing either release ZIP replaces that device's sideloaded app. Both entry points must be tested on hardware with rsg_version=1.3 before submission.
3. Reuse the organization's existing Roku signing key if one exists. A new signing key must be created and securely retained by its owner if none exists. Follow Roku's official packaging guide. Generating or changing a key is not part of these unsigned build scripts.
4. In the Roku Development Application Installer, install the player ZIP. Use the Package/Packager page with a short label such as PAL-player-0.9.1 (maximum 32 characters) and the owner's signing credentials to produce the encrypted .pkg. Download and keep that file as pro-announcement-looper-player-0.9.1.pkg.
5. Install the screensaver ZIP on the signing device. Test screensaver Preview. Configure it through the signed companion player; there is no screensaver settings entry. Use PAL-saver-0.9.1 as a short package label. Sign with the SAME key and download pro-announcement-looper-screensaver-0.9.1.pkg. Verify both packages' developer IDs match. Preserve a signed package and the key password securely for future updates.
6. Capture genuine 1920×1080 screenshots from the new build using the bundled demo: Home, presentation details, schedule, and the sample slideshow. Use only content you have rights to publish. Do not submit illustrative mockups or previous-build screenshots as new-build captures. Copy the approved captures into store/screenshots and rerun npm run release.
7. Create separate beta player/screensaver entries, upload signed packages, and use the provided posters/listing copy. Set no sign-in and free/no monetization. Review all values in listing-en-US.json, including publisher-specific public support contacts. Beta apps are temporary QA distribution, not permanent installations.
8. Run Roku's Static Analysis and applicable pre-certification tools, resolve findings, and complete hardware smoke/soak tests. Confirm how Roku will evaluate a LAN utility with no long-form video catalog. Only then create/finish the public listings and submit them for Roku review.

Public privacy/terms/support pages are prepared as repository Markdown files. Their proposed GitHub URLs become usable only after the corresponding commit is pushed and the publisher reviews the text. A dedicated public website may replace those URLs later.

Official references:
- https://developer.roku.com/dev/docs/packaging-channels
- https://developer.roku.com/dev/docs/channel-publishing-guide
- https://developer.roku.com/dev/docs/channel-manifest
- https://developer.roku.com/dev/docs/screensavers

The local release build never signs or installs by itself. Keep device addresses, developer-account details, signing credentials, publisher contacts, and unpublished Store draft IDs in private records outside this repository. Publisher-specific signing and deployment records are not part of the open-source release.
