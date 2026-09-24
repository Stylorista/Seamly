# Seamly

Seamly is a privacy-conscious fashion styling MVP built with Flutter and FastAPI. It combines:

- database-backed registration, hashed passwords, 30-day session tokens, and a one-time welcome screen;
- a header account button for editing your name, height in centimetres, and private profile picture, plus current-session logout;
- guided fashion measurements and a starting-size recommendation;
- a guided, consent-gated camera or photo scan that instructs users to move to a well-lit area, frame their full body, estimates 11 garment measurements using the height saved in their account profile, and places a lighting-checked color-season palette below the camera result;
- a source-linked shop that ranks exact marketplace listings when an approved
  product feed is connected, with image-free Shopee, Lazada, and Temu searches
  as the honest fallback;
- a category-filtered fashion news feed powered by publisher RSS, Google News, and GDELT, with article-owned Open Graph imagery and duplicate-image removal;
- a curated profile hub with fit scanning, weather-aware outfits, complexion color guidance, and consent-based accessory suggestions;
- live current and next-day city weather with forecast-matched fashion guidance;
- a four-season personal-color direction from selected skin, hair, and eye colors;
- climate- and season-aware outfit recommendations;
- explicit explanations and limitations for every AI result.

> **Prototype status:** The body scanner uses deterministic image geometry and strict full-person/framing checks. It proves the product workflow, but it is not validated for commercial sizing, tailoring, biometric measurement, or purchasing guarantees.

> **Authentication status:** Accounts are validated by the API. Passwords are stored as salted PBKDF2-SHA256 hashes, raw passwords are never retained, and accepted measurement profiles can be restored after sign-in. Local development uses SQLite; hosted deployments should configure PostgreSQL for durable storage.

## Repository structure

```text
lib/                 Flutter user interface
backend/app/         FastAPI routes, account storage, news, weather, and analysis engines
backend/tests/       API tests
docs/PRODUCT_PLAN.md Product definition and delivery roadmap
docs/AUDIT.md        Brand, product, privacy, AI, and technical audit
```

## Run the Python API

Create a virtual environment and install the dependencies:

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python -m uvicorn app.main:app --reload
```

The API is served at `http://127.0.0.1:8000`; interactive documentation is at `http://127.0.0.1:8000/docs`.

The fashion feed reads Google News RSS and GDELT without a local key. Optional Reddit stories require approved Reddit Data API access and an OAuth token:

```powershell
$env:REDDIT_ACCESS_TOKEN="your-approved-oauth-token"
```

Facebook and Instagram are shown as unavailable until an approved Meta app and eligible accounts are connected; the prototype does not scrape private or restricted social feeds.

Publisher and GDELT images are taken from the story metadata. When a feed omits an image, the API attempts to read `og:image` or `twitter:image` from the article itself. It never substitutes the same local fashion photo across unrelated stories.

Home weather uses Open-Meteo city search and its current/two-day forecast. Manila is the default, and users can enter another city without granting precise device-location permission.

### Account database

For local use, the API creates `backend/data/seamly.db` automatically. For an online Render deployment, create a Render PostgreSQL database and set the web service's `DATABASE_URL` environment variable to its internal connection string. The app will switch to PostgreSQL automatically. Render's free PostgreSQL databases currently expire after 30 days, so use a paid database or another durable PostgreSQL provider before real users rely on the service.

The shop never assigns a generic photo to a product. Exact product photos,
titles, sellers, and links are accepted only from a backend-configured approved
seller or affiliate feed, and the backend rejects records whose listing and
image hosts do not match the named marketplace. When no approved feed is
connected, Seamly shows image-free search suggestions instead of fake
listings. See [the shop source contract](docs/SHOP_SOURCES.md) for the normalized
feed format and marketplace onboarding boundary.

## Use the online app

Open [Seamly online](https://stylorista-ai.jadesalvador3257.chatgpt.site) in a current browser.

On iPhone, open the link in Safari, tap **Share**, then choose **Add to Home Screen**. This installs the web app icon and launches it in a standalone app window. A native App Store/TestFlight release still requires Apple Developer signing and a macOS/Xcode build.

## Run Flutter

From the repository root:

```powershell
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

For an Android emulator, point the app at the host loopback alias:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

## Verify

```powershell
flutter analyze
flutter test
cd backend
python -m pytest
```

## Privacy boundary

The body-scan and profile-accessory prototypes send a selected photo to the configured API only after an explicit consent checkbox. These analysis endpoints process the image in memory without retaining it or reusing it for training. Only a scan that passes the person, framing, and confidence checks can update the signed-in account's measurement profile.

Account pictures are separate: choosing a picture previews it on-device, and **Save changes** uploads it to the authenticated account. The API accepts JPEG, PNG, and WebP pictures up to 2 MB / 16 megapixels, resizes them to a maximum 512-pixel edge, and re-encodes them without original photo metadata. Pictures are stored in the account database and returned only with an authenticated profile or successful login. **Remove photo**, then **Save changes**, deletes the saved picture value. Device-cached account data is cleared at logout; online logout also revokes that session token.

The camera estimator needs a known height because an ordinary single photo has no absolute centimetre scale. Check your actual height in **Home → profile button → Height** before scanning; legacy registration initializes this value to 165 cm. Changing height invalidates saved scan estimates and size recommendations, and stale-height scan saves are rejected by the API. The estimator is not validated for purchasing, tailoring, biometric identification, or medical use. Continuous measurement quality must be evaluated against consented ground-truth tape measurements using centimetre error and within-tolerance rates; a 98% ROC-AUC claim would be technically inappropriate and is not made.

## Important naming note

`Seamly` is a working product name, not a cleared trademark. Obtain professional trademark, company-registry, app-store, social-handle, and domain clearance before public launch.
