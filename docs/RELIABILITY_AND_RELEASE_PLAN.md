# Seamly: Full App Reliability and Release Plan

**Revision 3 — October 30, 2026**

**Reviewed source:** main at 06129667, app version 1.9.4+22. Fixes in progress on branch `fix/reliability-quick-wins`.
**Review status:** every source finding in section 3.1 was re-checked against the code. Selected findings were reproduced on a Redmi 14C running the installed 1.9.4 (22) APK and against the deployed API (`seamly-api.onrender.com`). Section 0 records what is fixed so far and how it was verified.
**Scope:** all existing user journeys in the Android APK, with regression coverage for the published web app. Native iOS distribution is a separate delivery requirement, not established by the presence of an ios folder.

## 0. Fix first and current status

The full plan below is a release programme, not a single sprint. Work these small, high-value fixes first; each has a regression test that fails on the old code and passes on the fix.

| ID | Fix | Status | Evidence |
| --- | --- | --- | --- |
| A1 | Native Google sign-in now exchanges the token with the API exactly once and always releases the loading state. Google sign-in is injectable for tests. | Fixed, regression passed | test/auth_screen_test.dart (2 tests; both fail on the old flow) |
| D3 | Measurement maps are decoded with `measurementsFromJson`, which skips null optional fields, for the account profile, the local store and scan results. | Fixed, regression passed | test/session_store_test.dart, test/camera_capture_test.dart. Old code threw `type 'Null' is not a subtype of type 'num'`. |
| C2 | Retake no longer resets the failure count, so fail → retake → fail shows the help tip. | Fixed, regression passed | test/camera_capture_test.dart: "fail, retake, fail shows the gallery help tip" |
| N1 | Changing category clears the old stories/sources while loading; a failed refresh keeps that category's last good stories; only a successful load marks the tab loaded, so a failed first load retries on the next visit. | Fixed, regression passed | test/widget_test.dart (2 tests; both fail on the old code) |
| N2 | Source status distinguishes failed sources from healthy sources with no matching stories. Publisher feeds report failure only when no feed could be read. | Fixed, regression passed; needs backend deploy | backend/tests/test_api.py (2 tests; both fail on the old code) |
| C3 | Low-coverage preview text changed to "Move closer…". | Fixed (low impact, see C3 below) | backend/tests/test_api.py: distant person guidance test |

Baseline before fixes: `flutter analyze` clean, 45 Flutter tests and 75 backend tests passing. After fixes: analyze clean, 53 Flutter and 78 backend tests passing.

**Next in order:** D1 (save manual measurements; remove sample defaults), D2 (never keep an old size with new measurements; always save locally), A3 (record confirmed height), N4 (real Share; honest Like/Comment), C4 (shutter countdown), then R1 release signing before any wider distribution.

## 1. What “completely working” means

Every advertised feature must complete its intended action, preserve the correct user's data, and recover predictably from errors. A spinner, placeholder message, or successful HTTP response alone does not prove that a feature works.

The release goal is **all required journeys verified end to end and all known functional defects fixed**, with no unresolved crash, account-isolation problem, data loss, or misleading result in the shipped scope. Testing cannot prove the absence of every possible future bug. Completion must be supported by recorded results from the actual release APK and deployed API, followed by monitoring and a rollback path.

This revision replaces the earlier camera/news-only plan. It adds account access, measurement persistence, shared personalization, external-service configuration, and APK delivery. It also corrects three weaknesses in the earlier plan:

- News already has an eight-second HTTP operation timeout and an eight-request enrichment semaphore. The problem is the lack of a total response deadline, caching, and a response-size limit before buffering publisher pages; the individual requests are not wholly unbounded.
- Existing features should not be removed simply to pass the checklist. Visible actions must acquire real behavior. A changed product requirement must be explicit.
- A version bump, release-note statement, APK filename, or filesystem timestamp does not establish what is inside a published APK. Inspect its manifest, signing certificate, build provenance, and download asset.

## 2. Full feature acceptance matrix

All rows start **not yet verified for release**. Each needs normal use, invalid input, service failure, interruption, relaunch, and relevant account-isolation checks.

