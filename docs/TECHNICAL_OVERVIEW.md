# Seamly — Technical Overview & Developer Change Guide

> **Purpose of this doc:** one place for the whole application structure,
> every API used, the runtime flows, and — most importantly — **where to
> change what** when another developer picks this up.
> Codebase version covered: `1.8.2+17` (`pubspec.yaml`), API `1.7.0`
> (`backend/app/main.py`). Branch `main`, repo `Stylorista/Stylorista-AI`.

---

## 1. What this app is (30 seconds)

Seamly is a privacy-conscious fashion MVP:

- **Flutter** UI (mobile + web) for accounts, body-scan, color/style advice,
  weather outfits, shop, news, profile hub.
- **FastAPI** backend for auth, deterministic fit/color/style engines,
  weather, news, shop-feed gating.
- No biometric ML model, no checkout, no scraped social feeds. The scanner is
  deterministic image geometry with strict framing checks (prototype only).

---

## 2. Tech stack

| Layer | Tech | Key packages |
|---|---|---|
| UI | Flutter 3.44 / Dart 3.12, Material 3 | `camera`, `image_picker`, `http`, `shared_preferences`, `url_launcher`, `google_sign_in ^7.2.0` + `google_sign_in_web` |
| API | FastAPI + Uvicorn, Pydantic v2 | `fastapi`, `uvicorn[standard]`, `pydantic`, `httpx`, `pillow`, `numpy`, `scikit-learn`, `psycopg[binary]`, `google-auth[requests]` |
| DB | SQLite locally, PostgreSQL in prod | `sqlite3` stdlib, `psycopg` |
| Hosting | Firebase Hosting (web `dist/`), Render (API) | `firebase.json` → `dist/`, `render.yaml` → `backend/` |
| External data | Open-Meteo, wttr.in fallback, RSS/GDELT/Google News, optional Reddit + operator shop feed | `httpx` server-side only |

---

## 3. Repository structure

```text
lib/
  main.dart                  # runApp(SeamlyApp)
  app.dart                   # AuthGate + SeamlyShell + nav (see §5)
  theme/seamly_theme.dart    # colors + Material theme
  services/
    seamly_api.dart          # ALL backend calls (single HTTP client)
    session_store.dart       # SharedPreferences session cache
    google_sign_in_service.dart  # GIS init + mobile authenticate()
  features/                  # one file per screen (see §6)
    auth_screen.dart         # sign-in / register + Google card
    welcome_screen.dart      # one-time onboarding
    home_screen.dart         # dashboard + weather
    shop_screen.dart         # listings + fallback searches
    camera_measurement_screen.dart  # scan flow (logic)
    camera_capture_view.dart # scan viewfinder (dumb UI)
    fashion_news_screen.dart
    profile_screen.dart      # style hub + selfie accessories
    measurements_screen.dart # manual tape form → size
    color_analysis_screen.dart
    season_style_screen.dart
    account_screen.dart      # name/height/avatar + logout
  widgets/
    common.dart, seamly_header.dart, account_avatar.dart
    google_web_button.dart (+ _web.dart GIS button, + _stub.dart mobile no-op)

backend/
  app/
    main.py              # FastAPI app + ALL routes (see §7)
    schemas.py           # Pydantic contracts for every endpoint
    account_store.py     # SQLite + Postgres accounts/sessions/measurements
    google_auth.py       # Google ID-token verification
    ai_engine.py         # size / color / style deterministic models
    body_scan.py         # silhouette geometry estimator
    appearance_analysis.py  # selfie color-direction
    weather_service.py   # Open-Meteo + wttr.in + fashion tips
    news_feed.py         # publisher RSS + GDELT + Google News + Reddit
    shop_catalog.py      # approved-feed gating + domain allow-list
    avatar.py            # account-picture sanitize (512px JPEG, strip EXIF)
  tests/
    test_api.py, test_account_settings.py, test_google_auth.py, ...
  requirements.txt
  .env.example           # GOOGLE_CLIENT_IDS, shop feed vars
  Dockerfile, railway.json, fly.toml, oracle_setup.sh

web/index.html           # meta google-signin-client_id + manifest
firebase.json / .firebaserc  # hosting public=dist, project seamly-web
render.yaml              # Render python service, DATABASE_URL + GOOGLE_CLIENT_IDS
build_web.ps1            # flutter build web → dist/ with dart-defines
assets/images/           # home_hero.png, seamly_logo.png, partner_collage.png
test/                    # widget_test.dart, account_settings_test.dart, camera_capture_test.dart
docs/                    # PRODUCT_PLAN.md, AUDIT.md, SHOP_SOURCES.md + this file
```

