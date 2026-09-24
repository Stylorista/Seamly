import base64
import asyncio
import json
from datetime import UTC, datetime
from io import BytesIO

from fastapi.testclient import TestClient
from PIL import Image, ImageDraw

from app import main as main_module
from app.account_store import AccountStore
from app.main import app, fashion_news_service, weather_style_service
from app.schemas import (
    FashionNewsPost,
    FashionNewsResponse,
    FashionWeatherTip,
    NewsSourceStatus,
    WeatherCurrent,
    WeatherDay,
    WeatherHomeResponse,
)


client = TestClient(app)


def test_health() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert response.json()["version"] == "1.7.0"
    assert response.json()["service"] == "seamly"


def test_shop_catalog_keeps_only_exact_source_linked_images(monkeypatch) -> None:
    catalog = {
        "items": [
            {
                "id": "lazada-123",
                "title": "Linen wrap midi dress",
                "category": "Dresses",
                "marketplace": "Lazada",
                "seller": "Source seller",
                "product_url": "https://www.lazada.com.ph/products/dress-i123.html",
                "image_url": "https://my-live-02.slatic.net/p/dress.jpg",
                "image_source_url": "https://my-live-02.slatic.net/p/dress.jpg",
                "price_label": "₱1,290",
                "sizes": ["S", "M", "L"],
                "color_seasons": ["Autumn"],
            },
            {
                "id": "mismatched-image",
                "title": "Untrusted source mismatch",
                "category": "Tops",
                "marketplace": "Shopee",
                "product_url": "https://shopee.ph/item-i.1.2",
                "image_url": "https://example.com/unrelated.jpg",
                "image_source_url": "https://example.com/unrelated.jpg",
            },
        ]
    }
    monkeypatch.setenv("FASHIONTECH_SHOP_CATALOG_JSON", json.dumps(catalog))
    monkeypatch.delenv("FASHIONTECH_SHOP_CATALOG_URL", raising=False)

    response = client.get("/v1/shop/products")

    assert response.status_code == 200
    payload = response.json()
    assert payload["catalog_mode"] == "source_feed"
    assert [item["id"] for item in payload["items"]] == ["lazada-123"]
    assert payload["items"][0]["image_url"] == payload["items"][0]["image_source_url"]
    assert next(source for source in payload["sources"] if source["name"] == "Lazada")[
        "connected"
    ] is True
    assert "invalid or duplicate record" in payload["disclosure"]


def test_shop_catalog_fails_closed_without_an_approved_feed(monkeypatch) -> None:
    monkeypatch.delenv("FASHIONTECH_SHOP_CATALOG_JSON", raising=False)
    monkeypatch.delenv("FASHIONTECH_SHOP_CATALOG_URL", raising=False)
    monkeypatch.delenv("FASHIONTECH_SHOP_CATALOG_TOKEN", raising=False)

    response = client.get("/v1/shop/products")

    assert response.status_code == 200
    payload = response.json()
    assert payload["catalog_mode"] == "setup_required"
    assert payload["items"] == []
    assert all(source["connected"] is False for source in payload["sources"])


def test_account_registration_login_and_measurement_history(
    monkeypatch, tmp_path
) -> None:
    store = AccountStore(tmp_path / "accounts.db")
    monkeypatch.setattr(main_module, "account_store", store)
    registration = client.post(
        "/v1/auth/register",
        json={
            "name": "Style Tester",
            "email": "style@example.com",
            "password": "fashion123",
            "height_cm": 165,
            "location": "Manila",
        },
    )
    assert registration.status_code == 201
    registered = registration.json()
    assert registered["is_new_account"] is True
    assert registered["profile"]["height_cm"] == 165
    token = registered["token"]

    measurements = {
        "height": 165,
        "neck": 35,
        "shoulder": 40,
        "chest": 94,
        "underbust": 85,
        "waist": 77,
        "high_hip": 96,
        "hip": 103,
        "sleeve": 59,
        "wrist": 16,
        "inseam": 76,
    }
    saved = client.put(
        "/v1/account/measurements",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "measurements": measurements,
            "size_label": "L",
            "scan_confidence": 0.82,
        },
    )
    assert saved.status_code == 200
    assert saved.json()["latest_measurements"]["waist"] == 77

    login = client.post(
        "/v1/auth/login",
        json={"email": "STYLE@example.com", "password": "fashion123"},
    )
    assert login.status_code == 200
    body = login.json()
    assert body["is_new_account"] is False
    assert body["profile"]["size_label"] == "L"
    assert body["profile"]["latest_measurements"]["hip"] == 103


