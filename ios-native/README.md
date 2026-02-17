# EmbyTokNative (UIKit)

This folder contains a native iOS/iPadOS UIKit app that plays Emby/Folder MP4 streams with AVPlayer.

## Open in Xcode
- Open `ios-native/EmbyTokNative.xcodeproj`.
- Set your `DEVELOPMENT_TEAM` in the target Signing & Capabilities.
- Ensure the device can reach your Emby/Folder server on the LAN.

## Notes
- HTTP is allowed via `NSAppTransportSecurity` for local servers.
- The app preloads the next 2 videos and uses `AVPlayerItem.preferredForwardBufferDuration` for smoother playback.