---

## 4. Backend API — full endpoint map

Base URL is `API_BASE_URL` (Flutter dart-define, default
`http://127.0.0.1:8000`). All JSON. Auth endpoints that need a session use
`Authorization: Bearer <token>`.

| Method | Path | Request | Response | Code file |
|---|---|---|---|---|
| GET | `/health` | — | `{status, service, version}` | `backend/app/main.py` |
| POST | `/v1/auth/register` | `AccountRegisterRequest{name,email,password,height_cm,phone?,location?}` | `AccountAuthResponse{token,is_new_account,profile}` 201 | `main.py` + `account_store.py:register` |
| POST | `/v1/auth/login` | `AccountLoginRequest{email,password}` | `AccountAuthResponse` | `main.py` + `account_store.py:login` |
| POST | `/v1/auth/google` | `AccountGoogleLoginRequest{id_token}` | `AccountAuthResponse` (links by email) | `main.py` + `google_auth.py` + `account_store.py:login_with_google` |
| POST | `/v1/auth/logout` | Bearer token | `{signed_out:true}` | `main.py` + `account_store.py:logout` |
| GET | `/v1/account/profile` | Bearer | `AccountProfile` | `main.py` |
| PUT | `/v1/account/profile` | Bearer + `AccountProfileUpdateRequest{name,height_cm,avatar_base64?}` | `AccountProfile` | `main.py` + `avatar.py` |
| PUT | `/v1/account/measurements` | Bearer + `SavedMeasurementsRequest{measurements,size_label?,scan_confidence?}` | `AccountProfile` | `main.py` |
| POST | `/v1/size/recommend` | `SizeRequest{measurements,fit_preference}` | `SizeResponse{recommended_size,alternatives,fit_notes}` | `ai_engine.py` |
| POST | `/v1/color/analyze` | `ColorRequest{skin_hex,hair_hex,eye_hex}` | `ColorResponse{season,palette,neutrals,metals}` | `ai_engine.py` |
| POST | `/v1/style/recommend` | `StyleRequest{climate,hemisphere,month,occasion,style,color_season,size_label?}` | `StyleResponse` | `ai_engine.py` |
| POST | `/v1/body-scan/preview` | `BodyScanPreviewRequest{image_base64,consent_confirmed=true}` | `BodyScanPreviewResponse{ready,person_detected,guidance,bbox?}` | `body_scan.py` |
| POST | `/v1/body-scan/analyze` | `BodyScanRequest{image_base64,reference_height_cm,consent_confirmed=true}` | `BodyScanResponse{measurements,scan_confidence,…}` | `body_scan.py` |
| POST | `/v1/profile/analyze` | `AppearanceAnalysisRequest{image_base64,consent_confirmed=true}` | `AppearanceAnalysisResponse{color_season,accessories,…}` | `appearance_analysis.py` |
| GET | `/v1/news/feed?category&limit` | `category=all\|y2k\|gothic\|alternative\|formal\|casual\|wedding\|streetwear\|vintage`, `limit 4–30` | `FashionNewsResponse{items,sources}` | `news_feed.py` |
| GET | `/v1/shop/products?limit` | `limit 1–80` | `ShopProductsResponse{items,sources,catalog_mode}` | `shop_catalog.py` |
| GET | `/v1/weather/home?city&size_label?&color_season?` | `city` min 2 chars | `WeatherHomeResponse{location,current,tomorrow,fashion[]}` | `weather_service.py` |

Contracts live in `backend/app/schemas.py` (ranges e.g. height 120–230 cm,
consent must be `true`, avatar ≤3M chars base64).

---

## 5. Third-party / external APIs used

