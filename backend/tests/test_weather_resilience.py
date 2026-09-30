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