def test_account_rejects_duplicate_email_and_wrong_password(
    monkeypatch, tmp_path
) -> None:
    monkeypatch.setattr(main_module, "account_store", AccountStore(tmp_path / "accounts.db"))
    payload = {
        "name": "Style Tester",
        "email": "style@example.com",
        "password": "fashion123",
        "height_cm": 165,
    }
    assert client.post("/v1/auth/register", json=payload).status_code == 201
    assert client.post("/v1/auth/register", json=payload).status_code == 409
    response = client.post(
        "/v1/auth/login",
        json={"email": payload["email"], "password": "wrongpass"},
    )
    assert response.status_code == 401


def test_news_uses_open_graph_image_and_removes_duplicates() -> None:
    markup = (
        '<html><head><meta property="og:image" '
        'content="/images/story-look.jpg"></head></html>'
    )
    assert fashion_news_service._open_graph_image(
        markup, "https://publisher.example/fashion/story"
    ) == "https://publisher.example/images/story-look.jpg"

    now = datetime.now(UTC)
    posts = [
        FashionNewsPost(
            id=str(index),
            title=f"Story {index}",
            summary="Summary",
            url=f"https://publisher.example/{index}",
            image_url="https://publisher.example/images/same.jpg",
            publisher="Publisher",
            platform="Publisher RSS",
            category="all",
            published_at=now,
            like_count=0,
            comment_count=0,
        )
        for index in range(2)
    ]
    enriched = asyncio.run(
        fashion_news_service._enrich_article_images(None, posts)  # type: ignore[arg-type]
    )
    assert enriched[0].image_url is not None
    assert enriched[1].image_url is None


def test_fashion_news_feed_supports_style_categories(monkeypatch) -> None:
    async def fake_fetch(category: str, limit: int) -> FashionNewsResponse:
        return FashionNewsResponse(
            category=category,
            fetched_at=datetime.now(UTC),
            items=[
                FashionNewsPost(
                    id="story-1",
                    title="A Y2K fashion update",
                    summary="A category-specific story.",
                    url="https://example.com/story",
                    publisher="Example Fashion",
                    platform="Google News",
                    category=category,
                    published_at=datetime.now(UTC),
                    like_count=120,
                    comment_count=14,
                )
            ],
            sources=[
                NewsSourceStatus(
                    name="Google News",
                    connected=True,
                    note="Live RSS stories",
                )
            ],
        )

    monkeypatch.setattr(fashion_news_service, "fetch", fake_fetch)
    response = client.get("/v1/news/feed?category=y2k&limit=8")

    assert response.status_code == 200
    body = response.json()
    assert body["category"] == "y2k"
    assert body["items"][0]["category"] == "y2k"
    assert body["sources"][0]["connected"] is True


def test_fashion_news_feed_rejects_unknown_category() -> None:
    response = client.get("/v1/news/feed?category=unknown")
    assert response.status_code == 422


def test_home_weather_returns_current_tomorrow_and_fashion(monkeypatch) -> None:
    async def fake_weather(
        city: str,
        size_label: str | None = None,
        color_season: str | None = None,
    ) -> WeatherHomeResponse:
        return WeatherHomeResponse(
            location=city,
            region="Metro Manila",
            country="Philippines",
            timezone="Asia/Manila",
            updated_at=datetime.now(UTC),
            current=WeatherCurrent(
                temperature_c=30,
                apparent_temperature_c=35,
                humidity_percent=74,
                wind_kmh=12,
                weather_code=2,
                condition="Partly cloudy",
                is_day=True,
            ),
            tomorrow=WeatherDay(
                date="2026-09-04",
                temperature_max_c=31,
                temperature_min_c=25,
                apparent_temperature_max_c=36,
                precipitation_probability=58,
                uv_index_max=7.2,
                weather_code=80,
                condition="Rain showers",
            ),
            fashion=[
                FashionWeatherTip(
                    kind="outfit",
                    title="Airy warm-weather layers",
                    reason=f"Forecast matched for size {size_label} and {color_season}.",
                )
            ],
            source="Open-Meteo forecast",
        )

    monkeypatch.setattr(weather_style_service, "fetch", fake_weather)
    response = client.get(
        "/v1/weather/home?city=Manila&size_label=M&color_season=Autumn"
    )

    assert response.status_code == 200
    body = response.json()
    assert body["current"]["condition"] == "Partly cloudy"
    assert body["tomorrow"]["condition"] == "Rain showers"
    assert body["fashion"][0]["kind"] == "outfit"