| Feature | Required working journey |
| --- | --- |
| Email account and onboarding | Register, reject duplicates/invalid input, sign in, complete welcome once, and collect the user's real height before calibrated scanning. |
| Google sign-in | Finish native and web sign-in, exchange the identity token with the backend, link the correct account, recover from cancellation, and never leave the button loading indefinitely. |
| Password recovery | Request recovery, receive a working reset link, change the password, reject expired/reused tokens, then sign in with the new password. A “coming soon” message fails this requirement. |
| Session and account management | Restore a valid session; distinguish temporary network failure from expiry; reauthenticate on 401; save name/height/picture; remove a picture; log out locally even when storage/network operations fail; prevent one account seeing another's private data. |
| Body camera and gallery | Confirm height/consent, open camera, switch lens, use a countdown when scanning alone, capture once, choose/cancel a photo, receive accurate quality guidance, retry, view results, and leave/resume safely. |
| Measurements and size | Enter/correct real values, receive a size for those values, save both together, restore them after login/relaunch, and propagate the same current profile to Home, Shop, and outfit planning. |
| Photo color and accessories | Analyze a suitable photo, handle inadequate lighting/subject detection, show results and limits, retry independently, and preserve accepted personalization. Failed color analysis must not erase a successful body result. |
| Manual color analysis | Select skin/hair/eye colors, show the corresponding palette, update all consumers consistently, and restore the accepted season for the account. |
| Home weather | Resolve the selected city correctly, remember the choice, show current/next-day local dates and timestamps, handle ambiguity and provider failure, and avoid showing an old city's outfit as the new city's result. |
| Event and seasonal styling | Use the selected event/date/time/style/location and current profile; distinguish forecast from climate averages; reject invalid dates; handle changed inputs and retries without publishing stale results. |
| Shop | Filter/search real approved listings, preserve correct images/prices/seller links, rank using current fit data, and open marketplace searches when that is the advertised mode. An unconnected product feed is an integration dependency, not a functioning live catalog. |
| News | Load relevant stories, change categories, search the advertised scope, refresh, retain correctly labeled cached stories on outages, render real or absent images, open original articles, and provide functional Like/Comment/Share actions. |
| Navigation and layout | All visible controls work on small screens, large text, portrait/landscape and Android Back; no inaccessible buttons, repeated submissions, keyboard obstruction, or stuck loading state. |

## 3. Evidence and defect register

“Source-confirmed” means the code path or missing functionality is directly visible. It does not mean a physical-device reproduction has been completed. P1 blocks a core journey or produces wrong/lost user state; P2 is a functional defect that also needs correction before the completeness claim.

### 3.1 Source-confirmed defects and gaps

