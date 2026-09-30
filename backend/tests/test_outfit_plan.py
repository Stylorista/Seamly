from datetime import UTC, datetime, timedelta

from fastapi.testclient import TestClient

from app import main as main_module
from app.main import app


client = TestClient(app)


def _moment(**overrides):
    base = {
        "location": {"name": "Manila", "admin1": "Metro Manila", "country": "Philippines"},
        "timezone": "Asia/Manila",
        "temperature_c": 31.0,
        "feels_like_c": 34.0,
        "condition": "Partly cloudy",
        "weather_code": 2,
        "rain_probability": 10,
        "wind_kmh": 12.0,
        "uv_index_max": 7.0,
        "hour": 16,
        "is_forecast": True,
    }
    base.update(overrides)
    return base


def _patch_moment(monkeypatch, **overrides):
    async def fake(city, event_date, event_time):
        return _moment(**overrides)

    monkeypatch.setattr(
        main_module.weather_style_service, "fetch_for_datetime", fake
    )


def _payload(**overrides):
    body = {
        "event_text": "cocktail party",
        "city": "Manila",
        "event_date": (datetime.now(UTC).date() + timedelta(days=3)).isoformat(),
        "event_time": "16:00",
        "style": "classic",
    }
    body.update(overrides)
    return body


def test_outfit_plan_wedding_heat(monkeypatch) -> None:
    _patch_moment(monkeypatch)
    response = client.post("/v1/outfits/plan", json=_payload(event_text="garden wedding"))
    assert response.status_code == 200
    body = response.json()
    assert body["occasion"] == "event"
    assert body["style_used"] == "classic"
    assert body["weather"]["is_forecast"] is True
    assert body["pieces"], "expected outfit pieces"
    assert any("heat" in reason or "34" in reason for reason in body["reasons"])
    assert "Garden Wedding" in body["title"]


def test_outfit_plan_rain_adjustment(monkeypatch) -> None:
    _patch_moment(monkeypatch, rain_probability=70, condition="Rain")
    response = client.post("/v1/outfits/plan", json=_payload(event_text="music festival"))
    assert response.status_code == 200
    body = response.json()
    assert body["occasion"] == "travel"
    assert any("rain" in reason.lower() for reason in body["reasons"])


def test_outfit_plan_beyond_window_is_estimate(monkeypatch) -> None:
    _patch_moment(
        monkeypatch,
        temperature_c=None,
        feels_like_c=None,
        condition="Seasonal estimate",
        rain_probability=None,
        wind_kmh=None,
        uv_index_max=None,
        is_forecast=False,
    )
    far = (datetime.now(UTC).date() + timedelta(days=60)).isoformat()
    response = client.post("/v1/outfits/plan", json=_payload(event_date=far))
    assert response.status_code == 200
    body = response.json()
    assert body["weather"]["is_forecast"] is False
    assert "seasonal estimate" in body["reasons"][0].lower()
    assert body["confidence"] < 0.7


def test_outfit_plan_unknown_event_falls_back(monkeypatch) -> None:
    _patch_moment(monkeypatch)
    response = client.post("/v1/outfits/plan", json=_payload(event_text="stargazing with friends"))
    assert response.status_code == 200
    assert response.json()["occasion"] == "everyday"


def test_outfit_plan_rejects_past_date(monkeypatch) -> None:
    _patch_moment(monkeypatch)
    past = (datetime.now(UTC).date() - timedelta(days=1)).isoformat()
    response = client.post("/v1/outfits/plan", json=_payload(event_date=past))
    assert response.status_code == 422


def test_style_free_text_mapping() -> None:
    assert main_module.engine.canonicalize_style("elegant evening") == "classic"
    assert main_module.engine.canonicalize_style("sporty") == "street"
    assert main_module.engine.canonicalize_style("cute soft look") == "romantic"
    assert main_module.engine.canonicalize_style(None) == "minimal"
    assert main_module.engine.canonicalize_occasion("Office Holiday Party") == "work"
    assert main_module.engine.canonicalize_occasion("Funeral") == "event"
    assert main_module.engine.canonicalize_occasion("Beach Party") == "travel"


def test_outfit_plan_normals_estimate_has_numbers(monkeypatch) -> None:
    async def fake_moment(city, event_date, event_time):
        return {
            "location": {"name": "Manila"},
            "timezone": "Asia/Manila",
            "temperature_c": 30.5,
            "feels_like_c": 33.0,
            "condition": "Often rainy",
            "weather_code": None,
            "rain_probability": 60,
            "wind_kmh": 12.0,
            "uv_index_max": None,
            "hour": 18,
            "is_forecast": False,
            "source": "climate normals (ERA5)",
            "sample_years": 10,
        }

    monkeypatch.setattr(
        main_module.weather_style_service, "fetch_for_datetime", fake_moment
    )
    far = (datetime.now(UTC).date() + timedelta(days=60)).isoformat()
    response = client.post(
        "/v1/outfits/plan", json=_payload(event_date=far, event_text="garden wedding")
    )
    assert response.status_code == 200
    body = response.json()
    assert body["weather"]["temperature_c"] == 30.5
    assert "averages" in body["reasons"][0]
    assert "climate averages" in body["disclaimer"]
    assert body["confidence"] == 0.62
