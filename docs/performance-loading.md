# Rider responsiveness and loading

The splash/olive work was verified and a separate release saved before these
changes. See `olive-theme-validation.md`.

## Changes

- Home sheet controls follow each frame, while native map padding is committed
  120 ms after the last sheet movement. This avoids rebuilding the map and
  sending new configuration during every drag frame. Route framing still runs
  after the panel settles; explicit recenter remains available.
- The sheet transition takes 260 ms and respects reduced motion. Removed the
  unconditional 1.1 second pause before fare review. Network-dependent booking
  validation remains in place.
- Cached images decode to their displayed pixel dimensions (capped at 2048 per
  dimension), with aspect-preserving resizing. The image cache resolves its
  directory once and coalesces background cleanup rather than delaying each
  image with a full directory scan.
- A 401 response to a guest request no longer clears a nonexistent session or
  navigates home. Authenticated expiration still clears the session normally.
- `skeletonizer` supplies a single shimmer per loading region for service types,
  vehicles, trip history, offers, wallet and notifications. Placeholders cannot
  receive taps and expose only a loading label to assistive technology. Reduced
  motion uses a static skeleton with no ticker. Existing content stays visible
  during list refreshes. Submission, connection and route progress indicators
  retain their explicit operation semantics.
- Notification loading starts alongside realtime connection and has a visible
  loading/error/retry state instead of briefly reporting an empty inbox.

## Evidence

The same deterministic home-sheet test drove 30 frames before and after:

| Map widget rebuilds | Before | After |
| --- | ---: | ---: |
| During the 30 moving frames | 30 | 0 |
| Including the final settled update | 30 | 1 |

This is a count of map widget rebuilds in a controlled widget test, not an FPS
measurement. The test now enforces the final budget unconditionally.

A separate x86_64 **profile** build was installed on MEmu. After excluding the
first 12 seconds of startup, a 30 second window included repeated sheet
expansion/collapse. Flutter delivered 268 frame timings:

| Duration | Median | 90th percentile | 99th percentile | Above 16.67 ms |
| --- | ---: | ---: | ---: | ---: |
| Flutter build | 0.767 ms | 1.487 ms | 4.886 ms | 0 / 268 |
| Flutter raster | 7.440 ms | 13.015 ms | 24.632 ms | 14 / 268 |

These are Flutter frame timings on this emulator. Native Google Maps rendering,
host load, GPU/driver behavior and physical phones can differ. No pre-change
device FPS baseline was captured, so these numbers do not establish a percentage
FPS improvement or guarantee uninterrupted 60 FPS.

`tool/performance_probe.dart` is a diagnostic entry point, excluded from normal
release startup. The final release uses `lib/main.dart`. Timing output and build
logs are saved in E:/Driver/work.

## Verification

- Final full suite: **120 tests passed**. Static analysis has no errors; the five
  existing warnings in offers/profile/wallet repositories remain, along with
  style information. `git diff --check` passed.
- Final x86_64 release built, installed on MEmu and launched successfully. The
  olive/light choice survived restart. Settings remained open through a 15 second
  check with no unexpected navigation. Screenshot: `previews/final-memu-settings.png`.
- APK: `E:/Driver/work/releases/yemen-drive-rider-smooth-olive-memu-x64.apk`.
  SHA256: `8CD79CFCD6A45558C57C07BE1FC2CE07D031AA7A2A7024F7DDAF561307A2A6CD`.
- Existing booking, routes, offers, payments, waiting, splash and connection tests.
- Guest 401 regression tests, including authenticated expiration followed by
  guest requests without repeated navigation.
- A real image decoding test verifies a large cached asset decodes within the
  120 x 120 pixel budget for a 60 x 60 logical thumbnail at 2x density.
- Skeleton tests cover accessibility, ignored taps, ready-state interaction,
  ticker disposal, reduced motion, short screens and olive light/dark previews.
- Preview images: `previews/loading-light.png` and `previews/loading-dark.png`.

The source retains the existing renderer choice used for MEmu compatibility.
Changing the renderer globally should be evaluated on representative physical
devices separately.
