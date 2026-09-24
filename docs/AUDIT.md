# Seamly initial audit

Audit date: 2026-08-31 (updated to align with the DICT Startup Grant Fund pitch materials)  
Scope: working brand, MVP product concept, AI validity, privacy, safety, accessibility, technical implementation, and consistency with the funding pitch (business plan and use-of-funds).

Pilot context: the funding pitch targets an initial pilot in Kalibo, Aklan (Region VI — Western Visayas). This audit's findings are unaffected by pilot location; where noted below, the pitch's claims are checked against what is actually built.

## Executive assessment

The concept is viable as a guided styling assistant. Its strongest differentiation is the combination of body measurements, personal color, and local climate—including tropical wet/dry seasons—inside one explained profile.

The largest product risk is overclaiming. A photo does not yield trustworthy absolute body measurements without calibration, controlled capture, computer vision, validation, and robust handling of pose and clothing. The MVP now includes an explicitly experimental, height-calibrated silhouette scan alongside guided tape measurements. Its generated-data models are appropriate for demonstrating system flow only.

## Brand-name audit

| Check | Result | Risk | Required action |
|---|---|---:|---|
| New working name “Seamly” | Name changed after the initial search | Unknown | Run a fresh professional clearance across markets and languages before launch |
| Trademark registers | Not formally cleared | High | Search relevant Nice classes with a qualified professional |
| Domains and social handles | Not verified | Medium | Check target domains, app stores, and priority networks |
| Pronunciation and meaning | Readable but somewhat long | Low | Test recall and spelling with target users |
| Tagline | Pitch materials now use "See Your Size. Know Your Style. Shop With Confidence."; an earlier internal draft ("Fit. Tone. Season. You.") should be retired to avoid mixed messaging | Low | Use one tagline consistently across product, pitch, and marketing copy |

The working name may be used for development. It must not be represented as trademark-cleared or legally exclusive.

## Pitch-to-product consistency audit

The funding pitch (business plan) describes several consumer and B2B features that are not yet built. This is expected at prototype stage, but the pitch and product materials should describe these consistently so reviewers, partners, and future users are not misled.

| Pitch claim | Current build status | Recommended framing |
|---|---|---|
| "Korean-style personal color matching" | MVP returns one of four broad seasonal directions from user-selected colors, not a licensed Korean personal-color methodology | Describe as "personal color / seasonal color analysis" until a specific methodology is licensed or validated by trained analysts |
| "Trending outfit-of-the-day looks" | Recommendations come from a small, curated, static catalog — no live trend or social data | Describe as "curated outfit suggestions" until Phase 4 live-trend ingestion exists |
| "Face-shape-aware recommendations" | Not implemented in any phase 0–1 code | Label as roadmap (Phase 4) in any materials shown to users or partners |
| "Search any online store for the exact size and fit" (Quick Size Search) | No retailer integrations exist yet | Label as roadmap (Phase 4); do not demo as live functionality |
| In-store retail system (instant inventory match, assisted fitting, live stock check) | Entirely unbuilt; no retailer inventory/POS integration exists | Scope explicitly as Phase 2 net-new engineering requiring signed retail partners; do not present as pilot-ready |
| Voice command | Not implemented | Label as roadmap (Phase 4) |

**Recommendation:** any pitch deck, demo, or grant-review walkthrough should clearly separate "built and testable today" from "funded roadmap" so the DICT evaluators see an honest maturity picture. This is also lower-risk for the applicant: overclaiming readiness in a grant application invites harder follow-up questions than a clearly scoped, honestly staged roadmap.

## Product audit

| Area | Status | Finding |
|---|---|---|
| User problem | Good | Fit uncertainty, color confusion, and climate mismatch are understandable problems |
| First-use value | Good | A user can receive three outputs without creating an account |
| Geographic relevance | Good | Tropical wet/dry logic avoids assuming that every user has four seasons |
| Body measurement | Guarded | Guided tape input remains primary; the photo scan is consent-gated, height-calibrated, non-retained, and labeled experimental |
| Universal sizing | Weak by nature | Alpha sizes are not standardized across brands or garments |
| Personal color | Exploratory | Broad palettes can inspire, but lighting and subjective interpretation limit accuracy |
| Explainability | Good | Results include fit notes, palette guidance, fabrics, and model versions |
| Commerce readiness | Integration-ready | Source-linked product/image validation and exact-listing UI are built, but no approved marketplace feed, garment measurements, inventory SLA, or returns feedback is connected yet |

## AI and data audit

