# Seamly product plan

## Product thesis

People do not need more random outfit images. They need fashion recommendations grounded in their measurements, coloring, climate, occasion, comfort, and the actual construction of garments.

Seamly should act as a transparent styling assistant: collect the minimum necessary information, explain its recommendations, let users correct the profile, and never present an estimate as a guaranteed fit.

## Brand working definition

- **Working name:** Seamly
- **Descriptor:** Personal fashion intelligence
- **Tagline:** "See Your Size. Know Your Style. Shop With Confidence." (aligned with the DICT Startup Grant Fund pitch; earlier internal draft was "Fit. Tone. Season. You.")
- **Promise:** Fashion guidance built from the user's real context
- **Voice:** Warm, precise, inclusive, never judgmental
- **Visual direction:** Editorial cream and ink, berry accent, moss for utility, restrained gold for color analysis

The name is memorable and communicates “style + fashionista,” but it is not proven legally unique. See `AUDIT.md`.

## Pilot context

The initial pilot targets **Kalibo, Aklan (Region VI — Western Visayas)**, partnering with local apparel retailers and university communities, per the funding pitch. This grounds two product decisions already in scope: the tropical wet/dry seasonal logic below (Kalibo's actual climate pattern) and the guided, low-bandwidth-friendly measurement flow (no camera dependency) suited to a first market outside Metro Manila.

## MVP user journey

1. The user records guided body measurements in centimetres.
2. The API recommends a general starting-size label and explains where measurements may cross sizes.
3. The user selects representative skin, natural hair-root, and iris colors under daylight.
4. The API returns a four-season color direction with palette, neutrals, metals, and usage guidance.
5. The user selects climate, hemisphere, occasion, and style direction.
6. The recommender combines the current month, climate cycle, color profile, and starting size into an outfit system.

## MVP scope

### Fit profile

Captured measurements:

- height;
- neck;
- shoulder width;
- chest or bust;
- underbust;
- natural waist;
- high hip;
- full hip;
- sleeve length;
- wrist;
- inseam.

The minimum usable set is height, chest/bust, waist, and full hip. The output is a starting point, not a universal size. Each retailer ultimately requires garment measurements, ease, fabrication, and pattern-block information.

### Personal color

The MVP accepts deliberate color selections instead of a face photograph. It provides one of four broad styling directions: Spring, Summer, Autumn, or Winter. The result is aesthetic advice, not a biological, racial, or health classification.

### Current-season styling

The MVP handles:

- tropical wet and dry seasons;
- northern and southern temperate seasons;
- arid hot and mild periods;
- cold-climate cold and mild periods;
- everyday, work, event, and travel occasions;
- minimal, classic, street, and romantic style directions.

The initial wardrobe catalog is deliberately small and curated so every recommendation can be inspected.

### Reconciling MVP scope with the funding pitch

The DICT pitch deck describes a fuller feature set — weather-pulled OOTD trending, Korean-style personal color matching, face-shape-aware accessory recommendations, cross-store "Quick Size Search," voice command, and a companion in-store retail system (instant inventory match, assisted fitting, live stock check). None of these are in the current MVP. To keep the pitch honest against what is actually built:

- **Built now:** guided measurements, a starting-size label, four-season color direction (Spring/Summer/Autumn/Winter — not marketed as "Korean-style" until a licensed color-analysis methodology and trained analysts are in place), current-season/occasion outfit suggestions, and a source-safe commerce surface that can display exact product photos and listings from an approved normalized partner feed while rejecting mismatched sources.
- **Roadmap, not MVP:** face-shape matching, voice command, OOTD trend-pull, cross-store size search, and the in-store retail system all require data, partners, or models not yet built (see Delivery roadmap and `AUDIT.md`).
- **Pitch language to soften until shipped:** "Korean-style personal color matching" should read as "personal color / seasonal color analysis" until methodology is licensed or validated; "trending outfit-of-the-day" should not imply live social/trend data until Phase 4.

## Technical architecture

```text
Flutter client
    ├── Guided measurement form
    ├── Color selectors
    ├── Seasonal context
    └── Result explanations
             │ JSON/HTTPS
             ▼
FastAPI service
    ├── Pydantic validation
    ├── scikit-learn size classifier
    ├── scikit-learn color classifier
    └── nearest-neighbor outfit recommender
```

The API base URL is a Dart compile-time setting (`API_BASE_URL`). Production should add authentication, encrypted storage, strict CORS origins, rate limiting, observability, model registry, and user-controlled deletion.

## Model strategy

### Current demonstration models

- **Size:** imputation, scaling, and random-forest classification over a deterministic synthetic reference set.
- **Color:** engineered color/contrast features and random-forest classification over synthetic seasonal profiles.
- **Style:** one-hot categorical encoding and nearest-neighbor retrieval from a curated outfit catalog.

### Production data requirements

- consented, de-identified professional body measurements;
- garment-level measurement charts and pattern-block metadata;
- outcomes such as kept/returned, too tight/loose, and alteration locations;
- controlled-light color samples evaluated by trained color analysts;
- climate, fabric, occasion, mobility, modesty, and comfort labels;
- representation across body shapes, ages, disabilities, gender expressions, and skin tones.

No production model should be trained on scraped private images or infer protected traits.

## Delivery roadmap

Phase timing below is aligned to the pitch's 12-month indicative roadmap. Phases 0–1 are the scope of the DICT Startup Grant Fund "Proof of Concept to Prototype" request (₱500,000–₱700,000); Phases 2–4 depend on later funding (follow-on grant tranche, retail partner integration, or investment).

### Phase 0 — Foundation (implemented, Months 1–2)

- responsive Flutter shell;
- guided measurements;
- personal-color selections;
- climate-aware current-season logic;
- three scikit-learn workflows;
- API validation, tests, and disclaimers;
- product and risk audit.

### Phase 1 — Validated profile beta (target: Months 2–4; DICT-funded)

- user authentication and encrypted profile storage;
- measurement tutorial illustrations;
- centimetre/inch conversion;
- brand-specific garment charts;
- corrections and feedback after each recommendation;
- accessibility and screen-reader testing;
- consent, export, and delete-account flows;
- 50-participant manual-vs-AI accuracy benchmark and 100+ user willingness-to-pay interviews in Kalibo, per the pitch's validation plan.

**Exit metric:** at least 80% of beta users can complete a profile without assistance; zero sensitive-data retention outside the documented policy.

### Phase 2 — Commerce-quality fit & retail pilot integration (target: Months 4–9)

- partner garment measurements, fabric stretch, ease, and silhouette data;
- separate top, bottom, dress, footwear, and accessory sizing;
- calibrated evaluation set measured by trained professionals;
- subgroup performance and confidence calibration;
- recommendation abstention when confidence or coverage is inadequate;
- **in-store retail system (net-new build):** inventory-match lookup, fitting-room notification to a sales associate, and live per-branch stock confirmation, piloted with 1–2 Kalibo-based apparel retailers — this is the technical build-out behind the pitch's B2B SaaS product and is not started today.

**Exit metric:** materially lower size-related return rate than a standard chart for pilot products, with no unacceptable subgroup gap; signed pilot MOU with at least one Kalibo retailer.

### Phase 3 — Camera-assisted measurement research (target: Months 9+)

- explicit opt-in capture;
- front and side capture with a calibration reference;
- pose and garment-quality checks;
- on-device landmark extraction where practical;
- immediate deletion of raw images by default;
- professional-measurement validation and adversarial privacy review.

Camera assistance must remain an estimate and should fall back to guided tape measurements when capture quality is inadequate.

### Phase 4 — Live wardrobe, weather, cross-store search, and scale (target: post-Month 12)

- live local weather and severe-weather context feeding the OOTD/outfit engine (the trend-aware behavior referenced in the pitch);
- production cross-store "Quick Size Search" against authorized partner online
  retailer feeds (the source-linked UI and normalized validation contract are
  implemented; marketplace approval and live feeds remain outstanding);
- face-shape-aware accessory recommendations;
- voice command for search and navigation;
- digital wardrobe ingestion with explicit rights and deletion controls;
- cost-per-wear and outfit repetition tools;
- shopping only when an existing wardrobe cannot satisfy the brief;
- regional retailers, currencies, and availability; expansion beyond Western Visayas.

## Business model options

Named to match the pitch's revenue streams (see business plan Section 3/7):

- **Consumer Freemium Subscription:** free profile and limited outfits; paid tier unlocks wardrobe planning, packing lists, unlimited OOTD refreshes, and priority search — Phase 1–4.
- **Affiliate / Commission:** commission on completed purchases sourced through cross-store "Quick Size Search" — depends on Phase 4 retailer integrations.
- **B2B SaaS License (in-store retail system):** per-branch license for inventory-matching and fitting-room notification — depends on the Phase 2 retail-system build and signed retailer partnerships; this is a net-new engineering scope, not an extension of the consumer app.
- **Brand/Data Analytics (future):** aggregate, privacy-preserving fit gaps and unmet size demand for brand partners.

Do not sell raw body measurements, face imagery, or inferred sensitive traits. Monetization should come from software value, subscriptions, or clearly disclosed commerce — not surveillance.

## Core metrics

- profile completion rate;
- recommendation save rate;
- correction rate and reason;
- size-related return rate;
- recommendation coverage and abstention rate;
- confidence calibration;
- subgroup error gaps;
- deletion-request completion time;
- repeat outfits before new-purchase recommendations;
- customer trust and explanation usefulness.
