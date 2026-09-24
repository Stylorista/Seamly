from __future__ import annotations

from datetime import UTC, datetime, timedelta

import httpx

from .schemas import (
    FashionWeatherTip,
    WeatherCurrent,
    WeatherDay,
    WeatherHomeResponse,
)


class WeatherServiceError(ValueError):
    pass


class WeatherStyleService:
    def __init__(self) -> None:
        self._cache: dict[str, tuple[datetime, WeatherHomeResponse]] = {}

    async def fetch(
        self,
        city: str,
        size_label: str | None = None,
        color_season: str | None = None,
    ) -> WeatherHomeResponse:
        normalized_city = city.strip()
        if len(normalized_city) < 2:
            raise WeatherServiceError("Enter at least two letters for the city.")

        cache_key = f"{normalized_city.lower()}|{size_label}|{color_season}"
        cached = self._cache.get(cache_key)
        if cached and datetime.now(UTC) - cached[0] < timedelta(minutes=10):
            return cached[1]

        async with httpx.AsyncClient(
            timeout=httpx.Timeout(8.0),
            follow_redirects=True,
            headers={"User-Agent": "Seamly/1.3 weather-style"},
        ) as client:
            location = await self._geocode(client, normalized_city)
            forecast = await self._forecast(
                client,
                latitude=float(location["latitude"]),
                longitude=float(location["longitude"]),
            )

        response = self._build_response(
            location=location,
            forecast=forecast,
            size_label=size_label,
            color_season=color_season,
        )
        self._cache[cache_key] = (datetime.now(UTC), response)
        return response

    async def _geocode(
        self,
        client: httpx.AsyncClient,
        city: str,
    ) -> dict[str, object]:
        response = await client.get(
            "https://geocoding-api.open-meteo.com/v1/search",
            params={"name": city, "count": 1, "language": "en", "format": "json"},
        )
        response.raise_for_status()
        results = response.json().get("results", [])
        if not results:
            raise WeatherServiceError(
                f'No weather location matched "{city}". Try adding the country.'
            )
        return results[0]

    async def _forecast(
        self,
        client: httpx.AsyncClient,
        *,
        latitude: float,
        longitude: float,
    ) -> dict[str, object]:
        response = await client.get(
            "https://api.open-meteo.com/v1/forecast",
            params={
                "latitude": latitude,
                "longitude": longitude,
                "current": (
                    "temperature_2m,apparent_temperature,relative_humidity_2m,"
                    "weather_code,wind_speed_10m,is_day"
                ),
                "daily": (
                    "weather_code,temperature_2m_max,temperature_2m_min,"
                    "apparent_temperature_max,precipitation_probability_max,"
                    "uv_index_max"
                ),
                "timezone": "auto",
                "forecast_days": 2,
            },
        )
        response.raise_for_status()
        return response.json()

    def _build_response(
        self,
        *,
        location: dict[str, object],
        forecast: dict[str, object],
        size_label: str | None,
        color_season: str | None,
    ) -> WeatherHomeResponse:
        current = forecast.get("current", {})
        daily = forecast.get("daily", {})
        if not isinstance(current, dict) or not isinstance(daily, dict):
            raise WeatherServiceError("The weather provider returned an incomplete forecast.")

        dates = self._numbers_or_strings(daily, "time")
        codes = self._numbers_or_strings(daily, "weather_code")
        highs = self._numbers_or_strings(daily, "temperature_2m_max")
        lows = self._numbers_or_strings(daily, "temperature_2m_min")
        apparent_highs = self._numbers_or_strings(daily, "apparent_temperature_max")
        rain_chances = self._numbers_or_strings(daily, "precipitation_probability_max")
        uv_values = self._numbers_or_strings(daily, "uv_index_max")
        if min(
            len(dates),
            len(codes),
            len(highs),
            len(lows),
            len(apparent_highs),
            len(rain_chances),
            len(uv_values),
        ) < 2:
            raise WeatherServiceError("The next-day forecast is temporarily unavailable.")

        current_code = int(current.get("weather_code", codes[0]))
        current_temperature = float(current.get("temperature_2m", highs[0]))
        current_weather = WeatherCurrent(
            temperature_c=round(current_temperature, 1),
            apparent_temperature_c=round(
                float(current.get("apparent_temperature", current_temperature)), 1
            ),
            humidity_percent=round(float(current.get("relative_humidity_2m", 0))),
            wind_kmh=round(float(current.get("wind_speed_10m", 0)), 1),
            weather_code=current_code,
            condition=self._condition(current_code),
            is_day=bool(current.get("is_day", 1)),
        )
        tomorrow = WeatherDay(
            date=str(dates[1]),
            temperature_max_c=round(float(highs[1]), 1),
            temperature_min_c=round(float(lows[1]), 1),
            apparent_temperature_max_c=round(float(apparent_highs[1]), 1),
            precipitation_probability=round(float(rain_chances[1])),
            uv_index_max=round(float(uv_values[1]), 1),
            weather_code=int(codes[1]),
            condition=self._condition(int(codes[1])),
        )
        tips = self._fashion_tips(
            temperature=current_temperature,
            code=current_code,
            tomorrow=tomorrow,
            wind=float(current.get("wind_speed_10m", 0)),
            size_label=size_label,
            color_season=color_season,
        )
        return WeatherHomeResponse(
            location=str(location.get("name", "Selected city")),
            region=str(location.get("admin1", "")) or None,
            country=str(location.get("country", "")) or None,
            timezone=str(forecast.get("timezone", location.get("timezone", "auto"))),
            updated_at=datetime.now(UTC),
            current=current_weather,
            tomorrow=tomorrow,
            fashion=tips,
            source="Open-Meteo forecast",
        )

    def _fashion_tips(
        self,
        *,
        temperature: float,
        code: int,
        tomorrow: WeatherDay,
        wind: float,
        size_label: str | None,
        color_season: str | None,
    ) -> list[FashionWeatherTip]:
        wet = self._is_wet(code) or tomorrow.precipitation_probability >= 45
        if temperature >= 30:
            base = FashionWeatherTip(
                kind="outfit",
                title="Airy warm-weather layers",
                reason="Choose linen, cotton voile, or a relaxed moisture-wicking top with breathable bottoms.",
            )
        elif temperature >= 24:
            base = FashionWeatherTip(
                kind="outfit",
                title="Light everyday separates",
                reason="A breathable top and relaxed trousers balance warmth with indoor air-conditioning.",
            )
        elif temperature >= 17:
            base = FashionWeatherTip(
                kind="outfit",
                title="Add one removable layer",
                reason="Use a cardigan, overshirt, or light blazer that can come off as the day warms.",
            )
        elif temperature >= 10:
            base = FashionWeatherTip(
                kind="outfit",
                title="Soft knit plus jacket",
                reason="A warm mid-layer and wind-blocking outer layer will handle the cooler temperature.",
            )
        else:
            base = FashionWeatherTip(
                kind="outfit",
                title="Insulated cold-weather layers",
                reason="Combine a thermal base, knit, and insulated coat while keeping movement comfortable.",
            )

        protection = FashionWeatherTip(
            kind="weather",
            title="Rain-ready finishing pieces" if wet else "Comfort-first footwear",
            reason=(
                "Carry a compact umbrella and choose quick-dry hems with water-resistant, grip-sole shoes."
                if wet
                else "Choose breathable shoes for the temperature and a sole suited to tomorrow’s forecast."
            ),
        )
        if wind >= 25:
            protection = FashionWeatherTip(
                kind="weather",
                title="Secure the windy-day silhouette",
                reason="Prefer a zipped layer, structured bag, and accessories that will stay in place.",
            )

        profile_reason = (
            f"Start with size {size_label}, then check the garment chart and intended ease."
            if size_label
            else "Complete a body scan to add your starting size to these weather picks."
        )
        fit = FashionWeatherTip(kind="fit", title="Your fit starting point", reason=profile_reason)

        color_reason = (
            f"Use a {color_season} accent near the face and keep weather gear in a coordinating neutral."
            if color_season
            else "Run Color Analysis to add a complexion-friendly accent to the recommendation."
        )
        color = FashionWeatherTip(kind="color", title="Your color accent", reason=color_reason)
        return [base, protection, fit, color]

    @staticmethod
    def _numbers_or_strings(source: dict[str, object], key: str) -> list[object]:
        value = source.get(key, [])
        return value if isinstance(value, list) else []

    @staticmethod
    def _is_wet(code: int) -> bool:
        return code in range(51, 68) or code in range(80, 83) or code in range(95, 100)

    @staticmethod
    def _condition(code: int) -> str:
        if code == 0:
            return "Clear sky"
        if code == 1:
            return "Mainly clear"
        if code == 2:
            return "Partly cloudy"
        if code == 3:
            return "Overcast"
        if code in (45, 48):
            return "Foggy"
        if code in range(51, 58):
            return "Drizzle"
        if code in range(61, 68):
            return "Rain"
        if code in range(71, 78):
            return "Snow"
        if code in range(80, 83):
            return "Rain showers"
        if code in (85, 86):
            return "Snow showers"
        if code in range(95, 100):
            return "Thunderstorms"
        return "Mixed conditions"
