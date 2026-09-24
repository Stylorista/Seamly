from __future__ import annotations

import base64
import binascii
from collections import deque
from io import BytesIO

import numpy as np
from PIL import Image, ImageOps, UnidentifiedImageError

from .schemas import (
    BodyScanPreviewRequest,
    BodyScanPreviewResponse,
    BodyScanRequest,
    BodyScanResponse,
    Measurements,
)


MEASUREMENT_NAMES = (
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
)

MEASUREMENT_LIMITS = {
    "height": (120.0, 230.0),
    "neck": (20.0, 70.0),
    "shoulder": (25.0, 75.0),
    "chest": (55.0, 190.0),
    "underbust": (50.0, 170.0),
    "waist": (45.0, 190.0),
    "high_hip": (55.0, 200.0),
    "hip": (60.0, 210.0),
    "sleeve": (35.0, 90.0),
    "wrist": (10.0, 35.0),
    "inseam": (45.0, 110.0),
}


class BodyScanError(ValueError):
    pass


class BodyScanEstimator:
    """Conservative, deterministic silhouette measurement preview.

    A result is returned only after human-shape and framing checks pass. Values
    come from the submitted silhouette plus the user's known height; there is no
    synthetic random-forest prediction. Low-confidence derived values stay in
    the API response for compatibility but are explicitly excluded from display.
    """

    def preview(self, request: BodyScanPreviewRequest) -> BodyScanPreviewResponse:
        """Live viewfinder readiness check (no measurements)."""
        try:
            image = self._decode_image(request.image_base64)
            array = self._prepare_image(image)
        except BodyScanError as error:
            return BodyScanPreviewResponse(
                ready=False,
                person_detected=False,
                person_confidence=0.0,
                guidance=str(error),
                bbox=None,
            )
        try:
            self._validate_lighting(array)
        except BodyScanError as error:
            return BodyScanPreviewResponse(
                ready=False,
                person_detected=False,
                person_confidence=0.0,
                guidance=str(error),
                bbox=None,
            )
        try:
            mask, _separation = self._foreground_mask(array)
            mask = self._largest_connected_component(mask, min_fraction=0.012)
            bounds = self._subject_bounds(mask, min_height_fraction=0.34)
            person_confidence, _warnings = self._validate_person_shape(
                mask, bounds, lenient=True
            )
        except BodyScanError as error:
            return BodyScanPreviewResponse(
                ready=False,
                person_detected=False,
                person_confidence=0.0,
                guidance=str(error),
                bbox=None,
            )

        height, width = mask.shape
        x_min, y_min, x_max, y_max = bounds
        bbox = [
            round(x_min / width, 4),
            round(y_min / height, 4),
            round((x_max - x_min + 1) / width, 4),
            round((y_max - y_min + 1) / height, 4),
        ]
        coverage = (y_max - y_min + 1) / height
        center = ((x_min + x_max) / 2) / width
        ready = person_confidence >= 0.52 and 0.42 <= coverage <= 0.96

        if not ready:
            if coverage < 0.42:
                guidance = "Step back so your full body fits in the frame."
            elif coverage > 0.96:
                guidance = "Move back a little so your head and feet are visible."
            elif abs(center - 0.5) > 0.22:
                guidance = "Stand in the centre of the guide."
            else:
                guidance = "Face forward with arms slightly away from your sides."
        else:
            guidance = "Ready — hold still and take the photo."

        return BodyScanPreviewResponse(
            ready=ready,
            person_detected=True,
            person_confidence=round(float(np.clip(person_confidence, 0, 1)), 2),
            guidance=guidance,
            bbox=bbox,
        )

    def analyze(self, request: BodyScanRequest) -> BodyScanResponse:
        image = self._decode_image(request.image_base64)
        array = self._prepare_image(image)
        self._validate_lighting(array)
        mask, separation = self._foreground_mask(array)
        mask = self._largest_connected_component(mask)
        bounds = self._subject_bounds(mask)
        person_confidence, person_warnings = self._validate_person_shape(mask, bounds)
        x_min, y_min, x_max, y_max = bounds
        subject_height_px = y_max - y_min + 1
        scale = request.reference_height_cm / subject_height_px

        ratios = (0.22, 0.33, 0.49, 0.61)
        widths = [self._width_at(mask, bounds, ratio) * scale for ratio in ratios]

        height = request.reference_height_cm
        shoulder = widths[0]
        chest = widths[1] * 2.35
        waist = widths[2] * 2.18
        hip = widths[3] * 2.35
        raw = np.asarray(
            [
                height,
                max(height * 0.195, shoulder * 0.82),
                shoulder,
                chest,
                chest * 0.90,
                waist,
                waist * 0.46 + hip * 0.54,
                hip,
                height * 0.355,
                height * 0.095,
                height * 0.46,
            ],
            dtype=float,
        )

        values: dict[str, float] = {}
        for index, name in enumerate(MEASUREMENT_NAMES):
            low, high = MEASUREMENT_LIMITS[name]
            values[name] = round(float(np.clip(raw[index], low, high)), 1)

        quality, quality_warnings = self._quality(mask, bounds, separation)
        if quality < 0.64 or person_confidence < 0.68:
            raise BodyScanError(
                "No clearly framed full-body person was detected. Show one person "
                "standing straight, head to toe, against a plain contrasting background."
            )
        warnings = [*person_warnings, *quality_warnings]
        confidence_multipliers = {
            "height": 0.99,
            "neck": 0.42,
            "shoulder": 0.86,
            "chest": 0.78,
            "underbust": 0.44,
            "waist": 0.76,
            "high_hip": 0.50,
            "hip": 0.80,
            "sleeve": 0.38,
            "wrist": 0.28,
            "inseam": 0.46,
        }
        confidence = {
            name: round(
                float(
                    np.clip(
                        quality * person_confidence * multiplier,
                        0.15,
                        0.98,
                    )
                ),
                2,
            )
            for name, multiplier in confidence_multipliers.items()
        }
        scan_confidence = round(float(np.mean(list(confidence.values()))), 2)
        displayable = [
            name
            for name in MEASUREMENT_NAMES
            if name == "height" or confidence[name] >= 0.55
        ]

        return BodyScanResponse(
            person_detected=True,
            person_confidence=round(person_confidence, 2),
            measurements=Measurements(**values),
            scan_confidence=scan_confidence,
            image_quality=round(quality, 2),
            measurement_confidence=confidence,
            displayable_measurements=displayable,
            quality_warnings=warnings,
            model_version="body-silhouette-geometry-0.2.0",
            validation_status=(
                "Unvalidated measurement preview. ROC-AUC is not a valid metric for centimetre "
                "estimates; accuracy must be measured with MAE and within-tolerance tests on "
                "consented reference measurements."
            ),
            disclaimer=(
                "Only measurements above the display threshold are shown. A single photo cannot "
                "provide exact neck, wrist, sleeve, or depth-based circumferences. Verify with a "
                "tape measure and the seller's garment chart before buying or altering clothing."
            ),
        )

    @staticmethod
    def _decode_image(value: str) -> Image.Image:
        encoded = value.split(",", 1)[-1] if value.startswith("data:") else value
        try:
            raw = base64.b64decode(encoded, validate=True)
        except (binascii.Error, ValueError) as error:
            raise BodyScanError("The captured photo could not be decoded.") from error
        if len(raw) > 12 * 1024 * 1024:
            raise BodyScanError("The photo is larger than the 12 MB scan limit.")
        try:
            return ImageOps.exif_transpose(Image.open(BytesIO(raw))).convert("RGB")
        except (UnidentifiedImageError, OSError) as error:
            raise BodyScanError("Use a valid JPEG, PNG, or WebP photo.") from error

    @staticmethod
    def _prepare_image(image: Image.Image) -> np.ndarray:
        if image.width < 96 or image.height < 160:
            raise BodyScanError("Use a clearer full-body photo with more resolution.")
        scale = min(1.0, 512 / max(image.width, image.height))
        if scale < 1:
            image = image.resize(
                (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
                Image.Resampling.LANCZOS,
            )
        return np.asarray(image, dtype=np.float32)

    @staticmethod
    def _validate_lighting(image: np.ndarray) -> None:
        luminance = (
            image[:, :, 0] * 0.2126
            + image[:, :, 1] * 0.7152
            + image[:, :, 2] * 0.0722
        )
        mean_luminance = float(np.mean(luminance))
        lower_quartile = float(np.percentile(luminance, 25))
        upper_quartile = float(np.percentile(luminance, 75))

        if mean_luminance < 38 or upper_quartile < 52:
            raise BodyScanError(
                "The photo is too dark for a reliable body scan. Move to a well-lit "
                "area with bright, even light in front of you and retake the photo."
            )
        if mean_luminance > 247 and lower_quartile > 245:
            raise BodyScanError(
                "The photo is overexposed. Move away from harsh direct light and retake "
                "the photo with your body outline clearly visible."
            )

    @staticmethod
    def _foreground_mask(image: np.ndarray) -> tuple[np.ndarray, float]:
        height, width, _ = image.shape
        side = max(2, round(width * 0.07))
        top = max(2, round(height * 0.04))
        border = np.concatenate(
            [
                image[:, :side].reshape(-1, 3),
                image[:, -side:].reshape(-1, 3),
                image[:top].reshape(-1, 3),
            ]
        )
        background = np.median(border, axis=0)
        distance = np.linalg.norm(image - background, axis=2)
        border_distance = np.linalg.norm(border - background, axis=1)
        threshold = float(np.clip(np.percentile(border_distance, 90) * 1.8, 24, 68))
        mask = distance > threshold

        for _ in range(2):
            padded = np.pad(mask.astype(np.uint8), 1)
            neighbours = sum(
                padded[y : y + height, x : x + width]
                for y in range(3)
                for x in range(3)
            )
            mask = neighbours >= 4

        subject_distance = distance[mask]
        separation = 0.0 if subject_distance.size == 0 else float(np.mean(subject_distance) / 180)
        return mask, float(np.clip(separation, 0, 1))

    @staticmethod
    def _largest_connected_component(
        mask: np.ndarray,
        min_fraction: float = 0.025,
    ) -> np.ndarray:
        height, width = mask.shape
        visited = np.zeros_like(mask, dtype=bool)
        best: list[tuple[int, int]] = []
        for y, x in np.argwhere(mask):
            if visited[y, x]:
                continue
            visited[y, x] = True
            queue: deque[tuple[int, int]] = deque([(int(y), int(x))])
            component: list[tuple[int, int]] = []
            while queue:
                current_y, current_x = queue.popleft()
                component.append((current_y, current_x))
                for next_y in range(max(0, current_y - 1), min(height, current_y + 2)):
                    for next_x in range(max(0, current_x - 1), min(width, current_x + 2)):
                        if mask[next_y, next_x] and not visited[next_y, next_x]:
                            visited[next_y, next_x] = True
                            queue.append((next_y, next_x))
            if len(component) > len(best):
                best = component

        if len(best) < height * width * min_fraction:
            raise BodyScanError(
                "No person was detected. Stand fully visible against a plain, contrasting background."
            )
        result = np.zeros_like(mask, dtype=bool)
        points = np.asarray(best)
        result[points[:, 0], points[:, 1]] = True
        return result

    @staticmethod
    def _subject_bounds(
        mask: np.ndarray,
        min_height_fraction: float = 0.43,
    ) -> tuple[int, int, int, int]:
        height, width = mask.shape
        rows = np.where(mask.sum(axis=1) >= max(3, width * 0.018))[0]
        columns = np.where(mask.sum(axis=0) >= max(3, height * 0.012))[0]
        if rows.size == 0 or columns.size == 0:
            raise BodyScanError("No full-body silhouette was found. Use a plain, contrasting background.")

        x_min, x_max = int(columns[0]), int(columns[-1])
        y_min, y_max = int(rows[0]), int(rows[-1])
        if (y_max - y_min) < height * min_height_fraction or (x_max - x_min) < width * 0.08:
            raise BodyScanError("Move back so the full person is visible from head to feet.")
        return x_min, y_min, x_max, y_max

    @classmethod
    def _validate_person_shape(
        cls,
        mask: np.ndarray,
        bounds: tuple[int, int, int, int],
        *,
        lenient: bool = False,
    ) -> tuple[float, list[str]]:
        image_height, image_width = mask.shape
        x_min, y_min, x_max, y_max = bounds
        box_height = y_max - y_min + 1
        box_width = x_max - x_min + 1
        height_coverage = box_height / image_height
        width_coverage = box_width / image_width
        aspect = box_height / max(box_width, 1)
        fill = float(mask[y_min : y_max + 1, x_min : x_max + 1].mean())
        center = ((x_min + x_max) / 2) / image_width

        head = cls._row_extent(mask, bounds, 0.07)
        shoulder = cls._row_extent(mask, bounds, 0.22)
        waist = cls._row_extent(mask, bounds, 0.49)
        hip = cls._row_extent(mask, bounds, 0.61)
        lower = cls._row_extent(mask, bounds, 0.82)
        head_ratio = head[0] / max(shoulder[0], 1)
        lower_ratio = lower[0] / max(hip[0], 1)
        center_drift = np.mean(
            [
                abs(row_center - (x_min + x_max) / 2) / box_width
                for _, row_center in (head, shoulder, waist, hip)
            ]
        )

        min_coverage = 0.42 if lenient else 0.55
        max_center = 0.32 if lenient else 0.28
        hard_failure = (
            height_coverage < min_coverage
            or width_coverage < 0.08
            or width_coverage > 0.78
            or aspect < 1.45
            or aspect > 7.0
            or not 0.18 <= fill <= 0.90
            or not 0.22 <= head_ratio <= 0.96
            or not 0.12 <= lower_ratio <= 1.25
            or abs(center - 0.5) > max_center
            or center_drift > 0.24
        )
        if hard_failure:
            raise BodyScanError(
                "No clearly framed full-body person was detected. Use a front-facing, head-to-toe "
                "photo of one person with arms slightly away from the torso."
            )

        coverage_score = max(0.0, 1 - abs(height_coverage - 0.80) / 0.35)
        center_score = max(0.0, 1 - abs(center - 0.5) * 3.4)
        aspect_score = max(0.0, 1 - abs(aspect - 3.7) / 4.2)
        head_score = max(0.0, 1 - abs(head_ratio - 0.62) / 0.55)
        lower_score = max(0.0, 1 - abs(lower_ratio - 0.48) / 0.75)
        drift_score = max(0.0, 1 - center_drift / 0.24)
        confidence = float(
            np.clip(
                np.mean(
                    [
                        coverage_score,
                        center_score,
                        aspect_score,
                        head_score,
                        lower_score,
                        drift_score,
                    ]
                ),
                0,
                0.96,
            )
        )
        warnings: list[str] = []
        if head_ratio > 0.82:
            warnings.append("Keep hair, hats, and raised hands away from the head outline.")
        if center_drift > 0.12:
            warnings.append("Face forward and keep your shoulders and hips level.")
        return confidence, warnings

    @staticmethod
    def _row_extent(
        mask: np.ndarray,
        bounds: tuple[int, int, int, int],
        ratio: float,
    ) -> tuple[float, float]:
        x_min, y_min, x_max, y_max = bounds
        box_height = y_max - y_min + 1
        center_y = y_min + round(box_height * ratio)
        radius = max(1, round(box_height * 0.012))
        band = mask[
            max(y_min, center_y - radius) : min(y_max + 1, center_y + radius + 1),
            x_min : x_max + 1,
        ]
        active = np.where(band.any(axis=0))[0]
        if active.size == 0:
            raise BodyScanError(
                "The body outline is incomplete. Keep your whole body inside the guide."
            )
        width = float(active[-1] - active[0] + 1)
        center = float(x_min + (active[0] + active[-1]) / 2)
        return width, center

    @staticmethod
    def _width_at(
        mask: np.ndarray,
        bounds: tuple[int, int, int, int],
        ratio: float,
    ) -> float:
        x_min, y_min, x_max, y_max = bounds
        height = y_max - y_min + 1
        center_y = y_min + round(height * ratio)
        radius = max(2, round(height * 0.025))
        samples: list[int] = []
        for row in mask[max(y_min, center_y - radius) : min(y_max + 1, center_y + radius + 1)]:
            active = np.where(row[x_min : x_max + 1])[0]
            if active.size:
                splits = np.split(active, np.where(np.diff(active) > 2)[0] + 1)
                samples.append(max(len(run) for run in splits))
        if not samples:
            raise BodyScanError("The body outline is incomplete. Retake the photo against a plain background.")
        return float(np.percentile(samples, 70))

    @staticmethod
    def _quality(
        mask: np.ndarray,
        bounds: tuple[int, int, int, int],
        separation: float,
    ) -> tuple[float, list[str]]:
        image_height, image_width = mask.shape
        x_min, y_min, x_max, y_max = bounds
        coverage = (y_max - y_min + 1) / image_height
        subject_center = ((x_min + x_max) / 2) / image_width
        centered = max(0.0, 1 - abs(subject_center - 0.5) * 2.2)
        coverage_score = max(0.0, 1 - abs(coverage - 0.78) / 0.45)
        top_clearance = y_min / image_height
        bottom_clearance = (image_height - 1 - y_max) / image_height
        edge_clearance = min(1.0, min(top_clearance, bottom_clearance) / 0.025)
        quality = float(
            np.clip(
                0.10
                + 0.25 * centered
                + 0.25 * coverage_score
                + 0.25 * separation
                + 0.15 * edge_clearance,
                0,
                0.94,
            )
        )

        warnings: list[str] = []
        if y_min <= image_height * 0.02 or y_max >= image_height * 0.98:
            warnings.append("The head or feet may be clipped; leave space around the whole body.")
        if abs(subject_center - 0.5) > 0.13:
            warnings.append("Stand closer to the center of the guide.")
        if separation < 0.35:
            warnings.append("Use a plain background that contrasts with the clothing.")
        if coverage < 0.55:
            warnings.append("Move closer while keeping the full body in frame.")
        if not warnings:
            warnings.append("Image framing passed the prototype quality checks.")
        return quality, warnings
