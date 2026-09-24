from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.neighbors import NearestNeighbors
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

from .schemas import ColorRequest, ColorResponse, SizeRequest, SizeResponse, StyleRequest, StyleResponse


SIZE_FEATURES = [
    "height",
    "neck",
    "shoulder",
    "chest",
    "underbust",
    "waist",
    "high_hip",
    "hip",
    "sleeve",
    "wrist",
    "inseam",
]

SIZE_CENTRES: dict[str, list[float]] = {
    "2XS": [158, 31, 36, 76, 68, 58, 78, 84, 56, 14, 73],
    "XS": [160, 32, 37.5, 82, 73, 64, 84, 90, 57, 14.5, 74],
    "S": [163, 34, 39, 88, 79, 70, 90, 96, 58, 15, 75],
    "M": [166, 36, 41, 96, 87, 78, 98, 104, 59, 16, 76],
    "L": [169, 38, 43, 104, 95, 86, 106, 112, 60, 17, 77],
    "XL": [172, 41, 45, 114, 105, 98, 116, 122, 61, 18, 78],
    "2XL": [174, 44, 47, 124, 115, 110, 128, 132, 62, 19, 79],
    "3XL": [176, 47, 49, 136, 127, 124, 140, 144, 63, 20, 80],
    "4XL": [178, 50, 51, 148, 139, 138, 152, 156, 64, 21, 81],
}

PALETTES = {
    "Spring": {
        "description": "Warm, clear and lively colors with fresh contrast.",
        "palette": ["#FF6F61", "#F7C948", "#5CC8A1", "#58A6D6", "#FF9E80"],
        "neutrals": ["#FFF3D6", "#C89B72", "#5B4636"],
        "metals": ["gold", "rose gold"],
    },
    "Summer": {
        "description": "Cool, soft and slightly muted colors with gentle contrast.",
        "palette": ["#8E9AAF", "#CBC0D3", "#6D9DC5", "#C98CA7", "#7FA99B"],
        "neutrals": ["#E8E6E3", "#9A9AA0", "#4D5866"],
        "metals": ["silver", "white gold"],
    },
    "Autumn": {
        "description": "Warm, earthy and rich colors with grounded contrast.",
        "palette": ["#B65C3A", "#D79A2B", "#6B7D3E", "#3F6B62", "#8B4A3B"],
        "neutrals": ["#E4C9A1", "#8A6A4A", "#3E332A"],
        "metals": ["antique gold", "bronze", "copper"],
    },
    "Winter": {
        "description": "Cool, clear and deep colors with crisp contrast.",
        "palette": ["#B0003A", "#2447A8", "#007C91", "#6A2C91", "#E23D74"],
        "neutrals": ["#FFFFFF", "#4B4F58", "#111111"],
        "metals": ["silver", "platinum"],
    },
}


@dataclass(frozen=True)
class Outfit:
    climate_season: str
    occasion: str
    style: str
    title: str
    summary: str
    pieces: tuple[str, ...]
    fabrics: tuple[str, ...]
    notes: tuple[str, ...]


