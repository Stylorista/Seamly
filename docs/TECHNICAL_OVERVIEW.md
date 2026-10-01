# Seamly — Technical Overview & Developer Change Guide
### *(written so a high school student can understand it)*

> **What is this doc?** Think of it as the "owner's manual" for our app.
> It explains what the app is, what each part does, how the parts talk to
> each other, and — most importantly — **exactly which file to open when you
> want to change something**.
>
> App version covered: `1.8.2+17`. Server version: `1.7.0`.
> Main branch: `main`.

---

## 1. What is this app? (the 30-second version)

Imagine a friendly fashion adviser living inside your phone. It's called
**Seamly**, and it can:

- Create your account and remember you (sign in with email or Google).
- Guess your clothing size from your measurements or a body photo.
- Tell you which colors look good on you (like "you're an Autumn!").
- Suggest outfits based on the weather in your city.
- Show fashion news and online shop listings.

**Two big pieces make it work** — like a restaurant:

- 🍽️ **The dining room = the Flutter app.** This is everything you see and
  tap on your phone or in the browser. (Built with Flutter, a toolkit from
  Google for making apps.)
- 👨‍🍳 **The kitchen = the Python server.** This is a hidden computer that
  does the thinking: checking passwords, guessing sizes, fetching weather.
  Your phone sends it a note ("here's my photo, what size am I?") and it
  sends back an answer. (Built with FastAPI, a popular Python tool for
  servers.)

Important honesty note: the body scanner is a **prototype**. It uses simple
photo-measuring math, not a super-smart AI. It proves the idea works, but a
real tailor should still double-check before you buy expensive clothes!

---

## 2. The ingredients (tech stack, in plain words)

| Piece | Plain meaning | Nerdy name |
|---|---|---|
| What you see | The phone/website screens | Flutter 3.44 + Dart 3.12 |
| The kitchen | The hidden computer that answers questions | Python + FastAPI + Uvicorn |
| The rulebook | A strict checklist that keeps messages tidy | Pydantic v2 |
| The filing cabinet | Where accounts are saved (a simple file on your laptop, a stronger database online) | SQLite (local) / PostgreSQL (online) |
| The stage | Where the website and kitchen live on the internet | Firebase Hosting (website) + Render (kitchen) |
| Outside helpers | Free weather/news services our kitchen asks for info | Open-Meteo, wttr.in, Google News RSS, GDELT, publisher RSS feeds |