| API | Where called | Key / auth | Notes |
|---|---|---|---|
| Google Sign-In (GIS + `google-auth` verify) | Flutter `google_sign_in` → backend `google_auth.py:verify_google_id_token` | Web OAuth client ID (`GOOGLE_CLIENT_IDS` backend, `GOOGLE_WEB_CLIENT_ID` Flutter, `web/index.html` meta) | No Firebase Auth. Backend checks `aud` + `email_verified`. See §8 |
| Open-Meteo geocoding + forecast | `backend/app/weather_service.py` | No key | `geocoding-api.open-meteo.com/v1/search`, `api.open-meteo.com/v1/forecast`. 30-min cache, PH-biased |
| wttr.in fallback | `weather_service.py:_fetch_wttr_fallback` | No key | Used when Open-Meteo fails |
| Google News RSS | `news_feed.py:_fetch_google_news` | No key (public RSS) | `news.google.com/rss/search`. NOT a Cloud API |
| GDELT DOC 2.0 | `news_feed.py` | No key | `api.gdeltproject.org/api/v2/doc/doc` |
| Publisher RSS (Vogue, ELLE, Fashionista) | `news_feed.py` | No key | Hardcoded feed URLs at top of file |
| Reddit search (optional) | `news_feed.py` | `REDDIT_ACCESS_TOKEN` env (approved OAuth token) | Skipped cleanly when unset |
| Operator shop feed (optional) | `shop_catalog.py` | `FASHIONTECH_SHOP_CATALOG_URL` + `TOKEN`, or inline `FASHIONTECH_SHOP_CATALOG_JSON` | Strict Shopee/Lazada/Temu host allow-list; else `setup_required` fallback |
| Firebase Hosting | `firebase.json`, `.firebaserc` (project `seamly-web`) | Firebase CLI login | Serves `dist/` only |
| Render API host | `render.yaml` | `DATABASE_URL`, `GOOGLE_CLIENT_IDS` (sync:false) | `uvicorn app.main:app`, health `/health` |

No Google Maps, Vision, or Firebase Auth. No payment API.

---

## 6. Frontend flows

### 6.1 Boot → auth gate (`lib/app.dart`, `lib/main.dart`)

```text
main() → SeamlyApp → AuthGate
  1. _restoreSession() reads SharedPreferences (1s splash with logo)
  2. not authenticated → AuthScreen
  3. authenticated + first time → WelcomeScreen → NEXT
  4. else → SeamlyShell (tabs)
Background: _refreshAccountProfile(token) silently refreshes from GET /account/profile.
Logout: POST /auth/logout (best-effort) + clear prefs + GIS signOut (best-effort).
```

### 6.2 Auth (`lib/features/auth_screen.dart`)

- Email form (`_AuthCard`): sign-in vs register toggle, 8-char password rule,
  register hardcodes `heightCm: 165` (fixed later in Profile).
- Google card (`_GoogleCard` below the form):
  - Web: GIS `renderButton()` (`widgets/google_web_button_web.dart`) listens
    to `authenticationEvents` → `POST /v1/auth/google`.
  - Mobile/desktop: `Continue with Google` →
    `GoogleSignInService.signInWithGoogle()` (`authenticate()`) → same endpoint.
- Success: `AccountSession.fromApi(response)` → `AuthGate._authenticate` →
  caches in `PreferencesSessionStore` (`seamly.*` keys).

### 6.3 Navigation (`SeamlyShell` in `lib/app.dart`)

Indexed screens (bottom bar on mobile, rail on ≥900px):

| Tab | Screen index | File |
|---|---|---|
| Home | 0 | `home_screen.dart` |
| Shop | 1 | `shop_screen.dart` |
| Scan (center FAB) | 2 | `camera_measurement_screen.dart` |
| News | 3 | `fashion_news_screen.dart` |
| Profile hub | 4 | `profile_screen.dart` |
| (pushed) Measurements | 5 | `measurements_screen.dart` |
| (pushed) Color | 6 | `color_analysis_screen.dart` |
| (pushed) Style | 7 | `season_style_screen.dart` |
| (pushed) Account | — | `account_screen.dart` |

Shared state in shell: `_sizeLabel`, `_colorSeason`, `_scannedMeasurements`,
`referenceHeightCm`. Scan save → `recommendSize` → `saveAccountMeasurements` →
`sessionStore.saveMeasurementProfile`.

### 6.4 Feature flows (screen → endpoint)

- **Manual size:** `measurements_screen.dart` (11 tape fields + fit
  segmented) → `POST /v1/size/recommend`.
- **Color:** `color_analysis_screen.dart` (skin/hair/eye swatches) →
  `POST /v1/color/analyze` → season palette.
- **Style:** `season_style_screen.dart` (climate/hemisphere/occasion/style) →
  `POST /v1/style/recommend`.
