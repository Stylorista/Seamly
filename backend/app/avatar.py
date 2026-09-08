"""Validate private account pictures and discard original photo metadata."""

import base64
import binascii
from io import BytesIO

from PIL import Image, ImageOps, UnidentifiedImageError


def normalize_avatar(encoded: str) -> str:
    try:
        raw = base64.b64decode(encoded, validate=True)
        if len(raw) > 2 * 1024 * 1024:
            raise ValueError("Choose a profile picture smaller than 2 MB.")
        with Image.open(BytesIO(raw)) as image:
            if image.format not in {"JPEG", "PNG", "WEBP"}:
                raise ValueError("Choose a JPEG, PNG, or WebP profile picture.")
            if image.width * image.height > 16_000_000:
                raise ValueError("Choose a smaller profile picture (up to 16 megapixels).")
            image = ImageOps.exif_transpose(image)
            image.thumbnail((512, 512), Image.Resampling.LANCZOS)
            rgba = image.convert("RGBA")
            clean = Image.new("RGB", rgba.size, "white")
            clean.paste(rgba, mask=rgba.getchannel("A"))
            output = BytesIO()
            clean.save(output, format="JPEG", quality=85)
        return base64.b64encode(output.getvalue()).decode("ascii")
    except (binascii.Error, UnidentifiedImageError, OSError, Image.DecompressionBombError) as error:
        raise ValueError("Choose a valid JPEG, PNG, or WebP profile picture.") from error
