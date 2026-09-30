from __future__ import annotations

import os

import httpx


def build_inspiration_query(
    *, style: str, pieces: list[str], occasion: str
) -> str:
    """Build a short human-style photo search from the planned outfit."""
    words: list[str] = []
    if style and style != "minimal":
        words.append(style)
    for piece in pieces[:2]:
        words.extend(piece.split()[:3])
    words.append("outfit")
    if occasion == "work":
        words.append("office")
    elif occasion == "travel":
        words.append("street style")
    query = " ".join(words).strip()
    return query or "fashion outfit"


class OutfitImageService:
    """Inspirational (not for sale) outfit photos via the Pexels API.

    The key lives in PEXELS_API_KEY. Without it the planner simply
    returns no photos; the outfit itself never fails because of images.
    """

    def __init__(self, api_key: str | None = None) -> None:
        self._api_key = (api_key if api_key is not None else os.getenv("PEXELS_API_KEY", "")).strip()
        self._cache: dict[str, list[dict[str, str]]] = {}

    @property
    def configured(self) -> bool:
        return bool(self._api_key)

    async def fetch_images(self, query: str, per_page: int = 3) -> list[dict[str, str]]:
        query = " ".join(query.split())
        if not query or not self.configured:
            return []
        cache_key = f"{query.lower()}|{per_page}"
        if cache_key in self._cache:
            return self._cache[cache_key]
        try:
            async with httpx.AsyncClient(
                timeout=httpx.Timeout(15.0, connect=8.0),
                follow_redirects=True,
                headers={
                    "Authorization": self._api_key,
                    "User-Agent": "Seamly/1.9 outfit-inspiration",
                },
            ) as client:
                images = await self._search(client, query, per_page)
        except (httpx.HTTPError, ValueError, KeyError, TypeError):
            return []
        self._cache[cache_key] = images
        return images

    async def _search(
        self, client: httpx.AsyncClient, query: str, per_page: int
    ) -> list[dict[str, str]]:
        from .weather_service import _get_with_retry

        response = await _get_with_retry(
            client,
            "https://api.pexels.com/v1/search",
            params={
                "query": query,
                "per_page": max(1, min(per_page, 6)),
                "orientation": "portrait",
                "size": "medium",
            },
            attempts=2,
        )
        payload = response.json()
        photos = payload.get("photos", [])
        images: list[dict[str, str]] = []
        if not isinstance(photos, list):
            return images
        for photo in photos:
            if not isinstance(photo, dict):
                continue
            src = photo.get("src", {})
            url = src.get("medium", "") if isinstance(src, dict) else ""
            if not url:
                continue
            images.append(
                {
                    "image_url": str(url),
                    "photographer": str(photo.get("photographer", "Pexels")),
                    "photographer_url": str(photo.get("photographer_url", "https://www.pexels.com")),
                    "alt": str(photo.get("alt", "Outfit inspiration"))[:140],
                }
            )
        return images
