# Event Outfit Planner — Plan (Home, above Weather)

> Status: **✅ IMPLEMENTED** (backend `POST /v1/outfits/plan` + Home
> `Plan your outfit` card). This doc is now the record of what was decided
> and built.

---

## 1. What the user asked (in own words, cleaned)

- In Home, **above the weather**, users choose clothing preferences.
- They **type the event** their fashion is for (free text, e.g. wedding).
- They choose the **date and time** of the event.
- They choose the **fashion type/style** they want.
- The app picks the **best outfit for that date/time based on predicted weather**.
- When the user has **scanned their body**, the outfit also respects their
  measurements/size + chosen style ("you get what I meant?" — yes).

## 2. Proposed UX (Home page, above weather card)

New card: **`Plan your outfit`** — placed between the `Scan your fit` banner
(`home-start-scan`) and the city weather card in
`lib/features/home_screen.dart`.

```text
┌ Plan your outfit ────────────────────┐
│ What's the event?  [ cocktail party _ ]│  ← text field + suggestion chips
│   (Business Casual Mixer · Office      │
│    Holiday Party · Alumni Networking · │
│    Conference · Cocktail Party ·       │
│    Brunch · Birthday Dinner ·          │
│    Engagement · Garden Wedding ·       │
│    Holiday Gathering · Music Festival ·│
│    Beach/Cruise · Bachelorette ·       │
│    First Date · Funeral + quick picks: │
│    Birthday · Wedding · Office ·       │
│    Church · Beach · Graduation —       │
│    all scrollable)                     │
│ Date  [ Sat, Jun 14 ▾ ]               │  ← date picker, any future date
│ Time  [  4:00 PM  ▾ ]                 │  ← time picker (default 6 PM)
│ Style [ Minimal Classic Street       │  ← chips + free-text field
│         Romantic  + type your own ]   │  (e.g. "elegant", "sporty")
│ [ Get outfit ]                        │
│ ─ result ─                            │
│  Wedding · Sat 4 PM · 31° Mostly     │
│  clear · Feels 33° · 20% rain         │
│  Linen blazer + … (Size M)            │
│  Why: heat + rain-risk + formal …     │
│  Palette: Autumn [■■■]  fabrics: …    │
│  [View in Style] [Rescan to refine]   │
└──────────────────────────────────────┘
```

Rules:

1. **Event field is free text + chips.** Typing "wedding" maps to occasion
   `event`; unknown text falls back to `everyday` with the raw text echoed
   ("Outfit for 'family reunion'"). Mapping table lives in one place
   (frontend const + backend canonicalization — backend wins).
2. **Date: any future date allowed.** Within 16 days → real forecast.
   Beyond 16 days → outfit still suggested, clearly labeled
   "seasonal estimate, not a forecast" (user decision). Past dates are
   rejected inline.
3. **Time matters.** The forecast hour nearest the chosen time drives
   temperature/feels-like/rain/wind/UV. Evening hours add a layer note.
4. **Style chips + free text** (user decision). Four chips
   (`minimal|classic|street|romantic`) plus a "type your own" field
   (e.g. "elegant", "sporty", "preppy"). Typed words are keyword-mapped
   to the closest engine style behind the scenes
   (elegant/formal → classic; sporty/edgy → street; cute/soft → romantic;
   simple/clean → minimal; unknown → engine default) and the user's own
   words are echoed in the result title.
5. **Personalization block** (only if scan data exists): shows
   `Size M · Autumn` line; without scan data shows
   `Scan your fit for size-true picks →` linking to tab 2.
6. Result card always shows **why** (2–4 short reasons: heat, rain, wind,
   formality, fit) — matches the app's "explicit explanations" principle.
7. Inputs persist per session in `SharedPreferences`
   (`seamly.event.*, se keyword: event text, date ISO, time, style`) and the
   last result is cached so leaving Home doesn't wipe it.

## 3. How the answer is computed (backend)