def test_local_development_origin_is_allowed() -> None:
    response = client.options(
        "/v1/size/recommend",
        headers={
            "Origin": "http://127.0.0.1:8765",
            "Access-Control-Request-Method": "POST",
        },
    )
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "http://127.0.0.1:8765"


def test_hosted_application_origin_is_allowed() -> None:
    origin = "https://stylorista-ai.jadesalvador3257.chatgpt.site"
    response = client.options(
        "/v1/size/recommend",
        headers={
            "Origin": origin,
            "Access-Control-Request-Method": "POST",
        },
    )
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == origin


def test_size_recommendation_is_bounded() -> None:
    response = client.post(
        "/v1/size/recommend",
        json={
            "measurements": {
                "height": 165,
                "neck": 35,
                "shoulder": 40,
                "chest": 94,
                "underbust": 85,
                "waist": 77,
                "high_hip": 96,
                "hip": 103,
                "sleeve": 59,
                "wrist": 16,
                "inseam": 76,
            },
            "fit_preference": "regular",
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["recommended_size"] in {"2XS", "XS", "S", "M", "L", "XL", "2XL", "3XL", "4XL"}
    assert 0 <= body["confidence"] <= 1
    assert len(body["alternatives"]) == 3


def test_invalid_measurement_is_rejected() -> None:
    response = client.post(
        "/v1/size/recommend",
        json={"measurements": {"height": 20, "chest": 94, "waist": 77, "hip": 103}},
    )
    assert response.status_code == 422


def _silhouette_photo() -> str:
    image = Image.new("RGB", (240, 480), "#EEE7DF")
    draw = ImageDraw.Draw(image)
    draw.ellipse((96, 35, 144, 83), fill="#2B2523")
    draw.rectangle((108, 75, 132, 100), fill="#2B2523")
    draw.polygon([(82, 90), (158, 90), (146, 285), (94, 285)], fill="#2B2523")
    draw.rectangle((87, 105, 102, 285), fill="#2B2523")
    draw.rectangle((138, 105, 153, 285), fill="#2B2523")
    draw.rectangle((97, 280, 116, 445), fill="#2B2523")
    draw.rectangle((124, 280, 143, 445), fill="#2B2523")
    buffer = BytesIO()
    image.save(buffer, format="JPEG", quality=90)
    return base64.b64encode(buffer.getvalue()).decode("ascii")


def _portrait_photo() -> str:
    image = Image.new("RGB", (240, 480), "#D9D7D2")
    draw = ImageDraw.Draw(image)
    draw.ellipse((68, 48, 172, 180), fill="#C68670")
    draw.rectangle((104, 168, 136, 218), fill="#C68670")
    draw.polygon([(48, 215), (192, 215), (218, 470), (22, 470)], fill="#39495A")
    buffer = BytesIO()
    image.save(buffer, format="JPEG", quality=92)
    return base64.b64encode(buffer.getvalue()).decode("ascii")


def test_body_scan_returns_all_measurement_labels() -> None:
    response = client.post(
        "/v1/body-scan/analyze",
        json={
            "image_base64": _silhouette_photo(),
            "reference_height_cm": 165,
            "consent_confirmed": True,
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert set(body["measurements"]) == {
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
    }
    assert body["measurements"]["height"] == 165
    assert body["person_detected"] is True
    assert 0 <= body["person_confidence"] <= 1
    assert "height" in body["displayable_measurements"]
    assert 0 <= body["scan_confidence"] <= 1
    assert "Unvalidated measurement preview" in body["validation_status"]


def test_body_scan_preview_reports_readiness_for_silhouette() -> None:
    response = client.post(
        "/v1/body-scan/preview",
        json={"image_base64": _silhouette_photo(), "consent_confirmed": True},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["person_detected"] is True
    assert body["ready"] is True
    assert body["bbox"] is not None
    assert len(body["bbox"]) == 4
    assert "Ready" in body["guidance"]


def test_body_scan_preview_rejects_blank_frame() -> None:
    image = Image.new("RGB", (240, 480), "#EEE7DF")
    buffer = BytesIO()
    image.save(buffer, format="JPEG", quality=90)
    response = client.post(
        "/v1/body-scan/preview",
        json={
            "image_base64": base64.b64encode(buffer.getvalue()).decode("ascii"),
            "consent_confirmed": True,
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["ready"] is False
    assert body["person_detected"] is False


def test_body_scan_preview_requires_consent() -> None:
    response = client.post(
        "/v1/body-scan/preview",
        json={"image_base64": _silhouette_photo(), "consent_confirmed": False},
    )
    assert response.status_code == 422


def test_body_scan_rejects_photo_without_person() -> None:
    image = Image.new("RGB", (240, 480), "#EEE7DF")
    buffer = BytesIO()
    image.save(buffer, format="JPEG", quality=90)
    response = client.post(
        "/v1/body-scan/analyze",
        json={
            "image_base64": base64.b64encode(buffer.getvalue()).decode("ascii"),
            "reference_height_cm": 165,
            "consent_confirmed": True,
        },
    )

    assert response.status_code == 422
    assert "No person was detected" in response.json()["detail"]


def test_body_scan_rejects_photo_that_is_too_dark() -> None:
    image = Image.new("RGB", (240, 480), "#111111")
    buffer = BytesIO()
    image.save(buffer, format="JPEG", quality=90)
    response = client.post(
        "/v1/body-scan/analyze",
        json={
            "image_base64": base64.b64encode(buffer.getvalue()).decode("ascii"),
            "reference_height_cm": 165,
            "consent_confirmed": True,
        },
    )

    assert response.status_code == 422
    assert "too dark" in response.json()["detail"]
    assert "well-lit area" in response.json()["detail"]


def test_body_scan_rejects_tall_non_human_object() -> None:
    image = Image.new("RGB", (240, 480), "#EEE7DF")
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((82, 35, 158, 445), radius=8, fill="#2B2523")
    buffer = BytesIO()
    image.save(buffer, format="JPEG", quality=90)
    response = client.post(
        "/v1/body-scan/analyze",
        json={
            "image_base64": base64.b64encode(buffer.getvalue()).decode("ascii"),
            "reference_height_cm": 165,
            "consent_confirmed": True,
        },
    )

    assert response.status_code == 422
    assert "full-body person" in response.json()["detail"]


def test_body_scan_measurements_are_deterministic() -> None:
    payload = {
        "image_base64": _silhouette_photo(),
        "reference_height_cm": 165,
        "consent_confirmed": True,
    }

    first = client.post("/v1/body-scan/analyze", json=payload)
    second = client.post("/v1/body-scan/analyze", json=payload)

    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["measurements"] == second.json()["measurements"]


def test_body_scan_requires_photo_consent() -> None:
    response = client.post(
        "/v1/body-scan/analyze",
        json={
            "image_base64": _silhouette_photo(),
            "reference_height_cm": 165,
            "consent_confirmed": False,
        },
    )
    assert response.status_code == 422


def test_profile_photo_returns_accessories_and_color_direction() -> None:
    response = client.post(
        "/v1/profile/analyze",
        json={
            "image_base64": _portrait_photo(),
            "consent_confirmed": True,
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["color_season"] in {"Spring", "Summer", "Autumn", "Winter"}
    assert len(body["accessories"]) == 4
    assert len(body["palette"]) >= 4
    assert 0 <= body["confidence"] <= 1
    assert 0 <= body["lighting_quality"] <= 1
    assert body["quality_warnings"]
    assert body["model_version"] == "appearance-color-calibrated-demo-0.2.0"
    assert "not identity" in body["disclaimer"]


def test_profile_color_analysis_rejects_dark_photo() -> None:
    image = Image.new("RGB", (240, 480), "#151515")
    buffer = BytesIO()
    image.save(buffer, format="JPEG", quality=90)
    response = client.post(
        "/v1/profile/analyze",
        json={
            "image_base64": base64.b64encode(buffer.getvalue()).decode("ascii"),
            "consent_confirmed": True,
        },
    )

    assert response.status_code == 422
    assert "too dark" in response.json()["detail"]


def test_profile_photo_requires_consent() -> None:
    response = client.post(
        "/v1/profile/analyze",
        json={
            "image_base64": _silhouette_photo(),
            "consent_confirmed": False,
        },
    )
    assert response.status_code == 422


def test_color_analysis_returns_palette() -> None:
    response = client.post(
        "/v1/color/analyze",
        json={"skin_hex": "#C98F70", "hair_hex": "#3D2A22", "eye_hex": "#65483A"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["season"] in {"Spring", "Summer", "Autumn", "Winter"}
    assert len(body["palette"]) >= 4


def test_tropical_season_uses_wet_dry_cycle() -> None:
    response = client.post(
        "/v1/style/recommend",
        json={
            "climate": "tropical",
            "hemisphere": "northern",
            "month": 8,
            "occasion": "work",
            "style": "classic",
            "color_season": "Autumn",
            "size_label": "M",
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["current_season"] == "Wet"
    assert body["pieces"]
    assert body["palette"]
