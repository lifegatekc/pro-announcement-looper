# Roku Dashboard Static Analysis — 0.9.0

Both signed packages were uploaded to unpublished public drafts under the publisher account. This report records actual Dashboard findings; local preflight is not certification.

## Player

Initial run reported one error: RSG 1.3 requires minimum firmware 15.1 or greater. The Dashboard package minimum was updated to v15.1.0 b1 and the same signed package was reuploaded. The fresh run reports zero errors and six warnings. No runtime source change was needed.

Warnings: deprecated InitClientCertificates; GetChannelMemoryLimit, EnableLowGeneralMemoryEvent, GetMemoryLimitPercent, and GetChannelAvailableMemory usage not found; KeyboardDialog advisory for email/PIN entry. The app already listens for memory warning notifications, and its keyboard fields collect a local server address, names and durations rather than account email/PIN credentials. Warnings still need review, not an assumption of exemption.

## Screensaver

The original packaged settings handler was blocked. Merely separating playback/settings scenes did not satisfy the checker. The owner chose configuration through the companion player, so the final standalone screensaver excludes ControlsScene and has no RunScreenSaverSettings entry point or custom OnKeyEvent. A temporary help dialog was removed after hardware testing found its close behavior unreliable. The final simplified candidate reports zero errors and seven warnings.

Configure all settings in Pro Announcement Looper, signed with the same key. The screensaver reads them at startup.

Warnings include App-versus-Screensaver type mismatch, plus the same deprecated API, memory monitoring and keyboard advisories as the player. The Dashboard App/Utility description explicitly includes screensavers; the category is Screensavers. Confirm the expected type with Roku.

Neither app has been submitted or certified. The signed packages and screenshots remain review candidates.