### 3.1 New endpoint (recommended)

```text
POST /v1/outfits/plan
Request: {
  "event_text": "wedding",        # free text, 2–80 chars
  "city": "Manila",               # reuse Home city
  "event_date": "2026-06-14",     # ISO date, today..today+16
  "event_time": "16:00",          # HH:MM 24h (optional, default 18:00)
  "style": "classic",             # minimal|classic|street|romantic|null
  "size_label": "M",              # optional (from scan)
  "color_season": "Autumn",       # optional (from analysis)
  "measurements": {...}           # optional (from scan, for fit notes)
}
Response: {
  "event_text": "wedding",
  "occasion": "event",            # canonicalized
  "city": "Manila",
  "event_datetime": "2026-06-14T16:00:00+08:00",
  "weather": { "temp_c": 31, "feels_c": 33, "condition": "Mostly clear",
               "rain_prob": 20, "wind_kmh": 14, "uv": 6.5,
               "is_forecast": true },
  "outfit": { "title": "...", "pieces": [...], "fabrics": [...],
              "palette": [...], "styling_notes": [...],
              "size_label": "M", "fit_notes": [...] },
  "reasons": ["31° heat → breathable linen", "20% rain → ...", ...],
  "confidence": 0.72,
  "disclaimer": "Forecast-based suggestion, not a guarantee. ..."
}
```

Why a new endpoint instead of gluing two old ones on the client:

- The client today calls `GET /v1/weather/home` (current + tomorrow only)
  and `POST /v1/style/recommend` (month granularity, no hour, no event text).
  An event planner needs **date-indexed daily + hourly forecast** and
  **event→occasion mapping** in one place, with one disclaimer.
- Keeps the "why" logic server-side and testable.

### 3.2 Weather for an arbitrary date/time

- Reuse `backend/app/weather_service.py` geocoding (city → lat/lon, PH bias
  kept).
- Extend forecast fetch: Open-Meteo `forecast` with
  `daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,weathercode,uv_index_max`
  + `hourly=temperature_2m,apparent_temperature,precipitation_probability,weathercode`
  + `start_date=end_date=event_date`, `forecast_days=16`, `timezone=auto`.
- Pick the hourly slot nearest `event_time`; daily row gives rain/UV bounds.
- `is_forecast=false` path: date >16 days out or API down → fall back to
  `SeamlyEngine.recommend_style` climate/month logic + "seasonal estimate"
  label (same pattern as the existing wttr.in fallback).

### 3.3 Outfit composition (reuse, don't reinvent)

1. `event_text` → `occasion` map (backend canonicalizes; user text echoed):
   - `work`: mixer, office, holiday party (office), networking, conference,
     seminar
   - `event`: cocktail, brunch, birthday, engagement, wedding, holiday
     gathering, bachelorette, date, funeral, church, graduation
   - `travel`: beach, cruise, festival (outdoor + on-the-move)
   - `everyday`: anything else / unknown text (raw text still echoed:
     "Outfit for 'family reunion'").
   - Funeral note: mapped to `event` + a somber-palette hint (dark
     neutrals) in the post-adjust step.
2. Climate comes from the geocoded city (keep tropical default for PH),
   month from `event_date`, style from chips (or engine default).
3. Call existing `SeamlyEngine.recommend_style(...)` for pieces/fabrics/
   palette, then **post-adjust for the hour's weather**: heat (≥30° → linen,
   drop layers), rain (≥40% → darker colors, quick-dry, carry layer), wind
   (≥25 km/h → secure fits), UV (≥8 → cover note), evening (≥18:00 → +1 layer
   note for formal events).
