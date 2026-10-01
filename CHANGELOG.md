# Seamly Changelog

Every user-facing change, newest first. Version = Flutter `pubspec.yaml`;
every entry below is on `main` and deployed via Render + GitHub releases.

## 1.9.4+22 (this release)

- **Body scan cleans your background first.** On phones, each photo runs
  through free on-device person segmentation (Google ML Kit, offline —
  nothing leaves your phone) that swaps busy backgrounds for white before
  measuring. Web and older phones fall back to the original photo, so
  nothing can get worse.

## 1.9.3+21

- **Body scan passes first try.** The green "ready" preview now enforces
  the same strict gates as analysis (previously it was lenient, so green
  often failed on capture). Every rejection names the top fix ("move
  closer", "plain contrasting background", "stand centre"…).
- New "prop the phone" preparation step (selfies can't fit a full body)
  plus a back-camera/gallery tip that appears after 2 failed scans.

## 1.9.2+20

- **Outfit inspiration photos.** The event-outfit result shows a photo
  strip (Pexels, free) labeled "Photos for ideas — not actual products,"
  with photographer credits. Needs a free `PEXELS_API_KEY` on the server;
  without it the strip hides and the outfit works as before.
- **Far-future events show real climate averages.** Beyond the 16-day
  forecast, the planner uses 10-year ERA5 averages for that exact date
  (e.g. Manila Nov 18: 30.8°, sometimes rainy) instead of dashes —
  still labeled as averages, never a forecast.

## 1.9.1+19

- **Weather resilience.** Server retries 3× with backoff on rate-limits
  and timeouts, falls back to wttr.in for near dates; the app auto-retries
  once after 5 seconds on brief outages.

## 1.9.0+18

- **Event outfit planner (Home).** 21 event shortcuts + free text,
  date/time pickers, 4 style chips + type-your-own, `POST /v1/outfits/plan`
  combining forecast + style engine + scan size, with reasons and palette.
- **Camera framing guide.** Full-body target frame, green "Good to go"
  banner, glowing shutter when the AI preview says ready.
- **Google Sign-In** with same-email account linking (`POST /v1/auth/google`).
- High-school-friendly technical overview + event plan docs.

## 1.8.2+17 and earlier

- See GitHub releases for 1.8.2 and below (city-aware weather, camera
  readiness preview, Seamly rebrand).