- **Body scan:** `camera_measurement_screen.dart` (consent + height gate →
  live `camera` preview loop → capture via `camera` or `image_picker`) →
  `POST /v1/body-scan/preview` (guidance) then
  `POST /v1/body-scan/analyze` (+ `referenceHeightCm`) and parallel
  `POST /v1/profile/analyze` for palette. UI only in `camera_capture_view.dart`.
- **Weather:** `home_screen.dart` (city persisted as `seamly.city`) →
  `GET /v1/weather/home`.
- **Shop:** `shop_screen.dart` → `GET /v1/shop/products`; exact listings only
  when operator feed connected, else image-free Shopee/Lazada/Temu search
  ideas + `url_launcher` deep links.
- **News:** `fashion_news_screen.dart` → `GET /v1/news/feed`; likes are local
  stubs, share opens original URL.
- **Account:** `account_screen.dart` → `PUT /v1/account/profile`
  (avatar ≤2 MB JPEG/PNG/WebP, resized 512px, EXIF stripped in `avatar.py`).

---

## 7. Backend internals (where logic lives)

| Module | What it does | Tune here |
|---|---|---|
| `ai_engine.py` | `SeamlyEngine`: sklearn size model (`SIZE_CENTRES` + RandomForest demo), hex→season color rules + `PALETTES`, climate/month style templates | Size centres, palette hexes, style copy |
| `body_scan.py` | `BodyScanEstimator.preview/analyze`: decode → lighting check → foreground mask → largest component → person-shape gate → widths at heights → cm via `reference_height_cm` | Lighting thresholds, bbox gates, cm ratios |
| `appearance_analysis.py` | `AppearanceAnalyzer.analyze`: tone sampling → warmth/brightness → season + `_ACCESSORIES` map | Accessory copy, season boundaries |
| `weather_service.py` | Geocode (PH province seats) → forecast → `_fashion_tips` | `PH_PROVINCE_SEATS`, tip text, cache TTL |
| `news_feed.py` | Fetch → merge/dedupe → OG-image enrich | Feed URL list, category map, GDELT query |
| `shop_catalog.py` | Load operator JSON → validate hosts/sizes → rank | `_MARKETPLACE_HOSTS`, validation rules |
| `account_store.py` | `register/login/login_with_google/profile/save_measurements/update_profile/logout`; PBKDF2-SHA256 310k, 30-day tokens (sha256-hashed) | Token TTL, default height 165, schema |
| `google_auth.py` | `verify_google_id_token`: cert verify + `aud` + `email_verified` | Allowed client IDs |
| `schemas.py` | Every request/response + validators | Ranges, new fields |
| `main.py` | Route wiring + CORS (`CORS_ALLOWED_ORIGINS`) | Origins, new routes |

Storage tables (SQLite file `backend/data/seamly.db` or Postgres when
`DATABASE_URL` set): `users(id,name,email UNIQUE,password_hash,height_cm,
phone,location,created_at,google_sub UNIQUE)`, `sessions(token_hash,user_id,
expires_at)`, `measurement_profiles(user_id,measurements_json,size_label,
…)`, `account_pictures(user_id,avatar_base64)`.

---

## 8. Auth detail (both methods)

- **Password:** salted PBKDF2-SHA256 stored; raw password never kept.
  `register` → 30-day token; `login` → new token; `profile_for_token` rejects
  expired.
- **Google:** Flutter gets Google `id_token` (GIS on web, `authenticate()` on
  mobile) → `POST /v1/auth/google` → backend verifies signature/audience via
  Google certs → `login_with_google(sub,email,name)`:
  1. existing `google_sub` → login,
  2. else existing email → link `google_sub` + login (`is_new=false`),
  3. else create user (random password hash, height 165) (`is_new=true`).
- Changing height deletes saved measurements (both API + UI enforce
  height-match on scan save).

---

## 9. Config & environments