| ID | Priority | Evidence and consequence | Primary files |
| --- | --- | --- | --- |
| A1 | P1 | The native Google flow sets _googleLoading=true, then calls _handleGoogleIdToken, which immediately returns when that flag is true. After a successful Google authentication, the backend exchange is skipped and loading can remain set. | lib/features/auth_screen.dart: _signInWithGoogleMobile, _handleGoogleIdToken |
| A2 | P1 | _forgotPassword only shows “Password recovery is coming…”; no recovery flow exists in the inspected API routes. | lib/features/auth_screen.dart, backend/app/main.py |
| A3 | P1 | Email registration and new Google accounts assign 165 cm. Camera calibration accepts any height in range, without recording that the user confirmed it. This can scale scans to an invented height. | lib/features/auth_screen.dart, backend/app/account_store.py, lib/features/camera_measurement_screen.dart |
| D1 | P1 | Manual measurements return only a size string to the shell. The edited values are not passed into shared measurements or saved through the account flow. The manual form also prepopulates sample measurements. | lib/features/measurements_screen.dart: _defaults, _submit; lib/app.dart: MeasurementsScreen wiring |
| D2 | P1 | If size recommendation fails, _saveScanMeasurements retains the previous size while accepting new measurements. A failed cloud save also skips the subsequent local save, and failure is silently swallowed. | lib/app.dart: _saveScanMeasurements |
| D3 | P1 | Optional measurement fields can be null in the backend schema, but AccountSession.fromApi casts every value to num. A valid profile containing null optional fields can fail Dart decoding. **Verified:** the API returns `"neck": null` for a profile saved with only required fields, and the cast throws a `TypeError`, which is an `Error`, not an `Exception`, so `on Exception` handlers (for example `_refreshAccountProfile`) do not catch it. | backend/app/schemas.py: Measurements; lib/services/session_store.dart: AccountSession.fromApi |
| D4 | P1 | Once chest/waist/hip pass the camera gate, the callback forwards the entire measurement map, including fields excluded from display by the scan result. Confidence/provenance is lost on the path to the saved/manual profile. | lib/features/camera_measurement_screen.dart: _usePhoto; lib/app.dart: _saveScanMeasurements |
| A4 | P1 | Profile refresh swallows all Exceptions, including session expiry; ApiException loses the HTTP status. HTTP helpers decode JSON outside their transport catch. A non-JSON response can escape screens that catch only ApiException, leaving incomplete recovery. | lib/app.dart: _refreshAccountProfile; lib/services/seamly_api.dart; lib/features/auth_screen.dart |
| C1 | P2 | The detected body rectangle scales directly to canvas width/height, while the native preview uses BoxFit.cover. The rectangle does not apply the preview crop/offset or lens mirroring transform. | lib/features/camera_capture_view.dart: _CoverPreview, _BodyOutlinePainter |
| C2 | P2 | _retake resets _consecutiveScanFailures, so the normal fail → retake → fail flow does not reach the two-failure help threshold. Existing tests inject the visible flag rather than exercising that sequence. | lib/features/camera_measurement_screen.dart: _retake; test/camera_capture_test.dart |
| C3 | P3 | When detected height coverage is below 0.42, readiness tells the user to “Step back,” which makes a distant subject smaller. **Verified as low impact:** the lenient shape check already rejects coverage below 0.42 with “Move closer…”, so this text is effectively unreachable. Corrected anyway. | backend/app/body_scan.py: preview |
| C4 | P2 | Preparation text tells the user to prop the phone and use a timer; the inspected camera controls have no shutter countdown. **Reproduced on device:** the live camera shows only Gallery, Shutter and Switch camera. | lib/features/camera_measurement_screen.dart: preparation steps; lib/features/camera_capture_view.dart |
| C5 | P2 | Preview errors retain the previous readiness state. There is no age limit on a green signal after communication failure. Also, preview analyzes the original photo while native final analysis uses the segmented photo. | lib/features/camera_measurement_screen.dart: _samplePreview, _usePhoto |
| D5 | P2 | Accepted color season is held only in _colorSeason in the shell; it is absent from account/session persistence and resets on recreation. | lib/app.dart; lib/services/session_store.dart |
| N1 | P2 | Selecting a new category retains old-category posts while loading; an API error then removes all posts. _hasLoaded is set before success, preventing automatic retry on later tab activation. | lib/features/fashion_news_screen.dart: _loadFeed, _selectCategory, didUpdateWidget |
| N2 | P2 | Source “connected” is bool(items), so a healthy source with no category matches is mislabeled unavailable. Exceptions, no results, and missing configuration are conflated. **Reproduced on device:** “Fashion publishers” is green under All and grey under Gothic; the API reports it “temporarily unavailable”. | backend/app/news_feed.py: fetch |
| N3 | P2 | Merge interleaves sources without globally sorting dates and deduplicates only normalized titles. Bad/missing dates become “now.” IDs are derived before URL resolution, so source aliases do not reliably share a story identity. | backend/app/news_feed.py: _merge, _post, date parsing, enrichment |
| N4 | P2 | Like is an in-memory toggle; Comment and Share only display snackbars. Publisher/Reddit counts and the local like increment are shown together despite representing different actions. **Reproduced on device:** Comment shows “Comments are available on the original story.” and Share shows “Open the story to share it from the original source.” | lib/features/fashion_news_screen.dart: card callbacks |
| R1 | P1 release gap | The checked-in Android release build uses the debug signing configuration. The API defaults to localhost unless build configuration overrides it. No tracked GitHub Actions or integration_test directory was found. These facts do not establish how an existing release asset was built. **Verified on device:** the installed 1.9.4 (22) APK is signed with `CN=Android Debug` (SHA-256 a8e90fc5…dba4) and calls `https://seamly-api.onrender.com`. | android/app/build.gradle.kts; lib/services/seamly_api.dart; tracked repository tree |

