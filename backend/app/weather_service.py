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
        if cached and datetime.now(UTC) - cached[0] < timedelta(minutes=30):
            return cached[1]

        async with httpx.AsyncClient(
            timeout=httpx.Timeout(20.0, connect=10.0),
            follow_redirects=True,
            headers={"User-Agent": "FashionTech/1.3 weather-style"},
        ) as client:
            try:
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
            except httpx.HTTPStatusError as error:
                if error.response.status_code != 429:
                    raise
                response = await self._fetch_wttr_fallback(
                    client,
                    city=normalized_city,
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

    async def _fetch_wttr_fallback(
        self,
        client: httpx.AsyncClient,
        *,
        city: str,
        size_label: str | None,
        color_season: str | None,
    ) -> WeatherHomeResponse:
        response = await client.get(
            f"https://wttr.in/{city}",
            params={"format": "j1"},
        )
        response.raise_for_status()
        payload = response.json()

        current_list = payload.get("current_condition") or []
        days = payload.get("weather") or []
        if not current_list or len(days) < 2:
            raise WeatherServiceError("The next-day forecast is temporarily unavailable.")

        current = current_list[0]
        location = (payload.get("nearest_area") or [{}])[0]
        place_name = ((location.get("areaName") or [{}])[0]).get("value", city)
        region = ((location.get("region") or [{}])[0]).get("value", "")
        country = ((location.get("country") or [{}])[0]).get("value", "")

        def _desc(hour: dict[str, object]) -> str:
            items = hour.get("weatherDesc") or []
            if items and isinstance(items[0], dict):
                return str(items[0].get("value", "")).strip()
            return ""

        def _code(desc: str) -> int:
            d = desc.lower()
            if "thunder" in d:
                return 95
            if "snow" in d:
                return 71
            if "drizzle" in d:
                return 51
            if "rain" in d or "shower" in d:
                return 61
            if "fog" in d or "mist" in d:
                return 45
            if "overcast" in d:
                return 3
            if "partly" in d or "cloud" in d:
                return 2
            if "clear" in d or "sun" in d:
                return 0
            return 2

        noon_hours = []
        for day in days[:2]:
            hours = day.get("hourly") or []
            noon = next(
                (h for h in hours if str(h.get("time", "")) in {"1200", "12"}),
                hours[len(hours) // 2] if hours else {},
            )
            noon_hours.append(noon or {})

        day_list: list[WeatherDay] = []
        for index in range(2):
            day = days[index]
            noon = noon_hours[index]
            desc = _desc(noon) or _desc(current)
            rain_values = [
                int(h.get("chanceofrain") or 0) for h in (day.get("hourly") or [])
            ]
            uv_values = [
                int(h.get("uvIndex") or 0) for h in (day.get("hourly") or [])
            ]
            high_c = float(day.get("maxtempC", 0))
            day_list.append(
                WeatherDay(
                    date=str(day.get("date", "")),
                    temperature_max_c=high_c,
                    temperature_min_c=float(day.get("mintempC", 0)),
                    apparent_temperature_max_c=high_c,
                    precipitation_probability=max(rain_values) if rain_values else 0,
                    uv_index_max=float(max(uv_values) if uv_values else 0),
                    weather_code=_code(desc),
                    condition=desc or "Clear",
                )
            )

        current_desc = _desc(current) or "Clear"
        temperature = float(current.get("temp_C", 0))
        current_code = _code(current_desc)
        current_weather = WeatherCurrent(
            temperature_c=temperature,
            apparent_temperature_c=float(current.get("FeelsLikeC", temperature)),
            humidity_percent=round(float(current.get("humidity", 0))),
            wind_kmh=float(current.get("windspeedKmph", 0)),
            weather_code=current_code,
            condition=current_desc,
            is_day=bool(int(current.get("uvIndex", 0) or 0) > 0 or "sun" in current_desc.lower()),
        )
        tips = self._fashion_tips(
            temperature=temperature,
            code=current_code,
            tomorrow=day_list[1],
            wind=float(current.get("windspeedKmph", 0)),
            size_label=size_label,
            color_season=color_season,
        )
        return WeatherHomeResponse(
            location=place_name or city,
            region=region or None,
            country=country or None,
            timezone=str(payload.get("timezone", {}).get("name", "auto")),
            updated_at=datetime.now(UTC),
            current=current_weather,
            tomorrow=day_list[1],
            fashion=tips,
            source="wttr.in fallback",
        )

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