### High-priority limitations

1. The training data is synthetic. Reported model confidence is class probability within the demonstration model, not real-world accuracy.
2. There is no calibrated validation set or subgroup evaluation.
3. The size model predicts a generic label rather than garment-specific fit.
4. The color model uses selected RGB values, not calibrated spectrophotometry or controlled photography.
5. The outfit catalog is small; nearest-neighbor retrieval can return a partially matching outfit when an exact combination is absent.

### Controls already present

- numeric ranges are validated by Pydantic and Flutter forms;
- a scan photo is transmitted only after explicit consent, processed in memory, and not retained or reused for training;
- every size and color response includes a limitation statement;
- deterministic random seeds make the demo reproducible;
- model versions are returned by the API;
- tropical, temperate, arid, and cold climate logic is explicit and testable.
- shop photos fail closed unless the exact listing URL and image CDN match the
  declared marketplace; duplicate or mismatched records are hidden.

### Controls required before production

- datasheets and consent records for every training source;
- separate development, calibration, and locked evaluation sets;
- subgroup sample-size requirements and error reporting;
- calibrated confidence and an abstain/ask-for-more-information outcome;
- model registry, signed artifacts, rollback, and monitoring;
- human review of catalog rules and high-impact changes;
- user feedback labels that do not silently retrain production models.

## Privacy and security audit

Body measurements are sensitive personal data even when they are not legally classified as biometric identifiers. A future face/body-photo workflow increases the risk substantially.

### Current MVP

- Data is transmitted to the configured API but not persisted by the included code.
- CORS is configured for local development only.
- The app has a local demonstration authentication gate, but no identity provider, credential storage, or secure server session.
- There are no analytics or advertising trackers.

### Production blockers

- TLS and strict production origins;
- authentication and authorization;
- encryption at rest with separated keys;
- data minimization and field-level retention schedules;
- user consent, access, export, correction, and deletion;
- rate limits, abuse detection, audit logs, and incident response;
- secrets management and dependency scanning;
- a documented legal basis in every launch market;
- a data-protection impact assessment for camera-based measurement.

Raw body or face photos should be processed on-device where practical and deleted immediately by default. They should never be reused for model training without separate, specific, revocable consent.

## Inclusive-design audit

### Positive choices

- avoids gender as a required sizing input;
- includes sizes 2XS through 4XL in the demonstration reference set;
- calls measurements “chest / bust” and uses neutral language;
- does not infer ethnicity, gender, health, or attractiveness;
- uses local climate instead of fashion calendars alone.

### Gaps to test

- screen-reader labels and focus order;
- color contrast and non-color result cues;
- users who cannot stand or use a measuring tape;
- seated measurements and adaptive clothing needs;
- headwear, modest-fashion, maternity, prosthetic, and sensory preferences;
- size coverage beyond the current demonstration range;
- nonbinary and culturally diverse style taxonomies.

## Technical audit

### Strengths

- Flutter UI and ML service are cleanly separated;
- API contracts have typed validation;
- API endpoint tests cover health, invalid measurements, size, color, and tropical season behavior;
- API location is injected at build time;
- no database or cloud dependency is required for the MVP.

### Known technical debt

- app state is in-memory and resets on restart;
- no offline cache or retry policy;
- no generated typed API client;
- no localization or unit conversion;
- marketplace seller/affiliate authorization and normalized production feeds
  are not connected, so the source-linked catalog intentionally remains empty;
- no production authentication, persistence, telemetry, or deployment configuration;
- development CORS origins must be made explicit for each served port;
- model training currently occurs at process start instead of loading signed artifacts;
- catalog breadth and test coverage must expand before user trials.

## Release decision

**Approved for local prototype/demo use.**  
**Not approved for production sizing claims, public camera scanning, medical/body assessment, automated purchasing, or storage of personal profiles.**

The next safe milestone is a small, consented usability study using guided measurements and clearly labeled recommendations. Brand clearance and privacy engineering should run in parallel.

### Fit with the DICT funding ask

The current build matches a "Proof of Concept to Prototype" grant stage, not "Prototype to MVP": core AI workflows exist end-to-end but run on synthetic data, there is no persistence or auth, and none of the retail-integration or camera-capture features are started. The pitch's ₱500,000–₱700,000 request against this track is consistent with the audit's findings — it should fund exactly what is listed as Phase 1 in `PRODUCT_PLAN.md` (validated profile beta, accuracy benchmarking, user research), not the in-store system or MVP-level commerce features, which require separate, later funding.