### 3.2 Risks requiring targeted reproduction or verification

| ID | Risk supported by the code | Required evidence |
| --- | --- | --- |
| C6 | Both readiness sampling and shutter invoke takePicture without a shared operation lock. Controller switching uses a different generation from preview result checks. Stopping the timer clears _previewInFlight while work may still be pending. | A controlled camera fake that rejects overlap; then shutter/switch/background stress on actual Android hardware. |
| C7 | Full-resolution decode, mask compositing, and JPEG encoding run synchronously in the segmentation service. EXIF orientation and mask coordinates are not explicitly normalized together, and mask validity uses only a minimum foreground fraction. | Rotated JPEGs, large gallery images, partial/incorrect masks, frame-time and memory recordings on lower-memory phones; compare native and web behavior. |
| N5 | Source retrieval and article enrichment share one response path. Page contents are buffered before slicing text to 750,000 characters. A slow source, large page, or multiple batches can delay all headlines. | Controlled slow/large/malformed upstream responses; measure the entire endpoint deadline and resource usage. |
| N6 | External feed article URLs are fetched with automatic redirects and no explicit public-destination validation. A scheme check on image strings does not protect server-side article requests. | Safe mock tests for private/loopback/link-local addresses, DNS changes and redirect chains; verify actual outbound requests only use approved public destinations. |
| I2 | The deployed API runs on Render's free plan. Measured on 2026-10-30: the first request after idle took 63 s; warm `/v1/news/feed?category=all` took about 10 s on three consecutive calls, so nothing is cached and the 8 s target in section 5 is missed. | Choose hosting that meets the cold-start target or show a clear waking-up state; add feed caching (Stage 3) and re-measure. |
| I1 | Production DB durability, mail delivery, Google OAuth IDs/certificate registration, product feeds, image-service credentials, CORS, hosting capacity and the published APK's version/signature are unverified in this review. | Read actual deployment settings without exposing secrets, exercise integrations in staging, and inspect the release artifact. A config key or mocked test is insufficient. |

## 4. Implementation order and acceptance gates

### Stage 0 — Establish the baseline and release contract

- Record the exact source SHA, app/backend versions, resolved Flutter/Dart/Android toolchain and supported OS versions. Identify the APK users currently install by manifest and signing certificate, not its filename.
- Create a tracked issue entry for every item above: trigger, expected/actual behavior, evidence, fix, regression check, and status. Reproduce runtime risks before assuming a particular cause.
- Run the existing Flutter and backend suites and analysis to record the baseline. Keep their passing results separate from device and live-service evidence; many current tests use fakes or synthetic silhouettes.
- Set up a staging API and test accounts with isolated data. Inventory required external integrations and configuration. Missing credentials, devices or measurement reference data remain explicit open dependencies.
- Use the feature matrix as the agreed scope. All visible controls stay on the acceptance list until functional; do not mark a feature done by hiding it.

**Exit:** reproducible baseline, full journey inventory, named dependencies, and a traceable APK/source relationship or an explicitly unresolved artifact gap.

### Stage 1 — Repair account access and shared user data

Addresses A1–A4 and D1–D5 before declaring camera-to-shop workflows complete.