| Var / flag | Where set | Used in |
|---|---|---|
| `API_BASE_URL` (dart-define) | `build_web.ps1 -ApiBaseUrl`, `flutter run --dart-define` | `lib/services/seamly_api.dart` |
| `GOOGLE_WEB_CLIENT_ID` (dart-define) | `build_web.ps1 -GoogleWebClientId` | `google_sign_in_service.dart`, note in `_GoogleCard` |
| `google-signin-client_id` meta | `web/index.html` (also copy to `dist/index.html` on build) | GIS web SDK |
| `GOOGLE_CLIENT_IDS` (or legacy `GOOGLE_WEB_CLIENT_ID`) | `backend/.env.example`, Render dashboard | `backend/app/google_auth.py` |
| `DATABASE_URL` | Render / env | `account_store.py:create_account_store` (Postgres) vs SQLite |
| `STYLORISTA_DB_PATH` | env (optional) | SQLite file location |
| `CORS_ALLOWED_ORIGINS` | env (comma list) | `backend/app/main.py` (default allows localhost + one chatgpt.site origin) |
| `FASHIONTECH_SHOP_CATALOG_URL` / `_TOKEN` / `_JSON` | env | `shop_catalog.py` |
| `REDDIT_ACCESS_TOKEN` | env | `news_feed.py` |
| `seamly.*` SharedPreferences keys | device | `session_store.dart` (`seamly.authenticated`, `seamly.account_token`, `seamly.city`, …) |

---

## 10. Run / verify / deploy

```powershell
# API
cd backend
python -m venv .venv; .\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python -m uvicorn app.main:app --reload   # http://127.0.0.1:8000 + /docs

# Flutter (from repo root)
flutter pub get
flutter run -d chrome --web-hostname localhost --web-port 7357 --dart-define=API_BASE_URL=http://127.0.0.1:8000 --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_ID.apps.googleusercontent.com
flutter analyze
flutter test
cd backend; python -m pytest

# Web release → Firebase
powershell -File build_web.ps1 -ApiBaseUrl "https://YOUR-API" -GoogleWebClientId "YOUR_ID.apps.googleusercontent.com"
firebase deploy --only hosting
```

Android emulator uses `http://10.0.2.2:8000` as `API_BASE_URL`.

---

## 11. Developer change guide — “I want to change X → edit Y”

### Product / UI copy & brand

| Want | Edit |
|---|---|
| App name, tagline, colors, fonts | `lib/theme/seamly_theme.dart` (`SeamlyColors`, `buildSeamlyTheme`), `pubspec.yaml` (`name`, `version`), `web/manifest.json`, `web/index.html` title/meta |
| Logo / hero images | `assets/images/` + `pubspec.yaml` assets block |
| Onboarding text | `lib/features/welcome_screen.dart` |
| Terms text | `lib/features/auth_screen.dart` terms dialog |
| Bottom tabs / add a tab | `lib/app.dart` (`screens` list, `_BottomNavigation._destinations`, `_DesktopNavigation`) + new file in `lib/features/` |

### Auth & accounts

| Want | Edit |
|---|---|
| Email validation / password rules | `lib/features/auth_screen.dart` validators + `backend/app/schemas.py` (`AccountRegisterRequest`) |
| Default height for new accounts | `lib/features/auth_screen.dart` (`heightCm: 165`) + `backend/app/account_store.py:login_with_google` (165) |
| Token lifetime (30 days) | `backend/app/account_store.py:_create_session` (`timedelta(days=30)`) |
| Google client IDs / disable Google | Backend `GOOGLE_CLIENT_IDS` env (`google_auth.py`); Flutter `--dart-define=GOOGLE_WEB_CLIENT_ID` + `web/index.html` meta; hide via `_GoogleCard` |
| Link-vs-block same-email Google | `backend/app/account_store.py:login_with_google` |
| Avatar size / format | `backend/app/avatar.py:normalize_avatar` + `lib/features/account_screen.dart` picker limit |

### Fit / color / style engines

| Want | Edit |
|---|---|
| Size recommendation logic | `backend/app/ai_engine.py` (`SIZE_CENTRES`, `_build_size_model`, `_fit_notes`) + ranges in `schemas.py:Measurements` |
| Manual measurement fields | `lib/features/measurements_screen.dart` + `schemas.py:Measurements` |
| Color season rules / palettes | `backend/app/ai_engine.py` (`PALETTES`, `_color_features`) + swatches in `lib/features/color_analysis_screen.dart` |
| Outfit templates | `backend/app/ai_engine.py:recommend_style` + form in `lib/features/season_style_screen.dart` |
| Scan strictness / guidance copy | `backend/app/body_scan.py` (lighting/person gates) + `lib/features/camera_measurement_screen.dart` instructions |
| Selfie accessory suggestions | `backend/app/appearance_analysis.py` (`_ACCESSORIES`) + `lib/features/profile_screen.dart` |

### Weather / news / shop (external data)