Helpful add-ons inside the app: `camera` (take photos), `image_picker`
(choose photos), `http` (send notes to the kitchen), `shared_preferences`
(the phone's little sticky-note memory), `url_launcher` (open links),
`google_sign_in` (the "Continue with Google" button).

---

## 3. Map of the whole project (where everything lives)

```text
lib/   ← THE DINING ROOM (everything you see on screen)
  main.dart                  ← the front door: opens the app
  app.dart                   ← the host: checks your ticket (login),
                               then shows the tabs (Home, Shop, Scan…)
  theme/seamly_theme.dart    ← the interior designer: colors, fonts
  services/
    seamly_api.dart          ← THE WAITER: the ONLY one allowed to carry
                               notes between your phone and the kitchen
    session_store.dart       ← sticky notes: remembers you after you close
                               the app (saved login, city, size)
    google_sign_in_service.dart ← the Google-button helper
  features/                  ← one file = one screen
    auth_screen.dart         ← login / register + Google button
    welcome_screen.dart      ← first-time hello screen
    home_screen.dart         ← dashboard + weather
    shop_screen.dart         ← clothes for sale
    camera_measurement_screen.dart ← body scan (the brains of the flow)
    camera_capture_view.dart ← body scan (just the camera window, no brains)
    fashion_news_screen.dart ← fashion news feed
    profile_screen.dart      ← style hub + selfie accessories
    measurements_screen.dart ← type your tape measurements → get a size
    color_analysis_screen.dart ← pick skin/hair/eye colors → get your season
    season_style_screen.dart ← pick climate + occasion → get an outfit
    account_screen.dart      ← edit name/height/photo + log out
  widgets/                   ← reusable LEGO bricks (headers, avatars,
                               Google button, little cards)

backend/   ← THE KITCHEN (the hidden computer)
  app/
    main.py              ← the reception desk: receives every note, sends
                           it to the right cook (ALL web addresses live here)
    schemas.py           ← the rulebook: what each note must look like
    account_store.py     ← the filing cabinet: accounts, login tickets
    google_auth.py       ← the ID checker: "is this Google login real?"
    ai_engine.py         ← three recipe books: size, color, style
    body_scan.py         ← the measuring-tape robot (photo → numbers)
    appearance_analysis.py ← the color-stylist robot (selfie → palette)
    weather_service.py   ← the weather reporter (asks Open-Meteo outside)
    news_feed.py         ← the newspaper collector (RSS + Google News…)
    shop_catalog.py      ← the shop bouncer (only approved listings get in)
    avatar.py            ← the photo cleaner (shrinks pictures, removes
                           hidden location data)
  tests/                 ← taste-testers: automatic checks that scream
                           if a recipe breaks
  requirements.txt       ← shopping list of Python ingredients
  .env.example           ← example of secret settings (keys go here, never
                           in the app itself!)

web/index.html           ← the website's front page (has the Google ID tag)
firebase.json            ← "serve the website from the dist/ folder"
render.yaml              ← "run the kitchen on Render.com"
build_web.ps1            ← one-click script: build the website
assets/images/           ← logo + decoration pictures
test/                    ← automatic checks for the dining room (Flutter)
docs/                    ← manuals like this one
```

**Golden rule for new developers:** the phone NEVER talks to the outside
world directly. It only talks to our kitchen (`seamly_api.dart` → our
server), and the *kitchen* talks to weather/news services. This keeps secrets
safe.

---

## 4. The kitchen's menu (every web address, plainly explained)

Your phone sends notes to addresses like `/v1/auth/login`. Here's the full
menu. (Techy details in brackets for developers.)

| Address | What it means in plain words |
|---|---|
| `GET /health` | "Are you awake, kitchen?" → "Yes!" |
| `POST /v1/auth/register` | "I'd like an account please" (send name, email, password, height) → you get a login ticket |
| `POST /v1/auth/login` | "It's me again" (email + password) → login ticket |
| `POST /v1/auth/google` | "Google says I'm me" (Google login token) → login ticket (reuses your account if the email matches) |
| `POST /v1/auth/logout` | "I'm leaving, tear up my ticket" |
| `GET /v1/account/profile` | "Show me my profile" (needs your ticket) |
| `PUT /v1/account/profile` | "Update my name/height/photo" |
| `PUT /v1/account/measurements` | "Save my new measurements" |
| `POST /v1/size/recommend` | "Here are my numbers, what size am I?" |
| `POST /v1/color/analyze` | "Here's my skin/hair/eye color, what's my season?" |
| `POST /v1/style/recommend` | "It's hot and I'm going to work, what should I wear?" |
| `POST /v1/outfits/plan` | "I'm going to a garden wedding Saturday at 4 PM — what should I wear?" (event text + date + time + style → forecast-driven outfit with reasons) |
| `POST /v1/body-scan/preview` | "Quick look at my photo — am I standing right?" |
| `POST /v1/body-scan/analyze` | "Measure my whole body from this photo" (needs permission checkbox!) |
| `POST /v1/profile/analyze` | "What accessories match my selfie?" (needs permission checkbox!) |
| `GET /v1/news/feed` | "Give me fashion news" (pick a category like wedding or vintage) |
| `GET /v1/shop/products` | "Show me clothes for sale" (only approved listings!) |
| `GET /v1/weather/home` | "What's the weather in my city, and what should I wear?" |

**Login tickets explained:** when you sign in, the kitchen gives your phone
a long secret code (a "token"). Your phone shows this ticket with every
private request. Tickets expire after 30 days, like a monthly bus pass.

---

## 5. Outside helpers (services we borrow, for free!)

| Helper | What it does | Needs a key? |
|---|---|---|
| Google Sign-In | The familiar "Continue with Google" button; our kitchen double-checks Google's ID card | YES — a free Google client ID (see §9) |
| Open-Meteo | Free weather forecasts (no sign-up!) | No |
| wttr.in | Backup weather reporter if Open-Meteo naps | No |
| Google News RSS | Public fashion headlines feed | No (it's public, not a secret API) |
| GDELT | A giant global news index researchers use | No |
| Vogue / ELLE / Fashionista feeds | Fashion magazines' public article feeds | No |
| Reddit search | Extra fashion stories | Only if you add an approved token; otherwise the app just skips it |
| Shop feed | A list of real products from a shop partner YOU connect | Only if you set it up; otherwise the app honestly says "not connected yet" and shows search ideas |
| Pexels photos | Style-inspiration photos in the outfit planner, labeled "not actual products" (never listings) | Free key in `PEXELS_API_KEY`; without it the planner just shows no photos |
| Firebase Hosting | Puts our website on the internet | Your Firebase login |
| Render | Runs our kitchen computer 24/7 | Your Render login |

What we do **NOT** use: no Google Maps, no face-recognition AI, no payment
system, no spying on private Instagram/Facebook.

---

## 6. How the app flows (follow a user around!)

### 6.1 Opening the app (the host checks your ticket)

```text
You tap the icon
  → Logo splash for 1 second (it's secretly re-reading your sticky notes)
  → Got a valid ticket? Come right in! 🎉
  → First visit ever? Hello screen → tap NEXT
  → No ticket? Login screen
While you're inside, the app quietly refreshes your profile in the
background. Logging out tears up your ticket on BOTH your phone and
the kitchen computer.
```
Lives in: `lib/main.dart` (front door) + `lib/app.dart` (the host, `AuthGate`).

### 6.2 Logging in (two doors, same house)

- **Email door:** type email + password (8+ characters). New accounts start
  with height 165 cm — you'll fix it later in your profile.
- **Google door:** tap the Google button. On the website it's Google's own
  button; on phones our app asks Google, gets an ID card, and hands it to
  our kitchen. The kitchen calls Google to verify the card is real, then
  finds your account **by email** — so your old password account and your
  Google login become ONE account, not two!
- After either door: your ticket + profile are saved on sticky notes
  (`SharedPreferences`), so you stay logged in.

Lives in: `lib/features/auth_screen.dart` + `lib/services/seamly_api.dart`
(waiter) + `backend/app/google_auth.py` (ID checker).

### 6.3 The tabs (rooms of the restaurant)

Bottom bar on phones, side bar on wide computers. The big round camera
button in the middle is the body scanner!

| Tab | Screen | Plain job |
|---|---|---|
| Home | `home_screen.dart` | Weather in your city + "what to wear" teaser |
| Shop | `shop_screen.dart` | Real listings (or honest search ideas) |
| Scan 📷 | `camera_measurement_screen.dart` | Body photo → measurements |
| News | `fashion_news_screen.dart` | Fashion headlines by category |
| Profile | `profile_screen.dart` | Style hub + selfie accessories |
| (hidden) Measurements | `measurements_screen.dart` | Type tape numbers → size |
| (hidden) Color | `color_analysis_screen.dart` | Pick colors → your season |
| (hidden) Style | `season_style_screen.dart` | Pick climate/occasion → outfit |
| (hidden) Account | `account_screen.dart` | Edit name/height/photo, log out |

The app remembers three shared things everywhere: your **size**, your
**color season**, and your **measurements**. A scan updates all three at once.

### 6.4 Each feature, super simply

- **Manual size** (`measurements_screen.dart`): type 11 numbers (height,
  chest, waist…) → kitchen answers with a size like "M" + confidence.
- **Color** (`color_analysis_screen.dart`): tap the closest skin/hair/eye
  swatches → kitchen says "You're an Autumn!" + color palette.
- **Style** (`season_style_screen.dart`): pick climate + occasion + vibe →
  kitchen writes you a full outfit recipe.
- **Body scan** (`camera_measurement_screen.dart`): check two permission
  boxes → stand in good light, full body in frame → live preview says
  "move left!" → snap → kitchen measures you + suggests a palette. The
  camera window itself (`camera_capture_view.dart`) is "dumb" — it only
  displays, all thinking happens in the other file. The green ready signal
  runs the same strict gates as analysis (so ready means it will pass),
  every rejection names the top fix, and after 2 failed scans the app
  suggests the back camera or a gallery photo. On phones, each photo is
  first cleaned on-device (Google ML Kit person segmentation → white
  background) before measuring; web and failures fall back to the
  original photo untouched.
- **Weather** (`home_screen.dart`): your city is remembered; pull down to
  refresh, like email. Above the weather sits the **Plan your outfit** card:
  type an event (21 shortcut chips), pick date + time, pick or type a style
  → the app returns a forecast-driven outfit with reasons
  (`POST /v1/outfits/plan`), personalized by your scan size and color.
- **Shop** (`shop_screen.dart`): only shows listings from an approved list
  with matching photos (no fake products!). Otherwise it shows
  "search ideas" that open Shopee/Lazada/Temu in your browser.
- **News** (`fashion_news_screen.dart`): pick Y2K, wedding, vintage…; hearts
  are just for fun (saved on your phone only).
- **Account** (`account_screen.dart`): change name/height/photo. Photos are
  shrunk to small size and hidden location data is scrubbed. ⚠️ Changing
  your height deletes old scan results (because they'd be wrong now!).

---

## 7. The kitchen robots (what each Python file does)

| Robot (file) | Job in plain words | Tweak it here |
|---|---|---|
| `ai_engine.py` | 3 recipe books: size guesser, color season finder, outfit writer | The size averages, color palettes, outfit texts |
| `body_scan.py` | Measuring-tape robot: finds your silhouette, checks the lighting, converts photo widths to centimeters using your height | Light sensitivity, how strict the "stand straight!" check is |
| `appearance_analysis.py` | Selfie stylist: samples skin tone → picks season + accessory ideas | Accessory suggestions, season boundaries |
| `weather_service.py` | Weather reporter: finds your city (extra smart about Philippine provinces!), fetches forecast, writes "wear linen today" tips | City list, tip texts |
| `news_feed.py` | Newspaper collector: grabs articles, removes duplicates, finds pictures | Which magazines, which categories |
| `shop_catalog.py` | Shop bouncer: ONLY lets in listings with matching real photos from Shopee/Lazada/Temu | Which shops are allowed, validation rules |
| `account_store.py` | Filing cabinet: saves accounts (passwords are scrambled with heavy math called PBKDF2, 310,000 rounds!), hands out 30-day tickets | Ticket lifetime, default height |
| `google_auth.py` | ID checker: calls Google to verify login cards | Which Google IDs are allowed |
| `schemas.py` | Rulebook: every note's required shape (e.g. height must be 120–230 cm, photo analysis needs the permission box checked) | Allowed ranges, new fields |
| `main.py` | Reception desk: routes every note + decides which websites may call (CORS) | Website permissions, new addresses |

Filing cabinet drawers (database tables): `users` (who you are),
`sessions` (active tickets), `measurement_profiles` (saved body numbers),
`account_pictures` (your photo). Locally it's one file
(`backend/data/seamly.db`); online it's a stronger Postgres database.

---

## 8. Settings & secret keys (the boring-but-important part)

| Setting | Where you set it | What reads it |
|---|---|---|
| `API_BASE_URL` | When starting the app (e.g. `--dart-define=API_BASE_URL=...`) | The waiter (`seamly_api.dart`) — "which kitchen do I talk to?" |
| `GOOGLE_WEB_CLIENT_ID` | When building the app | Google button helper — "which Google ID is mine?" |
| Google tag in `web/index.html` | Edit the file (paste your ID) | Google's website button |
| `GOOGLE_CLIENT_IDS` | Server settings (Render dashboard) | ID checker (`google_auth.py`) |
| `DATABASE_URL` | Server settings | Filing cabinet — "use the strong database" (if empty, uses the simple file) |
| `CORS_ALLOWED_ORIGINS` | Server settings | Reception desk — "which websites may order food?" |
| Shop feed keys (`FASHIONTECH_SHOP_*`) | Server settings | Shop bouncer — "where's the approved product list?" |
| `REDDIT_ACCESS_TOKEN` | Server settings | Newspaper collector — bonus stories (optional) |
| `seamly.*` sticky notes | Automatic on your phone | Session memory (login, city, size…) |

**Safety rule:** secret keys live ONLY on the kitchen computer (server
settings). NEVER paste them into the phone app — anyone can read app code!

---

## 9. Everyday commands (copy-paste recipes)

```powershell
# Start the kitchen (from the backend/ folder)
python -m venv .venv; .\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python -m uvicorn app.main:app --reload
# Open http://127.0.0.1:8000 and http://127.0.0.1:8000/docs (try the menu!)

# Start the dining room (from the project folder)
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
# (Android emulator? use http://10.0.2.2:8000 instead!)

# Health checks (do these before every commit!)
flutter analyze
flutter test
cd backend; python -m pytest

# Put the website online
powershell -File build_web.ps1 -ApiBaseUrl "https://YOUR-KITCHEN" -GoogleWebClientId "YOUR-ID.apps.googleusercontent.com"
firebase deploy --only hosting
```

---

## 10. 🛠️ DEVELOPER CHANGE GUIDE — "I want to change X, where do I go?"

> **How to read this:** left = your wish in plain words. Right = exact
> file(s) to open + what to touch. Always run the health checks (§9) after!

### Looks & words (design, text, brand)

| I want to… | Open this and change that |
|---|---|
| Change colors, fonts, the whole vibe | `lib/theme/seamly_theme.dart` — the `SeamlyColors` paint box + `buildSeamlyTheme()` |
| Change the app name or version | `pubspec.yaml` (name + version), `web/manifest.json`, `web/index.html` (title) |
| Swap the logo / background photos | `assets/images/` folder + the assets list in `pubspec.yaml` |
| Rewrite the welcome screen | `lib/features/welcome_screen.dart` |
| Rewrite the terms & conditions popup | `lib/features/auth_screen.dart` (search "Terms") |
| Add a brand-new tab | `lib/app.dart`: add your screen to the `screens` list + both menus (`_BottomNavigation` for phones, `_DesktopNavigation` for computers) + create your screen file in `lib/features/` |

### Accounts & login

| I want to… | Open this and change that |
|---|---|
| Change password rules ("must be 8+ characters") | `lib/features/auth_screen.dart` (the form check) AND `backend/app/schemas.py` (`AccountRegisterRequest`) — change BOTH or they'll disagree! |
| Change the starting height (165 cm) | `lib/features/auth_screen.dart` (search `165`) AND `backend/app/account_store.py` (`login_with_google`) |
| Make login tickets last longer/shorter than 30 days | `backend/app/account_store.py` → `_create_session` → `timedelta(days=30)` |
| Set up Google login with my own ID | Server setting `GOOGLE_CLIENT_IDS` + app build flag `GOOGLE_WEB_CLIENT_ID` + paste ID into `web/index.html` meta tag |
| Hide the Google button | `lib/features/auth_screen.dart` → `_GoogleCard` |
| Change photo rules (size/format) | `backend/app/avatar.py` (`normalize_avatar`) + `lib/features/account_screen.dart` (picker limit) |

### Size / color / outfits (the smart stuff)

| I want to… | Open this and change that |
|---|---|
| Make size guesses smarter/different | `backend/app/ai_engine.py` (size averages + guessing model) + allowed ranges in `backend/app/schemas.py` (`Measurements`) |
| Add/remove a measurement box (e.g. "arm length") | `lib/features/measurements_screen.dart` (the form) + `backend/app/schemas.py` (`Measurements`) |
| Change color seasons or palettes | `backend/app/ai_engine.py` (`PALETTES`) + the swatch colors in `lib/features/color_analysis_screen.dart` |
| Rewrite outfit suggestions | `backend/app/ai_engine.py` (`recommend_style`) + the dropdowns in `lib/features/season_style_screen.dart` |
| Make the body scanner stricter/looser | `backend/app/body_scan.py` (lighting + "are you standing right?" checks) + instructions in `lib/features/camera_measurement_screen.dart` |
| Change selfie accessory ideas | `backend/app/appearance_analysis.py` (`_ACCESSORIES`) + display in `lib/features/profile_screen.dart` |

### Weather / news / shop

| I want to… | Open this and change that |
|---|---|
| Change the default city or outfit tips | `backend/app/weather_service.py` (province list, tip texts); the app's default + memory in `lib/features/home_screen.dart` |
| Switch weather provider | `backend/app/weather_service.py` (`fetch` — the Open-Meteo web addresses) |
| Add/remove a news source or category | `backend/app/news_feed.py` (magazine addresses at the top, category list) + the chips in `lib/features/fashion_news_screen.dart`; Reddit needs the `REDDIT_ACCESS_TOKEN` setting |
| Add a shop or change what's sold | Connect a product list via `FASHIONTECH_SHOP_*` settings (must match the shape in `schemas.py:ShopProduct`); allowed shops in `backend/app/shop_catalog.py`; ranking in `lib/features/shop_screen.dart` |
| Change how product links open | `lib/features/shop_screen.dart` + `fashion_news_screen.dart` (the `url_launcher` calls) |

### Kitchen / database / internet

| I want to… | Open this and change that |
|---|---|
| Add a NEW web address (endpoint) | 5 steps, always in order: ① `backend/app/schemas.py` (the note's shape) → ② `backend/app/main.py` (the route) → ③ `lib/services/seamly_api.dart` (waiter's new method) → ④ your screen file → ⑤ tests! |
| Change allowed number ranges | `backend/app/schemas.py` only (the phone copies its messages from here) |
| Let another website use the kitchen (CORS) | `backend/app/main.py` (`CORS_ALLOWED_ORIGINS`) |
| Add a database column/table | `backend/app/account_store.py` — follow the existing `google_sub` pattern (simple-file version AND Postgres version, both!) |
| Move to the strong online database | Set the `DATABASE_URL` setting — tables build themselves |
| Change where the website/API live | `firebase.json` (website folder), `.firebaserc` (project name), `render.yaml` (kitchen settings), `build_web.ps1` (defaults) |
| Release a new version number | `pubspec.yaml` (`version: x.y.z+N`) + `backend/app/main.py` (`version=`) |

### Tests to update together (don't forget!)

| I changed… | I must also update… |
|---|---|
| Login / accounts | `backend/tests/test_google_auth.py`, `test_account_settings.py`, `test/widget_test.dart`, `test/account_settings_test.dart` |
| Scanner / camera screen | `test/camera_capture_test.dart` + scan cases in `backend/tests/test_api.py` |
| News / shop / weather | matching sections in `backend/tests/test_api.py` |

---

## 11. Privacy promises (never break these!)

1. 📷 **Body/selfie photos are never saved.** They're examined in memory and
   thrown away — like a doctor who forgets your face after the checkup. The
   permission checkbox is REQUIRED.
2. 🖼️ **Profile photos are separate.** Only saved when YOU tap Save. Shrunk
   small, location data scrubbed, shown only to you. Delete = really deleted.
3. 🔑 **Passwords are scrambled** with heavy math (PBKDF2, 310,000 rounds).
   Even we can't read them.
4. 📩 **Google logins are verified** with Google directly — we never trust
   an email just because the phone says so.
5. 📏 **Changing height erases old scans** — because old numbers would now
   be lies!

## 12. Honest limitations (read before launch day!)

- The scanner is a **prototype, not a tailor**. It needs testing against
  real tape measurements before anyone promises accuracy.
- "Seamly" is a **working name** — check trademarks, app-store names, and
  domains before printing business cards.
- Free online databases can expire — get a permanent one before real users
  arrive.
- iPhones currently use the website version; a real App Store release needs
  Apple signing + a Mac computer.

## 13. Quick answers (FAQ)

- **"Where do phone-to-kitchen calls live?"** → One file:
  `lib/services/seamly_api.dart`. Every screen orders through this waiter.
- **"Where do I add a tab?"** → `lib/app.dart` (screen list + both menus).
- **"Where do I add a web address?"** → rulebook → reception desk → waiter
  → screen → tests (§10, "kitchen" table).
- **"Google login broken on my laptop?"** → check 3 things: the tag in
  `web/index.html`, the build flag ID, the server's `GOOGLE_CLIENT_IDS` —
  plus Google's "allowed websites" list must include your address.
- **"Shop says 'setup required'?"** → no product list connected yet — set
  `FASHIONTECH_SHOP_CATALOG_JSON` (see `docs/SHOP_SOURCES.md`).
- **"No Reddit stories?"** → normal without a token — skipped on purpose.