- Give the Google login flow one loading owner and a finally path. Perform exactly one backend exchange per accepted Google identity; cancellation and all error types must unlock the UI.
- Implement real password recovery with a verified sending service, expiring single-use hashed reset tokens, rate limiting, neutral account-existence responses, password update and session revocation. Prove mail/deep-link delivery with a designated test account.
- Record whether the account holder confirmed their height. Do not treat 165 cm as confirmed merely because it is in range. Migrate existing records without guessing which 165 cm entries were intentional; prompt for confirmation before their next calibrated scan.
- Introduce a shared typed fit profile containing actual measurements, origin (manual or estimated), per-field confidence/acceptance, height version and size calculation status. Remove silently accepted sample defaults.
- Route manual corrections and scan acceptance through the same persistence path. Keep pending/local/cloud-saved states visible. Store accepted data locally even if cloud sync fails; retry safely. Never attach an old size to new measurements after a failed recalculation.
- Preserve optional null measurements correctly. Only display and use accepted fields; a heuristic confidence score is not evidence of validated measurement accuracy.
- Carry account identity and profile revision through asynchronous saves, refreshes and recommendation responses. Prevent late operations restoring stale data after height changes, logout or account switching.
- Preserve HTTP status and stable error codes in the API client. Normalize invalid JSON, wrong response shape, timeout, 401, 409, 422, 429 and 5xx into recoverable UI states. Retry only appropriate/idempotent operations.
- Handle expired sessions distinctly from offline mode. Clear local access promptly on logout, including storage failure paths. Persist color personalization consistently and scope private caches to the correct account.

**Exit:** register/login/recovery/logout work; accepted manual and scanned data survive relaunch and re-login; all consuming screens agree; delayed responses cannot corrupt another account or newer profile.

### Stage 2 — Repair camera capture and measurement behavior

Addresses C1–C7 and preserves the data rules from Stage 1.

- Start with small regression-backed fixes: a shared native camera-operation lock, capture priority over preview sampling, and generation checks covering session, controller, scan and relevant account/profile revision.
- Stopping a timer is not cancellation. Keep track of the actual pending operation, await safe controller disposal, and discard old results. Do not dispose an active native capture or reset its in-flight flag prematurely.
- Define explicit camera states and transitions: preparation, permission, initializing, live, countdown, capturing, analyzing, results, recoverable error and suspended. Controls must allow only valid actions in each state.
- Prefer local readiness checks where supported, after validating full-body support on the selected model/platform. If sampled stills remain necessary, bound their resolution/frequency, serialize them with the shutter and remove temporary files after use. Any preview upload needs clear consent describing that behavior.
- Add a cancelable countdown for solo capture, correct the distance instruction, preserve failure counts across retakes, expire stale green readiness, and provide specific permission/device/network recovery actions.
- Use one documented transformation from source image coordinates to the displayed crop, including EXIF rotation, aspect ratio, crop offset and front-camera mirroring. Display the accepted photo without hiding framing evidence.
- Move expensive image work off the UI thread where the platform supports it, cap image size before encoding/upload, and validate segmentation masks for orientation, coverage and missing body parts. An unusable mask must safely fall back or request a new capture.
- Share preprocessing and quality rules where possible. Test preview/final agreement on the same pixels and processing mode; a different pose or exposure in a later photo cannot be guaranteed to pass.
- Give body and color analysis independent outcomes/retry paths. Preserve a successful body result when color analysis fails; provide bounded progress and cancellation, and never save a rejected scan.
- Handle denied/permanently denied permission, camera unavailable, app background/resume, gallery cancellation, process interruption and recovered picker data.

**Accuracy gate:** the current geometry uses fixed ratios and cannot be made a validated sizing model by fixing UI bugs. Establish intended sizing tolerances before evaluation; benchmark against consented tape measurements with a held-out sample, per-measurement error, false accepts/rejects and cohort coverage. If it fails, revise the measurement method or capture requirements. Do not loosen quality gates merely to increase successful scans.

**Exit:** one shutter action produces one capture; repeated transitions produce no collisions/stale updates; guidance is consistent; real-device performance is acceptable; accepted estimates meet the agreed intended-use benchmark.

### Stage 3 — Make news retrieval reliable and safe

Addresses N2, N3, N5 and N6.

