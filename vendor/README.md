# Android location notification icon

`geolocator_android` is the unmodified upstream 5.0.3 package, except for
`android/src/main/java/com/baseflow/geolocator/location/BackgroundNotification.java`.
That file adds the host app's `drawable/ic_brand_notification` as the large icon
of the persistent location notification. The existing small-icon options,
channel, service lifecycle and location behavior are preserved. The upstream
license is included in the package. `pubspec.yaml` uses this source through a
local dependency override.