4. Fit: if `size_label`/`measurements` passed (from the shell's scan state),
   attach fit notes (`ai_engine` size follow-up); never invent a size.

## 4. Frontend changes (files)

| # | File | Change |
|---|---|---|
| 1 | `lib/services/seamly_api.dart` | Add `planEventOutfit({eventText,city,eventDate,eventTime,style?,sizeLabel?,colorSeason?,measurements?})` → `POST /v1/outfits/plan` |
| 2 | `lib/features/home_screen.dart` | New `_EventOutfitCard` widget above weather card; date/time pickers (`showDatePicker`/`showTimePicker`); style chips; result view; persist inputs via `SharedPreferences`; pass `widget.sizeLabel/colorSeason` + measurements (shell must also pass `initialMeasurements` into `HomeScreen`, like `ShopScreen` gets today) |
| 3 | `lib/app.dart` (`SeamlyShell`) | Pass `_scannedMeasurements` into `HomeScreen` (new optional param) so the planner can send fit data |
| 4 | `test/widget_test.dart` | New tests: card renders above weather; past date blocked; mocked plan response renders outfit + reasons; no-scan shows rescan hint |

No new tab, no nav change. `SeasonStyleScreen` stays as the "deep" version;
Home card links `View in Style → tab 7` with the chosen values prefilled
(optional stretch).

## 5. Backend changes (files)

| # | File | Change |
|---|---|---|
| 1 | `backend/app/schemas.py` | Add `OutfitPlanRequest` / `OutfitPlanResponse` (+ weather slice, reasons, disclaimer); `event_text` 2–80 chars, `event_date` ISO, `event_time` HH:MM |
| 2 | `backend/app/weather_service.py` | Add `fetch_for_datetime(city, date, time)` returning the nearest-hour slice + `is_forecast` flag; keep existing `fetch()` untouched |
| 3 | `backend/app/main.py` | Add `POST /v1/outfits/plan` (calls weather slice → occasion map → `SeamlyEngine.recommend_style` → weather post-adjust → response) |
| 4 | `backend/app/ai_engine.py` | Small pure helper for weather post-adjustments (so it's unit-testable without HTTP) |
| 5 | `backend/tests/test_outfit_plan.py` (new) | Tests: wedding+heat snapshot, rain adjustment, >16-day estimate flag, unknown event text fallback, invalid/past date 422 |

## 6. Edge cases & copy

- Past date/time → inline error, no API call.
- City unresolvable → same 404 style as weather today ("couldn't find…").
- API offline → keep last good result + "couldn't refresh" (Home's pattern).
- No scan → outfit still works, fit line replaced by rescan CTA.
- Timezone: use the city's forecast timezone; display "Sat, Jun 14 · 4:00 PM".
- Disclaimer (always under result): prototype styling guidance; confirm with
  seller size chart; forecast can shift.

## 7. Build order (after you approve)

1. Backend: schemas → weather slice → endpoint + engine helper → tests
   (`python -m pytest` from `backend/`).
2. Flutter: `seamly_api.planEventOutfit` → `HomeScreen._EventOutfitCard` →
   shell wiring → widget tests (`flutter test`).
3. Verify: `flutter analyze`, manual pass (wedding future date, rain case,
   no-scan case), then commit + push.

## 8. Decisions (answered ✅ — ready to build)

1. ~~Date limit?~~ → Allow any future date; beyond 16 days show
   "seasonal estimate, not a forecast."
2. ~~Style chips?~~ → Chips (Minimal/Classic/Street/Romantic) PLUS free-text
   field with keyword mapping; user's words echoed in the result.
3. ~~Event chips?~~ → 21 shortcuts: 15 custom (Business Casual Mixer, Office
   Holiday Party, Alumni Networking Event, Conference / Seminar, Cocktail
   Party, High-End Daytime Brunch, Milestone Birthday Dinner, Engagement
   Party, Outdoor / Garden Wedding, Winter Holiday Gathering, Music Festival,
   Beach Party / Cruise Night, Themed Bachelorette Party, First Date,
   Funeral / Celebration of Life) + 6 quick picks (Birthday, Wedding,
   Office, Church, Beach, Graduation).