- Separate source adapters from normalization, story identity, ranking, caching and optional image enrichment. Preserve partial success instead of collapsing source errors to an empty list.
- Apply a total request deadline, per-source deadlines and bounded response sizes. Headline delivery must not depend on fetching every publisher page. Cache metadata or enrich it through supervised background work.
- Validate schemes and public destinations before every server-side connection and redirect. Include IPv4/IPv6, DNS rebinding and redirect checks; a hostname check followed by an unrelated DNS lookup is insufficient. Never forward credentials across hosts.
- Parse each record independently; one malformed article should not discard all records from a source. Distinguish ok, empty, unavailable, rate-limited and not-configured source states.
- Create stable story identity from verified canonical URLs with known tracking parameters removed. Preserve case-sensitive paths and functional query parameters. Deduplicate across sources and category loads before sorting by genuine publication time and stable ID.
- Treat missing publication time as unknown. Do not label a retrieval/first-seen timestamp as publication time or invent “Just now.”
- Cache feed results by category/query with original timestamps and a defined stale lifetime. Prevent simultaneous requests from repeatedly fetching the same upstream data. Add pagination using a stable snapshot/cursor if it is included in the feed contract.
- Resolve Google/publisher links only through supported accessible responses. If the actual story image cannot be established, show a compact no-image card; do not substitute aggregator logos or unrelated photography.
- Keep image loading optional, resource bounded and independently recoverable. Distinguish “no image supplied” from a broken image URL.

**Exit:** one unavailable provider does not empty a healthy partial feed; headline responses meet the total deadline; bad records and image failures are isolated; identities/dates/order are stable; outbound URL safety cases pass.

### Stage 4 — Complete news actions and all remaining journeys

- Key news loading and cached state by category/query. Clear or label the previous category while loading. Retain the correct last-good feed on refresh failure, revalidate it when appropriate on tab return, and expose separate empty/offline/error states.
- Define search honestly. If it searches only fetched stories, label that scope; if it promises full feed search, implement server search and pagination rather than silently searching the first 16 items.
- Make Share open the OS/browser share flow with a working copy-link fallback.
- Implement Like as a persistent per-account Seamly action with a stable story ID and idempotent updates. Do not mix it into Reddit/publisher counts.
- If the existing generic Comment feature remains, provide a real Seamly comment flow (list, submit, delete own comment, validation, authorization and abuse controls) tied to the same stable story ID. Sending a snackbar does not pass. Changing it to an explicitly labeled external publisher-discussion link is a product-scope decision, not an automatic shortcut.
- Verify weather city resolution, date boundaries/timezones, forecast versus climate-average labels, event/style input changes during requests, retries, image-service failures and shared-profile updates.
- Verify Shop filters, exact listing/image association, fit state, empty categories and outbound links against an actual approved feed. Test marketplace-search fallback separately. External discovery links are not proof of an embedded Facebook/Instagram feed.
- Verify color/accessory workflows and every account/profile/navigation control. Replace any remaining “coming soon,” empty callbacks or demo outcomes in required journeys with complete behavior.

**Exit:** every feature matrix row has a complete implementation and an associated regression scenario; unresolved integration dependencies are not marked complete.

### Stage 5 — Prove the release and deliver the correct APK

- Extend meaningful regression coverage for the exact failures above. Add app-to-API integration journeys using staging, a fresh account and a returning account; unit/widget mocks remain useful but do not substitute for these checks.
- Add CI for backend tests, Flutter analysis/tests and release-build validation, using pinned/resolved dependencies and a recorded toolchain. Include PostgreSQL contract/migration checks as well as local SQLite tests.
- Test physical Android devices representing the minimum supported environment, a lower-memory phone and a common current phone. Check web camera/gallery behavior separately. Record device/OS/app version and results.
- Verify durable hosted account storage, migrations, backups/restore, service capacity/cold-start behavior, production HTTPS/CORS, Google OAuth client IDs and signing fingerprints, required feeds and email delivery.
- Configure an owned release signing key and protected storage. Inspect the previously distributed certificate before changing keys: switching from a debug certificate can break in-place upgrades. Do not resolve a signature mismatch by telling users to uninstall and lose data without a documented migration.
- Make production API URL and required auth configuration explicit build inputs; fail a production build that points to localhost or lacks required configuration.
- Build from the tested commit, install the exact signed candidate, and exercise fresh install plus upgrade from the prior supported APK without losing user data. Record versionName, versionCode, commit SHA, certificate fingerprint and SHA-256 checksum.
- Deploy backward-compatible API changes before a new APK that requires them. Keep older supported clients working during the rollout and test database rollback/forward compatibility.
- Publish the tested artifact and clear release notes, then verify the actual download and service health. Add privacy-safe crash/error monitoring, a staged rollout, and a rollback procedure; an old APK versionCode cannot simply be installed over a newer one.

