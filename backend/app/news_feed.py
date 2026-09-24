from __future__ import annotations

import asyncio
import hashlib
import html
import os
import re
from datetime import UTC, datetime
from email.utils import parsedate_to_datetime
from urllib.parse import urljoin, urlsplit
from xml.etree import ElementTree

import httpx

from .schemas import FashionNewsPost, FashionNewsResponse, NewsSourceStatus


_CATEGORY_QUERIES = {
    "all": "fashion trends",
    "y2k": "Y2K fashion",
    "gothic": "gothic fashion",
    "alternative": "alternative fashion",
    "formal": "formal fashion",
    "casual": "casual fashion",
    "wedding": "wedding fashion",
    "streetwear": "streetwear fashion",
    "vintage": "vintage fashion",
}

_PUBLISHER_FEEDS = (
    ("Vogue", "https://www.vogue.com/feed/rss"),
    ("Fashionista", "https://fashionista.com/.rss/full/"),
    ("ELLE", "https://www.elle.com/rss/fashion.xml"),
)


class FashionNewsService:
    async def fetch(self, category: str, limit: int = 16) -> FashionNewsResponse:
        normalized = category.strip().lower()
        query = _CATEGORY_QUERIES.get(normalized, _CATEGORY_QUERIES["all"])
        reddit_token = os.getenv("REDDIT_ACCESS_TOKEN", "").strip()

        async with httpx.AsyncClient(
            timeout=httpx.Timeout(8.0),
            follow_redirects=True,
            headers={"User-Agent": "Seamly/1.3 fashion-news-feed"},
        ) as client:
            tasks = [
                self._fetch_gdelt(client, query, normalized, limit),
                self._fetch_google_news(client, query, normalized, limit),
                self._fetch_publisher_feeds(client, normalized, limit),
            ]
            if reddit_token:
                tasks.append(
                    self._fetch_reddit(
                        client, query, normalized, reddit_token, limit
                    )
                )
            results = await asyncio.gather(*tasks, return_exceptions=True)
            gdelt_items = self._successful_items(results[0])
            google_items = self._successful_items(results[1])
            publisher_items = self._successful_items(results[2])
            reddit_items = (
                self._successful_items(results[3])
                if reddit_token and len(results) > 3
                else []
            )
            merged = self._merge(
                publisher_items,
                gdelt_items,
                google_items,
                reddit_items,
                limit=limit,
            )
            merged = await self._enrich_article_images(client, merged)

        return FashionNewsResponse(
            category=normalized,
            fetched_at=datetime.now(UTC),
            items=merged,
            sources=[
                NewsSourceStatus(
                    name="Google News",
                    connected=bool(google_items),
                    note=(
                        "Live RSS stories"
                        if google_items
                        else "Temporarily unavailable; pull to retry"
                    ),
                ),
                NewsSourceStatus(
                    name="Fashion publishers",
                    connected=bool(publisher_items),
                    note=(
                        "Live Vogue, Fashionista, and ELLE feeds"
                        if publisher_items
                        else "Publisher feeds are temporarily unavailable"
                    ),
                ),
                NewsSourceStatus(
                    name="Global publishers",
                    connected=bool(gdelt_items),
                    note=(
                        "Live via GDELT"
                        if gdelt_items
                        else "GDELT is temporarily unavailable"
                    ),
                ),
                NewsSourceStatus(
                    name="Reddit",
                    connected=bool(reddit_items),
                    note=(
                        "Connected with approved OAuth access"
                        if reddit_items
                        else "Requires REDDIT_ACCESS_TOKEN and approved API access"
                    ),
                ),
                NewsSourceStatus(
                    name="Facebook + Instagram",
                    connected=False,
                    note="Requires approved Meta app access and eligible accounts",
                ),
            ],
        )

    async def _enrich_article_images(
        self,
        client: httpx.AsyncClient,
        posts: list[FashionNewsPost],
    ) -> list[FashionNewsPost]:
        """Fill missing images from each publisher page and prevent repeats."""

        semaphore = asyncio.Semaphore(8)

        async def enrich(post: FashionNewsPost) -> FashionNewsPost:
            if post.image_url:
                return post
            async with semaphore:
                try:
                    response = await client.get(post.url)
                    response.raise_for_status()
                except httpx.HTTPError:
                    return post
            image_url = self._open_graph_image(
                response.text[:750_000], str(response.url)
            )
            resolved_url = str(response.url)
            update: dict[str, str | None] = {"image_url": image_url}
            if "news.google.com" not in urlsplit(resolved_url).netloc:
                update["url"] = resolved_url
            return post.model_copy(update=update)

        enriched = await asyncio.gather(*(enrich(post) for post in posts))
        unique_images: set[str] = set()
        deduplicated: list[FashionNewsPost] = []
        for post in enriched:
            image_url = post.image_url
            if image_url:
                parts = urlsplit(image_url)
                image_key = f"{parts.netloc.lower()}{parts.path.rstrip('/').lower()}"
                if image_key in unique_images:
                    post = post.model_copy(update={"image_url": None})
                else:
                    unique_images.add(image_key)
            deduplicated.append(post)
        return deduplicated

    @classmethod
    def _open_graph_image(cls, markup: str, page_url: str) -> str | None:
        for tag in re.findall(r"<meta\b[^>]*>", markup, flags=re.IGNORECASE):
            attributes = {
                key.lower(): html.unescape(value)
                for key, _, value in re.findall(
                    r"([\w:-]+)\s*=\s*([\"'])(.*?)\2",
                    tag,
                    flags=re.IGNORECASE | re.DOTALL,
                )
            }
            image_kind = (attributes.get("property") or attributes.get("name") or "").lower()
            if image_kind not in {"og:image", "og:image:url", "twitter:image"}:
                continue
            image_url = urljoin(page_url, attributes.get("content", "").strip())
            safe_image = cls._safe_image(image_url)
            if safe_image:
                return safe_image
        return None

    async def _fetch_publisher_feeds(
        self,
        client: httpx.AsyncClient,
        category: str,
        limit: int,
    ) -> list[FashionNewsPost]:
        responses = await asyncio.gather(
            *(client.get(url) for _, url in _PUBLISHER_FEEDS),
            return_exceptions=True,
        )
        posts: list[FashionNewsPost] = []
        search_terms = (
            set()
            if category == "all"
            else set(_CATEGORY_QUERIES.get(category, "fashion").lower().split())
        )
        search_terms.discard("fashion")
        for (publisher, _), response in zip(_PUBLISHER_FEEDS, responses):
            if not isinstance(response, httpx.Response) or response.is_error:
                continue
            try:
                root = ElementTree.fromstring(response.content)
            except ElementTree.ParseError:
                continue
            for item in root.findall(".//item"):
                title = (item.findtext("title") or "").strip()
                url = (item.findtext("link") or "").strip()
                raw_summary = item.findtext("description") or ""
                searchable = f"{title} {self._clean_summary(raw_summary)}".lower()
                if search_terms and not any(term in searchable for term in search_terms):
                    continue
                if not title or not url:
                    continue
                posts.append(
                    self._post(
                        title=title,
                        summary=self._clean_summary(raw_summary)
                        or f"Read the latest fashion story from {publisher}.",
                        url=url,
                        image_url=self._rss_image(item),
                        publisher=publisher,
                        platform="Publisher RSS",
                        category=category,
                        published_at=self._parse_rss_date(item.findtext("pubDate")),
                    )
                )
                if len(posts) >= limit:
                    return posts
        return posts

    async def _fetch_gdelt(
        self,
        client: httpx.AsyncClient,
        query: str,
        category: str,
        limit: int,
    ) -> list[FashionNewsPost]:
        response = await client.get(
            "https://api.gdeltproject.org/api/v2/doc/doc",
            params={
                "query": f'"{query}"',
                "mode": "artlist",
                "maxrecords": min(limit, 50),
                "timespan": "1month",
                "sort": "datedesc",
                "format": "json",
            },
        )
        response.raise_for_status()
        payload = response.json()
        posts: list[FashionNewsPost] = []
        for article in payload.get("articles", []):
            url = str(article.get("url", "")).strip()
            title = str(article.get("title", "")).strip()
            if not url or not title:
                continue
            publisher = str(article.get("domain", "Global publisher")).strip()
            posts.append(
                self._post(
                    title=title,
                    summary=f"Explore this {category} fashion story from {publisher}.",
                    url=url,
                    image_url=self._safe_image(article.get("socialimage")),
                    publisher=publisher,
                    platform="Global News",
                    category=category,
                    published_at=self._parse_gdelt_date(article.get("seendate")),
                )
            )
        return posts

    async def _fetch_google_news(
        self,
        client: httpx.AsyncClient,
        query: str,
        category: str,
        limit: int,
    ) -> list[FashionNewsPost]:
        response = await client.get(
            "https://news.google.com/rss/search",
            params={
                "q": query,
                "hl": "en-PH",
                "gl": "PH",
                "ceid": "PH:en",
            },
        )
        response.raise_for_status()
        root = ElementTree.fromstring(response.content)
        posts: list[FashionNewsPost] = []
        for item in root.findall("./channel/item")[:limit]:
            title = (item.findtext("title") or "").strip()
            url = (item.findtext("link") or "").strip()
            if not title or not url:
                continue
            source_node = item.find("source")
            publisher = (
                (source_node.text or "Google News").strip()
                if source_node is not None
                else "Google News"
            )
            summary = self._clean_summary(item.findtext("description") or "")
            posts.append(
                self._post(
                    title=title,
                    summary=summary
                    or f"Open this {category} fashion story in Google News.",
                    url=url,
                    image_url=None,
                    publisher=publisher,
                    platform="Google News",
                    category=category,
                    published_at=self._parse_rss_date(item.findtext("pubDate")),
                )
            )
        return posts

    async def _fetch_reddit(
        self,
        client: httpx.AsyncClient,
        query: str,
        category: str,
        token: str,
        limit: int,
    ) -> list[FashionNewsPost]:
        response = await client.get(
            "https://oauth.reddit.com/search",
            params={"q": query, "sort": "new", "limit": min(limit, 25)},
            headers={"Authorization": f"Bearer {token}"},
        )
        response.raise_for_status()
        posts: list[FashionNewsPost] = []
        for child in response.json().get("data", {}).get("children", []):
            data = child.get("data", {})
            permalink = str(data.get("permalink", "")).strip()
            title = str(data.get("title", "")).strip()
            if not permalink or not title:
                continue
            preview = data.get("preview", {}).get("images", [])
            image_url = None
            if preview:
                image_url = html.unescape(
                    str(preview[0].get("source", {}).get("url", ""))
                )
            posts.append(
                self._post(
                    title=title,
                    summary=self._clean_summary(str(data.get("selftext", "")))
                    or "Join this fashion conversation on Reddit.",
                    url=f"https://www.reddit.com{permalink}",
                    image_url=self._safe_image(image_url),
                    publisher=f"r/{data.get('subreddit', 'fashion')}",
                    platform="Reddit",
                    category=category,
                    published_at=datetime.fromtimestamp(
                        float(data.get("created_utc", 0)), tz=UTC
                    ),
                    like_count=max(int(data.get("score", 0)), 0),
                    comment_count=max(int(data.get("num_comments", 0)), 0),
                )
            )
        return posts

    def _post(
        self,
        *,
        title: str,
        summary: str,
        url: str,
        image_url: str | None,
        publisher: str,
        platform: str,
        category: str,
        published_at: datetime,
        like_count: int = 0,
        comment_count: int = 0,
    ) -> FashionNewsPost:
        digest = hashlib.sha256(url.encode("utf-8")).hexdigest()
        return FashionNewsPost(
            id=digest[:16],
            title=title[:220],
            summary=summary[:360],
            url=url,
            image_url=image_url,
            publisher=publisher[:80],
            platform=platform,
            category=category,
            published_at=published_at,
            like_count=like_count,
            comment_count=comment_count,
        )

    def _merge(
        self,
        *groups: list[FashionNewsPost],
        limit: int,
    ) -> list[FashionNewsPost]:
        unique: dict[str, FashionNewsPost] = {}
        for index in range(max((len(group) for group in groups), default=0)):
            for group in groups:
                if index >= len(group):
                    continue
                post = group[index]
                key = re.sub(r"\W+", "", post.title.lower())[:120]
                unique.setdefault(key, post)
                if len(unique) >= limit:
                    return list(unique.values())
        return list(unique.values())

    @staticmethod
    def _successful_items(result: object) -> list[FashionNewsPost]:
        return result if isinstance(result, list) else []

    @staticmethod
    def _clean_summary(value: str) -> str:
        no_tags = re.sub(r"<[^>]+>", " ", html.unescape(value))
        return re.sub(r"\s+", " ", no_tags).strip()

    @staticmethod
    def _safe_image(value: object) -> str | None:
        image_url = str(value or "").strip()
        return image_url if image_url.startswith("https://") else None

    @classmethod
    def _rss_image(cls, item: ElementTree.Element) -> str | None:
        for child in item:
            local_name = child.tag.rsplit("}", 1)[-1]
            if local_name in {"content", "thumbnail", "enclosure"}:
                image = cls._safe_image(child.attrib.get("url"))
                if image:
                    return image
        markup = " ".join(
            value or ""
            for value in (
                item.findtext("description"),
                next(
                    (
                        child.text
                        for child in item
                        if child.tag.rsplit("}", 1)[-1] == "encoded"
                    ),
                    "",
                ),
            )
        )
        match = re.search(r'<img[^>]+src=["\'](https://[^"\']+)', markup)
        return cls._safe_image(html.unescape(match.group(1))) if match else None

    @staticmethod
    def _parse_gdelt_date(value: object) -> datetime:
        try:
            return datetime.strptime(str(value), "%Y%m%dT%H%M%SZ").replace(tzinfo=UTC)
        except ValueError:
            return datetime.now(UTC)

    @staticmethod
    def _parse_rss_date(value: str | None) -> datetime:
        try:
            parsed = parsedate_to_datetime(value or "")
            return parsed.astimezone(UTC)
        except (TypeError, ValueError):
            return datetime.now(UTC)
