# Rider splash

The splash uses the supplied transparent rider artwork, the current app icon,
Arabic Flutter text, and a painted scene of mountains, Sana'a buildings and a
golden road. Android/iOS launch backgrounds stay green until Flutter renders.

The rider logo starts at 12% size in the center of the available screen and
grows into its final position. The entrance runs once, for at most 1.6 seconds,
while the gold outline repeats on a separate 2.4 second timeline during network
checking, API checking and service initialization. Successful startup never
waits for the entrance to finish. Failure stops the glow and exposes Retry;
retry restarts the glow without replaying the entrance. Reduced motion shows
the complete composition without animated tickers.

The scene and bitmap layers have repaint boundaries. The animated outline uses
cached path metrics and layered strokes rather than blur/shader effects. Its
260-point contour is generated offline by `tool/branding/generate_splash_outline.py`.
Frame times have not been benchmarked across physical phones.

`StartupConnectionService` checks network interfaces, then performs a public
`ServiceKindModel/list` request against the configured API. The interface and
API timeouts are 3 and 8 seconds respectively. Failed checks never open home.
Onboarding, returning guests and pending notification destinations retain their
previous behavior after a successful check.

Validation commands:

```powershell
flutter test --no-pub
flutter test --no-pub test/splash_flow_test.dart --dart-define=UPDATE_PREVIEWS=true --update-goldens
flutter build apk --release --target-platform android-x64 --split-per-abi --no-pub
```

The MEmu APK is `build/app/outputs/apk/release/app-x86_64-release.apk`.
The ABI split prevents ARM plugin libraries from causing MEmu to select an
incompatible architecture. `docs/previews/splash-entrance.gif` shows a preview;
raw preview frames live under `../work/rider-splash-motion-frames`.
