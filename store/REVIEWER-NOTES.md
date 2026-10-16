# Reviewer instructions — release candidate 0.9.0

## App classification and access

This is a local-network display utility, not a video catalog or subscription service. There are no accounts, ads, payments, analytics, or sign-in. The publisher should confirm the applicable utility/screensaver certification criteria with Roku. No movie/episode deep-link catalog is supplied; do not claim a formal exemption unless Roku confirms it.

## Test without a ProPresenter machine

Player: launch the app, open Connection & TV settings, and select Try offline demo. Three original sample slides loop at six-second intervals with a 0.3-second dissolve. Play/Pause holds/resumes; Left/Right changes slides. Back or * ends the demo and restores the original configuration. Demo mode never writes settings to the registry and requires no network request.

Screensaver: with no configured presentations, use Roku's screensaver Preview. Bundled slides appear without a server. A remote key exits under normal Roku screensaver behavior. All configuration is in the companion player. There is no screensaver settings entry or custom key handler. Install both packages signed with the same key to test shared configuration.

## Full integration test

Use a ProPresenter machine reachable on the same LAN, or run the read-only mock server included in scripts/mock_server.py on a separate machine. See README for its commands. The mock is a development test fixture; it is not bundled or launched by the Roku app. Do not use the church's private IP addresses as reviewer credentials or publicly expose a church computer.

Configure the reachable address, add a presentation, set duration, and choose Show now. Add a second presentation and schedule switches through Schedule. Verify cached playback after disconnecting the server, safe failure on refresh, periodic background checks, and a static one-slide presentation. Optional remote actions are disabled by default and exist only in the player.

## Scope and known platform constraints

Images only. Player and standalone screensaver are separate app submissions signed with the same key to share registry settings. Caches are independent. This app respects the system screensaver and does not keep the OS awake by fake activity. Device power, network control, and screensaver settings are user-controlled. Screensavers do not accept remote API commands or play video.

## Validation status

Version 0.9.0 compiles and passes 248 automated checks plus the mock API suite. On the Streaming Stick 4K, the player and standalone screensaver both completed offline-demo loops under rsg_version=1.3. Player Play/Pause and Back-to-Home were checked. Genuine release screenshots were captured from the device. Both .pkg files were signed with the same publisher signing identity.

A new full service-length soak and full ProPresenter integration on this build remain to be completed. The earlier long-running session was on the previous build. Screensaver Preview completed two demo loops on the companion-configured candidate. A temporary settings-help dialog had a close issue and was removed entirely; all configuration is now in the player. The final screensaver has no settings entry point. See STATIC-ANALYSIS.md for Dashboard results and remaining warnings. Do not mark this build certified until Roku approves it.