OUTFITS = [
    Outfit("wet", "everyday", "minimal", "Rain-ready clean layers", "Breathable pieces that dry quickly without feeling technical.", ("relaxed water-resistant overshirt", "lightweight knit top", "straight ankle trousers", "grip-sole loafers", "compact umbrella"), ("Tencel", "cotton poplin", "recycled nylon"), ("Keep the trouser hem above splash level.", "Use one saturated accent against quiet neutrals.")),
    Outfit("wet", "work", "classic", "Polished monsoon tailoring", "Soft tailoring that handles warm commutes and strong indoor air-conditioning.", ("unlined blazer", "breathable shell top", "wide-leg trousers", "closed-toe slingbacks", "structured water-resistant tote"), ("tropical wool", "linen blend", "viscose twill"), ("Carry a fine-gauge layer for cold interiors.", "Choose wrinkle-resistant blends for travel.")),
    Outfit("wet", "travel", "street", "Utility travel system", "Modular layers for humidity, rain and changing transport temperatures.", ("packable shell", "boxy jersey tee", "convertible cargo trousers", "water-resistant sneakers", "crossbody pouch"), ("quick-dry jersey", "ripstop", "mesh"), ("Keep valuables in a zipped inner pocket.", "Repeat one color across shoes and accessories.")),
    Outfit("dry", "everyday", "romantic", "Airy sunlit separates", "Soft movement and sun-ready details for a warm, dry day.", ("square-neck blouse", "fluid midi skirt", "woven sandals", "lightweight scarf", "structured mini bag"), ("linen", "cotton voile", "Tencel"), ("Balance volume with one fitted piece.", "Use a scarf color close to your face palette.")),
    Outfit("dry", "work", "minimal", "Lightweight column dressing", "A tonal, office-ready silhouette designed for warm weather.", ("sleeveless longline vest", "fine-rib top", "pleated trousers", "minimal leather shoes", "slim belt"), ("linen blend", "tropical wool", "cotton rib"), ("Use tonal colors to lengthen the silhouette.", "Check workplace coverage requirements before wearing sleeveless pieces.")),
    Outfit("spring", "everyday", "romantic", "Soft transitional color", "Light layers and expressive color for changeable spring weather.", ("cropped cardigan", "printed blouse", "A-line jeans", "ballet flats", "small shoulder bag"), ("cotton knit", "denim", "silk blend"), ("Let one print lead the palette.", "Add or remove the cardigan as temperature changes.")),
    Outfit("summer", "event", "classic", "Warm-weather occasion set", "Elegant proportions with breathable fabrics and restrained shine.", ("draped midi dress", "light stole", "low heeled sandals", "metallic clutch", "sculptural earrings"), ("silk crepe", "linen satin", "cupro"), ("Prioritize lining that breathes.", "Match metal accessories to your color profile.")),
    Outfit("autumn", "work", "classic", "Textured modern tailoring", "Rich texture and a dependable layered structure for cooler days.", ("single-breasted blazer", "fine-gauge mock neck", "straight trousers", "leather loafers", "structured satchel"), ("wool twill", "merino", "brushed cotton"), ("Mix two textures within one color family.", "Keep the strongest color near the face.")),
    Outfit("winter", "everyday", "street", "Insulated street layers", "A warm modular outfit with proportion and movement.", ("long insulated coat", "heavyweight hoodie", "tapered trousers", "weatherproof boots", "ribbed beanie"), ("wool blend", "fleece", "weatherproof nylon"), ("Avoid compressing insulation with overly tight outerwear.", "Use the beanie or scarf as the color accent.")),
    Outfit("hot", "everyday", "minimal", "Heat-smart essentials", "Low-complexity pieces that protect from sun and release heat.", ("vented overshirt", "breathable tank", "relaxed drawstring trousers", "open sandals", "wide-brim hat"), ("linen", "hemp", "cotton seersucker"), ("Favor space between fabric and skin.", "Choose light-reflective neutrals for peak sun.")),
    Outfit("mild", "work", "classic", "Desert-day tailoring", "Crisp layers that adjust between warm daylight and cooler evenings.", ("light blazer", "collared knit", "straight trousers", "leather flats", "silk scarf"), ("cotton twill", "light wool", "silk"), ("Use the scarf as a removable temperature layer.", "A medium-value palette handles dust better than pure white.")),
    Outfit("cold", "event", "romantic", "Cold-weather evening texture", "Insulating pieces with a graceful line and controlled shine.", ("velvet column dress", "long wool coat", "thermal tights", "closed pumps", "statement earrings"), ("velvet", "wool cashmere", "thermal jersey"), ("Keep the coat hem compatible with the dress length.", "Use shine in one focal accessory.")),
]


