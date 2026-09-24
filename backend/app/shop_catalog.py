from __future__ import annotations

import json
import os
from datetime import UTC, datetime
from urllib.parse import urlsplit

import httpx
from pydantic import ValidationError

from .schemas import ShopProduct, ShopProductsResponse, ShopSourceStatus


_MARKETPLACE_HOSTS = {
    "Shopee": {
        "products": ("shopee.ph",),
        "images": ("susercontent.com", "shopee.ph", "shopeemobile.com"),
    },
    "Lazada": {
        "products": ("lazada.com.ph",),
        "images": ("slatic.net", "lazada.com.ph"),
    },
    "Temu": {
        "products": ("temu.com",),
        "images": ("kwcdn.com", "temu.com"),
    },
}


class ShopCatalogService:
    """Load normalized products from an operator-approved marketplace feed.

    The service deliberately has no page scraper. A product is only returned when
    the product link and its image link match the declared marketplace's domains.
    """

    async def fetch(self, *, limit: int = 40) -> ShopProductsResponse:
        payload, configured, load_error = await self._load_payload()
        candidates = payload.get("items", payload) if isinstance(payload, dict) else payload
        if not isinstance(candidates, list):
            candidates = []

        items: list[ShopProduct] = []
        seen_products: set[str] = set()
        seen_images: set[str] = set()
        rejected = 0
        for candidate in candidates:
            try:
                item = ShopProduct.model_validate(candidate)
            except (ValidationError, TypeError):
                rejected += 1
                continue
            if not self._source_matches(item):
                rejected += 1
                continue
            product_key = self._url_key(item.product_url)
            image_key = self._url_key(item.image_url)
            if product_key in seen_products or image_key in seen_images:
                rejected += 1
                continue
            seen_products.add(product_key)
            seen_images.add(image_key)
            items.append(item)
            if len(items) >= limit:
                break

        statuses = []
        for marketplace in _MARKETPLACE_HOSTS:
            count = sum(item.marketplace == marketplace for item in items)
            if count:
                note = f"{count} exact source-linked listing{'s' if count != 1 else ''}"
            elif load_error:
                note = "The approved product feed is temporarily unavailable"
            elif configured:
                note = "Connected feed returned no valid listings from this source"
            else:
                note = "Connect an approved seller or affiliate product feed"
            statuses.append(
                ShopSourceStatus(
                    name=marketplace,
                    connected=count > 0,
                    item_count=count,
                    note=note,
                )
            )

        rejected_note = (
            f" {rejected} invalid or duplicate record{'s were' if rejected != 1 else ' was'} hidden."
            if rejected
            else ""
        )
        disclosure = (
            "Every photo is supplied with the exact product record and opens that "
            "listing; Seamly does not substitute unrelated product images."
            f"{rejected_note}"
        )
        return ShopProductsResponse(
            fetched_at=datetime.now(UTC),
            items=items,
            sources=statuses,
            catalog_mode="source_feed" if items else "setup_required",
            disclosure=disclosure,
        )

    async def _load_payload(self) -> tuple[object, bool, bool]:
        inline_catalog = os.getenv("FASHIONTECH_SHOP_CATALOG_JSON", "").strip()
        if inline_catalog:
            try:
                return json.loads(inline_catalog), True, False
            except json.JSONDecodeError:
                return [], True, True

        feed_url = os.getenv("FASHIONTECH_SHOP_CATALOG_URL", "").strip()
        if not self._safe_feed_url(feed_url):
            return [], bool(feed_url), bool(feed_url)
        headers = {"User-Agent": "Seamly/1.4 product-catalog"}
        bearer_token = os.getenv("FASHIONTECH_SHOP_CATALOG_TOKEN", "").strip()
        if bearer_token:
            headers["Authorization"] = f"Bearer {bearer_token}"
        try:
            async with httpx.AsyncClient(
                timeout=httpx.Timeout(10.0),
                follow_redirects=False,
                headers=headers,
            ) as client:
                response = await client.get(feed_url)
                response.raise_for_status()
                return response.json(), True, False
        except (httpx.HTTPError, ValueError):
            return [], True, True

    @classmethod
    def _source_matches(cls, item: ShopProduct) -> bool:
        rules = _MARKETPLACE_HOSTS[item.marketplace]
        product_host = cls._https_host(item.product_url)
        image_host = cls._https_host(item.image_url)
        source_host = cls._https_host(item.image_source_url)
        if not product_host or not image_host or not source_host:
            return False
        return (
            cls._matches_host(product_host, rules["products"])
            and cls._matches_host(image_host, rules["images"])
            and cls._matches_host(source_host, rules["images"])
            and cls._url_key(item.image_url) == cls._url_key(item.image_source_url)
        )

    @staticmethod
    def _safe_feed_url(value: str) -> bool:
        if not value:
            return False
        parsed = urlsplit(value)
        host = (parsed.hostname or "").lower()
        return parsed.scheme == "https" and host not in {
            "localhost",
            "127.0.0.1",
            "0.0.0.0",
            "::1",
        }

    @staticmethod
    def _https_host(value: str) -> str | None:
        parsed = urlsplit(value.strip())
        if parsed.scheme != "https" or parsed.username or parsed.password:
            return None
        return (parsed.hostname or "").lower() or None

    @staticmethod
    def _matches_host(host: str, allowed: tuple[str, ...]) -> bool:
        return any(host == suffix or host.endswith(f".{suffix}") for suffix in allowed)

    @staticmethod
    def _url_key(value: str) -> str:
        parsed = urlsplit(value.strip())
        return f"{parsed.scheme.lower()}://{parsed.netloc.lower()}{parsed.path.rstrip('/')}"
