import asyncio
import json
from datetime import UTC, datetime

import httpx
import pytest

from app.weather_service import WeatherStyleService, WeatherServiceError, _get_with_retry


def _response(status: int, payload: object = None) -> httpx.Response:
    request = httpx.Request("GET", "https://example.com/x")
    response = httpx.Response(status, request=request)
    if payload is not None:
        response._content = json.dumps(payload).encode()
        response.headers["content-type"] = "application/json"
    return response


def _status_error(status: int) -> httpx.HTTPStatusError:
    request = httpx.Request("GET", "https://example.com/x")
    try:
        httpx.Response(status, request=request).raise_for_status()
    except httpx.HTTPStatusError as error:
        return error
    raise AssertionError("expected an HTTPStatusError")


class _StubClient:
    def __init__(self, results: list) -> None:
        self._results = list(results)
        self.calls = 0

    async def get(self, url: str, params: dict | None = None) -> httpx.Response:
        self.calls += 1
        outcome = self._results[min(self.calls - 1, len(self._results) - 1)]
        if isinstance(outcome, Exception):
            raise outcome
        return outcome


def test_get_with_retry_recovers_from_rate_limit() -> None:
    async def run() -> httpx.Response:
        client = _StubClient(
            [_status_error(429), _status_error(429), _response(200)]
        )
        return await _get_with_retry(client, "https://example.com/x", attempts=3)

    client_holder: dict[str, _StubClient] = {}

    async def run_counted() -> httpx.Response:
        client = _StubClient(
            [_status_error(429), _status_error(429), _response(200)]
        )
        client_holder["client"] = client
        return await _get_with_retry(client, "https://example.com/x", attempts=3)

    response = asyncio.run(run_counted())
    assert response.status_code == 200
    assert client_holder["client"].calls == 3
    assert asyncio.run(run()).status_code == 200


def test_get_with_retry_gives_up_and_reraises() -> None:
    client = _StubClient(
        [_status_error(503), _status_error(503), _status_error(503)]
    )

    async def run() -> None:
        await _get_with_retry(client, "https://example.com/x", attempts=3)

    with pytest.raises(httpx.HTTPStatusError):
        asyncio.run(run())
    assert client.calls == 3


def test_get_with_retry_does_not_retry_client_errors() -> None:
    client = _StubClient([_status_error(404)])

    async def run() -> None:
        await _get_with_retry(client, "https://example.com/x")

    with pytest.raises(httpx.HTTPStatusError):
        asyncio.run(run())
    assert client.calls == 1


def test_wttr_for_date_picks_nearest_hour() -> None:
    today = datetime.now(UTC).date()
    payload = {
        "weather": [
            {
                "date": today.isoformat(),
                "hourly": [
                    {
                        "time": "1200",
                        "tempC": "31",
                        "FeelsLikeC": "34",
                        "weatherDesc": [{"value": "Partly cloudy"}],
                        "chanceofrain": "10",
                        "windspeedKmph": "12",
                        "uvIndex": "6",
                    },
                    {
                        "time": "1800",
                        "tempC": "29",
                        "FeelsLikeC": "32",
                        "weatherDesc": [{"value": "Light rain"}],
                        "chanceofrain": "60",
                        "windspeedKmph": "14",
                        "uvIndex": "1",
                    },
                ],
            }
        ]
    }

    async def run() -> dict:
        service = WeatherStyleService()
        client = _StubClient([_response(200, payload)])
        return await service._fetch_wttr_for_date(
            client,
            city="Manila",
            location={"latitude": 14.6, "longitude": 121.0, "name": "Manila"},
            event_date=today,
            hour=18,
            timezone="Asia/Manila",
        )

    result = asyncio.run(run())
    assert result["is_forecast"] is True
    assert result["temperature_c"] == 29.0
    assert result["condition"] == "Light rain"
    assert result["rain_probability"] == 60


def test_wttr_for_date_rejects_unknown_date() -> None:
    async def run() -> None:
        service = WeatherStyleService()
        client = _StubClient([_response(200, {"weather": []})])
        await service._fetch_wttr_for_date(
            client,
            city="Manila",
            location={"latitude": 14.6, "longitude": 121.0},
            event_date=datetime.now(UTC).date(),
            hour=18,
            timezone="Asia/Manila",
        )

    with pytest.raises(WeatherServiceError):
        asyncio.run(run())


def _normals_payload(month: int = 11, day: int = 18) -> dict:
    tag = f"{month:02d}-{day:02d}"
    times, highs, rains, winds = [], [], [], []
    for year in range(2015, 2025):
        times.append(f"{year}-{tag}")
        highs.append(31.0)
        rains.append(5.0 if year % 10 < 6 else 0.0)
        winds.append(12.0)
    times.append("2024-06-01")
    highs.append(20.0)
    rains.append(0.0)
    winds.append(5.0)
    return {
        "daily": {
            "time": times,
            "temperature_2m_max": highs,
            "precipitation_sum": rains,
            "wind_speed_10m_max": winds,
        }
    }


def test_summarize_normals_uses_same_month_day() -> None:
    summary = WeatherStyleService._summarize_normals(
        _normals_payload(), month=11, day=18
    )
    assert summary is not None
    assert summary["temperature_c"] == 31.0
    assert summary["rain_probability"] == 60
    assert summary["condition"] == "Often rainy"
    assert summary["sample_years"] == 10
    assert summary["is_forecast"] is False


def test_summarize_normals_needs_enough_samples() -> None:
    assert (
        WeatherStyleService._summarize_normals(
            {"daily": {"time": [], "temperature_2m_max": []}}, month=11, day=18
        )
        is None
    )


def test_far_date_returns_climate_normals(monkeypatch) -> None:
    from datetime import date, timedelta

    event_date = datetime.now(UTC).date() + timedelta(days=60)
    service = WeatherStyleService()

    async def fake_geocode(client, city):
        return {"latitude": 14.6, "longitude": 121.0, "name": "Manila"}

    async def fake_get(client, url, params=None, attempts=3):
        return _response(
            200, _normals_payload(month=event_date.month, day=event_date.day)
        )

    monkeypatch.setattr(service, "_geocode", fake_geocode)
    monkeypatch.setattr(
        "app.weather_service._get_with_retry", fake_get
    )

    async def run() -> dict:
        return await service.fetch_for_datetime("Manila", event_date, "18:00")

    result = asyncio.run(run())
    assert result["is_forecast"] is False
    assert result["temperature_c"] == 31.0
    assert result["rain_probability"] == 60
    assert "climate normals" in str(result.get("source", ""))


def test_far_date_falls_back_when_archive_fails(monkeypatch) -> None:
    from datetime import date, timedelta

    event_date = datetime.now(UTC).date() + timedelta(days=60)
    service = WeatherStyleService()

    async def fake_geocode(client, city):
        return {"latitude": 14.6, "longitude": 121.0, "name": "Manila"}

    async def fake_get(client, url, params=None, attempts=3):
        raise httpx.ConnectError("offline")

    monkeypatch.setattr(service, "_geocode", fake_geocode)
    monkeypatch.setattr(
        "app.weather_service._get_with_retry", fake_get
    )

    async def run() -> dict:
        return await service.fetch_for_datetime("Manila", event_date, "18:00")

    result = asyncio.run(run())
    assert result["is_forecast"] is False
    assert result["temperature_c"] is None
    assert result["condition"] == "Seasonal estimate"