class SeamlyEngine:
    """Deterministic demo models for the MVP.

    The generated training sets are intentionally local and reproducible. They
    prove the API/ML workflow but must be replaced by consented, validated data
    before any commercial fit claim is made.
    """

    def __init__(self) -> None:
        self._size_model = self._build_size_model()
        self._color_model = self._build_color_model()
        self._style_encoder, self._style_model = self._build_style_model()

    @staticmethod
    def _build_size_model() -> Pipeline:
        rng = np.random.default_rng(42)
        rows: list[np.ndarray] = []
        labels: list[str] = []
        noise_scale = np.array([3.5, 1.2, 1.5, 3.2, 3.0, 3.0, 3.2, 3.5, 2.0, 0.7, 2.5])
        for label, centre in SIZE_CENTRES.items():
            samples = rng.normal(np.array(centre), noise_scale, size=(160, len(SIZE_FEATURES)))
            rows.extend(samples)
            labels.extend([label] * len(samples))
        pipeline = Pipeline(
            [
                ("imputer", SimpleImputer(strategy="median")),
                ("scaler", StandardScaler()),
                (
                    "classifier",
                    RandomForestClassifier(
                        n_estimators=180,
                        max_depth=10,
                        min_samples_leaf=3,
                        random_state=42,
                        class_weight="balanced",
                    ),
                ),
            ]
        )
        pipeline.fit(np.asarray(rows), np.asarray(labels))
        return pipeline

    @staticmethod
    def _build_color_model() -> Pipeline:
        rng = np.random.default_rng(73)
        centres = {
            "Spring": [0.22, 0.78, 0.52, 0.52, 0.26, 0.38],
            "Summer": [-0.13, 0.75, 0.50, 0.55, 0.20, 0.23],
            "Autumn": [0.17, 0.60, 0.24, 0.29, 0.38, 0.34],
            "Winter": [-0.12, 0.64, 0.12, 0.25, 0.54, 0.30],
        }
        scales = np.array([0.11, 0.09, 0.12, 0.12, 0.10, 0.08])
        rows: list[np.ndarray] = []
        labels: list[str] = []
        for label, centre in centres.items():
            samples = rng.normal(np.asarray(centre), scales, size=(260, 6))
            rows.extend(samples)
            labels.extend([label] * len(samples))
        model = Pipeline(
            [
                ("scaler", StandardScaler()),
                ("classifier", RandomForestClassifier(n_estimators=220, random_state=73, min_samples_leaf=3)),
            ]
        )
        model.fit(np.asarray(rows), np.asarray(labels))
        return model

    @staticmethod
    def _build_style_model() -> tuple[ColumnTransformer, NearestNeighbors]:
        rows = np.asarray([[o.climate_season, o.occasion, o.style] for o in OUTFITS], dtype=object)
        encoder = ColumnTransformer(
            [("categories", OneHotEncoder(handle_unknown="ignore"), [0, 1, 2])],
            remainder="drop",
        )
        encoded = encoder.fit_transform(rows)
        model = NearestNeighbors(n_neighbors=1, metric="cosine")
        model.fit(encoded)
        return encoder, model

    def recommend_size(self, request: SizeRequest) -> SizeResponse:
        values = request.measurements.model_dump()
        row = np.asarray([[values.get(feature) for feature in SIZE_FEATURES]], dtype=object)
        probabilities = self._size_model.predict_proba(row)[0]
        classes = self._size_model.named_steps["classifier"].classes_
        ranked = np.argsort(probabilities)[::-1]
        best_index = int(ranked[0])
        recommended = str(classes[best_index])

        if request.fit_preference != "regular":
            ordered = list(SIZE_CENTRES)
            current = ordered.index(recommended)
            adjustment = -1 if request.fit_preference == "close" else 1
            recommended = ordered[max(0, min(len(ordered) - 1, current + adjustment))]

        alternatives = [
            {"label": str(classes[int(index)]), "probability": round(float(probabilities[int(index)]), 3)}
            for index in ranked[:3]
        ]
        notes = self._fit_notes(values, recommended, request.fit_preference)
        return SizeResponse(
            recommended_size=recommended,
            confidence=round(float(probabilities[best_index]), 3),
            alternatives=alternatives,
            fit_notes=notes,
            model_version="size-demo-0.1.0",
            disclaimer="Prototype estimate from synthetic reference data. Brand patterns and garment ease vary; verify against each garment chart and a physical fitting.",
        )

    @staticmethod
    def _fit_notes(values: dict[str, float | None], recommended: str, preference: str) -> list[str]:
        centre = dict(zip(SIZE_FEATURES, SIZE_CENTRES[recommended], strict=True))
        notes = [f"Recommendation uses a {preference} fit preference."]
        differences = {
            name: float(values[name]) - centre[name]
            for name in ("chest", "waist", "hip")
            if values.get(name) is not None
        }
        largest = max(differences, key=lambda key: abs(differences[key]))
        if differences[largest] > 4:
            notes.append(f"Your {largest} measurement is above this reference block; prioritize that area when checking garment charts.")
        elif differences[largest] < -4:
            notes.append(f"Your {largest} measurement is below this reference block; alterations may improve the intended silhouette.")
        else:
            notes.append("Chest, waist and hip are relatively close to this reference block.")
        if values.get("inseam") is not None and abs(float(values["inseam"]) - centre["inseam"]) > 4:
            notes.append("Check the listed inseam or finished garment length before ordering trousers.")
        notes.append("When measurements cross sizes, select by the garment's least flexible area and tailor the rest.")
        return notes

    def analyze_color(self, request: ColorRequest) -> ColorResponse:
        features = np.asarray([self._color_features(request)], dtype=float)
        probabilities = self._color_model.predict_proba(features)[0]
        classes = self._color_model.named_steps["classifier"].classes_
        best_index = int(np.argmax(probabilities))
        season = str(classes[best_index])
        palette = PALETTES[season]
        warmth = features[0, 0]
        contrast = features[0, 4]
        guidance = [
            "Use the palette near your face first; trousers and shoes can stay neutral.",
            "Compare two real fabrics in indirect daylight before buying a statement piece.",
            f"Detected {'warm' if warmth >= 0 else 'cool'} direction with {'higher' if contrast > 0.38 else 'softer'} contrast.",
        ]
        return ColorResponse(
            season=season,
            confidence=round(float(probabilities[best_index]), 3),
            description=palette["description"],
            palette=palette["palette"],
            neutrals=palette["neutrals"],
            metals=palette["metals"],
            guidance=guidance,
            model_version="color-demo-0.1.0",
            disclaimer="Personal-color analysis is aesthetic guidance, not a biological assessment. Camera white balance, makeup, lighting and dyed hair can change the result.",
        )

    @staticmethod
    def _hex_to_rgb(value: str) -> np.ndarray:
        raw = value.lstrip("#")
        return np.asarray([int(raw[i : i + 2], 16) / 255 for i in (0, 2, 4)], dtype=float)

    def _color_features(self, request: ColorRequest) -> list[float]:
        skin = self._hex_to_rgb(request.skin_hex)
        hair = self._hex_to_rgb(request.hair_hex)
        eyes = self._hex_to_rgb(request.eye_hex)
        skin_value = float(np.max(skin))
        hair_value = float(np.max(hair))
        eye_value = float(np.max(eyes))
        warmth = float((skin[0] - skin[2]) + 0.25 * (skin[0] - skin[1]))
        contrast = float(max(abs(skin_value - hair_value), abs(skin_value - eye_value)))
        saturation = float(np.mean([np.ptp(skin), np.ptp(hair), np.ptp(eyes)]))
        return [warmth, skin_value, hair_value, eye_value, contrast, saturation]

    def recommend_style(self, request: StyleRequest) -> StyleResponse:
        climate_season = self._climate_season(request.climate, request.hemisphere, request.month)
        row = np.asarray([[climate_season, request.occasion, request.style]], dtype=object)
        encoded = self._style_encoder.transform(row)
        _, indices = self._style_model.kneighbors(encoded)
        outfit = OUTFITS[int(indices[0, 0])]
        palette = PALETTES[request.color_season]["palette"][:4]
        notes = list(outfit.notes)
        if request.size_label:
            notes.append(f"Use {request.size_label} only as a starting point; confirm each brand's garment measurements and intended ease.")
        return StyleResponse(
            current_season=climate_season.title(),
            title=outfit.title,
            summary=outfit.summary,
            pieces=list(outfit.pieces),
            fabrics=list(outfit.fabrics),
            palette=palette,
            styling_notes=notes,
            model_version="style-neighbors-0.1.0",
        )

    @staticmethod
    def _climate_season(climate: str, hemisphere: str, month: int) -> str:
        if climate == "tropical":
            return "wet" if 6 <= month <= 11 else "dry"
        if climate == "arid":
            return "hot" if 3 <= month <= 10 else "mild"
        if climate == "cold":
            return "cold" if month in (10, 11, 12, 1, 2, 3) else "mild"
        north = {
            12: "winter", 1: "winter", 2: "winter",
            3: "spring", 4: "spring", 5: "spring",
            6: "summer", 7: "summer", 8: "summer",
            9: "autumn", 10: "autumn", 11: "autumn",
        }
        if hemisphere == "northern":
            return north[month]
        inverse = {"winter": "summer", "spring": "autumn", "summer": "winter", "autumn": "spring"}
        return inverse[north[month]]