| Want | Edit |
|---|---|
| Default city, PH bias, fashion tips | `backend/app/weather_service.py` (`DEFAULT_COUNTRY_BIAS`, `PH_PROVINCE_SEATS`, `_fashion_tips`); city default + cache key in `lib/features/home_screen.dart` |
| Weather provider / add API key | `weather_service.py:fetch` (Open-Meteo URLs, wttr fallback) |
| News sources / categories | `backend/app/news_feed.py` (feed URL tuple, `_fetch_gdelt`, category list) + chips in `lib/features/fashion_news_screen.dart`; Reddit via `REDDIT_ACCESS_TOKEN` |
| Shop listings / add marketplace | Operator JSON feed (env `FASHIONTECH_SHOP_*`) must match `schemas.py:ShopProduct`; allow-list in `backend/app/shop_catalog.py:_MARKETPLACE_HOSTS`; UI ranking in `lib/features/shop_screen.dart` |
| Open product links in-app vs browser | `lib/features/shop_screen.dart` + `fashion_news_screen.dart` (`url_launcher`) |

### API / data / infra

| Want | Edit |
|---|---|
| Add new endpoint | `backend/app/schemas.py` (models) → `backend/app/main.py` (route) → `lib/services/seamly_api.dart` (client method) → screen → `backend/tests/test_*.py` + `test/widget_test.dart` |
| Change validation ranges | `backend/app/schemas.py` only (frontend mirrors messages) |
| Change CORS | `backend/app/main.py` (`CORS_ALLOWED_ORIGINS`, `allow_origin_regex`) |
| Change DB (add column/table) | `backend/app/account_store.py` (`_ensure_schema` + `_ensure_google_column` pattern for SQLite, `ALTER … IF NOT EXISTS` for Postgres) — must handle both stores |
| Switch SQLite → Postgres | Set `DATABASE_URL`; tables auto-created by `PostgresAccountStore` |
| Change hosting / API URL | `firebase.json` (public dir), `.firebaserc` (project), `render.yaml` (service/env), `build_web.ps1` defaults |
| Bump version | `pubspec.yaml` (`version: x.y.z+N`) + `backend/app/main.py` (`version=`) |

### Tests to update together

| Changed | Update |
|---|---|
| Auth / account | `backend/tests/test_google_auth.py`, `test_account_settings.py`, `test/widget_test.dart` (auth flows), `test/account_settings_test.dart` |
| Scan / camera UI | `test/camera_capture_test.dart`, `backend/tests/test_api.py` (scan cases) |
| News/shop/weather | `backend/tests/test_api.py` (feed/catalog/weather sections) |

---

## 12. Privacy boundaries (do not regress)

- Scan/selfie photos: in-memory only, consent checkbox required
  (`consent_confirmed` validator), never stored or trained on. Only a passing
  scan may update measurements.
- Account pictures: explicit Save, 512px JPEG re-encode, EXIF stripped,
  returned only with auth; Remove+Save deletes; logout clears device cache and
  revokes server token.
- No raw passwords stored (PBKDF2 hashes only). Google `id_token` is verified
  server-side — never trust client email alone.

## 13. Known limitations / before public launch

- Scanner is **not** validated for tailoring, purchasing, or biometrics
  (README prototype disclaimer). Needs ground-truth tape evaluation before any
  accuracy claim.
- `Seamly` is a working name — needs trademark / store / domain clearance.
- Render free Postgres expires (see README) — use durable DB for real users.
- iOS is web-via-Safari only; native release needs Apple signing + Xcode build.

## 14. Quick FAQ

- **Where is the single source for backend calls?**
  `lib/services/seamly_api.dart` — every screen goes through it.
- **Where do I add a tab?** `lib/app.dart` screens list + both navigations.
- **Where do I add an endpoint?** `schemas.py` → `main.py` → `seamly_api.dart`
  → screen → tests.
- **Google not working locally?** Check meta in `web/index.html`, dart-define
  ID, Render `GOOGLE_CLIENT_IDS`, and Authorized JS origins include your
  `localhost:PORT` and hosting domain.
- **Shop shows “setup required”?** No operator feed connected — set
  `FASHIONTECH_SHOP_CATALOG_JSON/URL` (see `docs/SHOP_SOURCES.md`).
- **News missing Reddit?** Set approved `REDDIT_ACCESS_TOKEN`; otherwise
  skipped by design.