**Exit:** all acceptance evidence is attached to the exact downloadable APK and deployed backend, with no known functional defect left in the required journeys.

## 5. Verification scenarios and measurable targets

These are proposed acceptance targets, not measurements already achieved.

| Area | Minimum evidence required |
| --- | --- |
| Account/data | New and existing email/Google accounts, cancel/retry, expired token, reset-token reuse/expiry, two-account switching, offline saves, storage failure, null optional fields, concurrent height edits and late responses. No false “saved” state, cross-account data or stale size. |
| Camera lifecycle | At least 100 controlled transition sequences in automation, plus 20 capture/retake/switch cycles on each selected physical device. Zero overlapping captures, unhandled exceptions, stuck controllers or stale-result application. |
| Image correctness | Rotation/EXIF variants, front/back lenses, cover-crop coordinate cases, huge/corrupt files, invalid masks, gallery cancellation and permission changes. Original and segmented images stay aligned; rejected images never update fit. |
| Scan usefulness | Predetermined measurement tolerances evaluated on independent consented reference data; report both rejection rate and error among accepted scans. Synthetic silhouettes alone do not satisfy this gate. |
| News reliability | Every category, rapid category changes, empty matches, one/all sources down, 429, slow/oversized/malformed pages, duplicate aliases, absent/future dates, broken images and malicious redirects. Last-good results remain correctly labeled. |
| News performance | On the declared staging network with a warm backend: cached feed p95 at most 1 second, uncached headlines p95 at most 5 seconds, and a total feed deadline of 8 seconds. Image work cannot extend that deadline. Record cold-start results separately and correct hosting if they fail the supported experience. |
| UI/performance | Visible feedback within 200 ms of tapping an action on supported devices; bounded waits with cancellation/retry; long camera/feed sessions show no continuing growth from abandoned controllers, images or timers. Define body/color latency limits from the Stage 0 baseline before declaring that flow complete. |
| Complete app | Fresh install → register → confirm height → scan/manual correction → save → Shop/Home/outfit personalization → News interactions → relaunch → profile edit → logout/login. Repeat on an upgraded APK and with staged network failures. |
| Release operations | Install and upgrade evidence, manifest/certificate/checksum, production endpoint, database persistence across restart/deploy, safe schema migration, downloadable asset verification and rollback rehearsal. |

## 6. Existing coverage and gaps to address

Extend the existing camera, segmentation, account, event and widget tests in test/, plus backend/tests/. Current camera tests provide useful layout/lifecycle checks and backend tests use deterministic fixtures. Segmentation tests mostly cover overrides/fallback; the news category API test replaces the collector with a fake. These do not demonstrate real camera behavior, real-provider parsing, Google native completion, password delivery, durable production storage, or a working release APK.

Add focused failing regressions before each fix, then run the affected checks. Run the full automated suite for the release candidate and repeat only the relevant checks after subsequent changes. Record pass/fail/blocked with evidence; “not tested” must never be presented as passing.

## 7. External dependencies and completion reporting

The implementation needs access to a testable Android device/APK, actual release-signing provenance, deployed API/database configuration, Google OAuth configuration, a password-reset delivery service, approved product-feed data where live products are required, and consented measurement reference data for scan validation. Optional Reddit/Pexels integrations should be declared explicitly in the supported feature contract and exercised when enabled. No credentials or private photos should be written into this document.

Use these status stages for each issue: source finding → reproduced or confirmed missing behavior → fixed → regression passed → end-to-end/device verified → verified in release artifact. Plan completion is only completion of this document. It is not a claim that the application is already repaired or bug-free.
