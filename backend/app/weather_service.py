from __future__ import annotations

import asyncio
from datetime import UTC, date, datetime, timedelta

import httpx

from .schemas import (
    FashionWeatherTip,
    WeatherCurrent,
    WeatherDay,
    WeatherHomeResponse,
)

# The app ships Philippine sizing and marketplaces, so an exact-name result in
# the Philippines wins ties against same-named places abroad. An explicit
# "City, Country" hint always outranks this default.
DEFAULT_COUNTRY_BIAS = "PH"

# Open-Meteo cannot resolve most Philippine province names directly (they
# return no results, or a same-named barangay in another region/country).
# Route each province to its seat city plus the expected province so "Aklan"
# and friends return weather for the place the user actually means.
PH_PROVINCE_SEATS: dict[str, tuple[str, str]] = {
    "abra": ("Bangued", "Abra"),
    "agusan del norte": ("Butuan", "Agusan del Norte"),
    "agusan del sur": ("Bayugan", "Agusan del Sur"),
    "aklan": ("Kalibo", "Aklan"),
    "albay": ("Legazpi", "Albay"),
    "antique": ("San Jose de Buenavista", "Antique"),
    "apayao": ("Kabugao", "Apayao"),
    "aurora": ("Baler", "Aurora"),
    "basilan": ("Isabela City", "Basilan"),
    "bataan": ("Balanga", "Bataan"),
    "batanes": ("Basco", "Batanes"),
    "batangas": ("Batangas City", "Batangas"),
    "benguet": ("La Trinidad", "Benguet"),
    "biliran": ("Naval", "Biliran"),
    "bohol": ("Tagbilaran", "Bohol"),
    "bukidnon": ("Malaybalay", "Bukidnon"),
    "bulacan": ("Malolos", "Bulacan"),
    "cagayan": ("Tuguegarao", "Cagayan"),
    "camarines norte": ("Daet", "Camarines Norte"),
    "camarines sur": ("Naga", "Camarines Sur"),
    "capiz": ("Roxas", "Capiz"),
    "catanduanes": ("Virac", "Catanduanes"),
    "cavite": ("Trece Martires", "Cavite"),
    "cebu": ("Cebu City", "Cebu"),
    "cotabato": ("Kidapawan", "Cotabato"),
    "davao de oro": ("Nabunturan", "Davao de Oro"),
    "davao del norte": ("Tagum", "Davao del Norte"),
    "davao del sur": ("Digos", "Davao del Sur"),
    "davao occidental": ("Malita", "Davao Occidental"),
    "davao oriental": ("Mati", "Davao Oriental"),
    "dinagat islands": ("San Jose", "Dinagat Islands"),
    "eastern samar": ("Borongan", "Eastern Samar"),
    "guimaras": ("Jordan", "Guimaras"),
    "ifugao": ("Lagawe", "Ifugao"),
    "ilocos norte": ("Laoag", "Ilocos Norte"),
    "ilocos sur": ("Vigan", "Ilocos Sur"),
    "iloilo": ("Iloilo City", "Iloilo"),
    "isabela": ("Ilagan", "Isabela"),
    "kalinga": ("Tabuk", "Kalinga"),
    "laguna": ("Santa Cruz", "Laguna"),
    "lanao del norte": ("Iligan", "Lanao del Norte"),
    "lanao del sur": ("Marawi", "Lanao del Sur"),
    "leyte": ("Tacloban", "Leyte"),
    "maguindanao": ("Buluan", "Maguindanao"),
    "marinduque": ("Boac", "Marinduque"),
    "masbate": ("Masbate City", "Masbate"),
    "misamis occidental": ("Oroquieta", "Misamis Occidental"),
    "misamis oriental": ("Cagayan de Oro", "Misamis Oriental"),
    "mountain province": ("Bontoc", "Mountain Province"),
    "negros occidental": ("Bacolod", "Negros Occidental"),
    "negros oriental": ("Dumaguete", "Negros Oriental"),
    "northern samar": ("Catarman", "Northern Samar"),
    "nueva ecija": ("Palayan", "Nueva Ecija"),
    "nueva vizcaya": ("Bayombong", "Nueva Vizcaya"),
    "occidental mindoro": ("Mamburao", "Occidental Mindoro"),
    "oriental mindoro": ("Calapan", "Oriental Mindoro"),
    "palawan": ("Puerto Princesa", "Palawan"),
    "pampanga": ("San Fernando", "Pampanga"),
    "pangasinan": ("Lingayen", "Pangasinan"),
    "quezon": ("Lucena", "Quezon"),
    "quirino": ("Cabarroguis", "Quirino"),
    "rizal": ("Antipolo", "Rizal"),
    "romblon": ("Romblon", "Romblon"),
    "samar": ("Catbalogan", "Samar"),
    "sarangani": ("Alabel", "Sarangani"),
    "siquijor": ("Siquijor", "Siquijor"),
    "sorsogon": ("Sorsogon City", "Sorsogon"),
    "south cotabato": ("Koronadal", "South Cotabato"),
    "southern leyte": ("Sogod", "Southern Leyte"),
    "sultan kudarat": ("Isulan", "Sultan Kudarat"),
    "sulu": ("Jolo", "Sulu"),
    "surigao del norte": ("Surigao City", "Surigao del Norte"),
    "surigao del sur": ("Tandag", "Surigao del Sur"),
    "tarlac": ("Tarlac City", "Tarlac"),
    "tawi-tawi": ("Bongao", "Tawi-Tawi"),
    "zambales": ("Iba", "Zambales"),
    "zamboanga del norte": ("Dipolog", "Zamboanga del Norte"),
    "zamboanga del sur": ("Pagadian", "Zamboanga del Sur"),
    "zamboanga sibugay": ("Ipil", "Zamboanga Sibugay"),
}

# Philippine places whose Open-Meteo name search needs disambiguation: same-
# named towns elsewhere outrank the famous one, or the city is only indexed
# under a longer name ("Lipa City"). Value = (search name, expected province).
PH_CITY_DISAMBIGUATION: dict[str, tuple[str, str]] = {
    "baguio": ("Baguio", "Benguet"),
    "kalibo": ("Kalibo", "Aklan"),
    "roxas": ("Roxas", "Capiz"),
    "antipolo": ("Antipolo", "Rizal"),
    "san fernando": ("San Fernando", "Pampanga"),
    "lucena": ("Lucena", "Quezon"),
    "lipa": ("Lipa City", "Batangas"),
}


class WeatherServiceError(ValueError):
    pass


async def _get_with_retry(
    client: httpx.AsyncClient,
    url: str,
    params: dict[str, object] | None = None,
    attempts: int = 3,
) -> httpx.Response:
    """GET with backoff for rate limits, cold starts and brief outages."""
    last_error: Exception | None = None
    for attempt in range(attempts):
        try:
            response = await client.get(url, params=params)
            response.raise_for_status()
            return response
        except httpx.HTTPStatusError as error:
            if error.response.status_code not in (408, 429, 500, 502, 503, 504):
                raise
            last_error = error
        except (httpx.ConnectError, httpx.TimeoutException) as error:
            last_error = error
        if attempt < attempts - 1:
            await asyncio.sleep(1.0 * (attempt + 1))
    assert last_error is not None
    raise last_error


class WeatherStyleService:
    def __init__(self) -> None:
        self._cache: dict[str, tuple[datetime, WeatherHomeResponse]] = {}
        self._normals_cache: dict[str, dict[str, object] | None] = {}

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
            headers={"User-Agent": "Seamly/1.3 weather-style"},
        ) as client:
            location: dict[str, object] | None = None
            try:
                location = await self._geocode(client, normalized_city)
            except httpx.HTTPStatusError as error:
                if error.response.status_code != 429:
                    raise
            if location is None:
                response = await self._fetch_wttr_fallback(
                    client,
                    city=normalized_city,
                    location=None,
                    size_label=size_label,
                    color_season=color_season,
                )
            else:
                try:
                    forecast = await self._forecast(
                        client,
                        latitude=float(location["latitude"]),
                        longitude=float(location["longitude"]),
                    )
                    response = self._build_response(
                        location=location,
                        forecast=forecast,
                        requested_city=normalized_city,
                        size_label=size_label,
                        color_season=color_season,
                    )
                except httpx.HTTPStatusError as error:
                    if error.response.status_code != 429:
                        raise
                    response = await self._fetch_wttr_fallback(
                        client,
                        city=normalized_city,
                        location=location,
                        size_label=size_label,
                        color_season=color_season,
                    )

        self._cache[cache_key] = (datetime.now(UTC), response)
        return response

    async def fetch_for_datetime(
        self,
        city: str,
        event_date: date,
        event_time: str | None,
    ) -> dict[str, object]:
        """Forecast slice for a specific event date + hour.

        Returns a dict with location, timezone, temperature_c, feels_like_c,
        condition, weather_code, rain_probability, wind_kmh, uv_index_max,
        hour and is_forecast. Dates beyond the 16-day Open-Meteo window
        return ``is_forecast=False`` with null weather values so the caller
        can fall back to a seasonal estimate.
        """
        normalized_city = city.strip()
        if len(normalized_city) < 2:
            raise WeatherServiceError("Enter at least two letters for the city.")
        hour = 18
        if event_time:
            try:
                hour = int(event_time.split(":")[0])
            except (ValueError, IndexError):
                hour = 18

        async with httpx.AsyncClient(
            timeout=httpx.Timeout(20.0, connect=10.0),
            follow_redirects=True,
            headers={"User-Agent": "Seamly/1.3 event-outfit"},
        ) as client:
            location = await self._geocode(client, normalized_city)
            days_ahead = (event_date - datetime.now(UTC).date()).days
            timezone = str(location.get("timezone", "auto"))
            base: dict[str, object] = {
                "location": location,
                "timezone": timezone,
                "hour": hour,
            }
            if days_ahead > 15:
                normals = await self._climate_normals(
                    client,
                    latitude=float(location["latitude"]),
                    longitude=float(location["longitude"]),
                    event_date=event_date,
                )
                if normals is not None:
                    return {**base, **normals}
                return {
                    **base,
                    "temperature_c": None,
                    "feels_like_c": None,
                    "condition": "Seasonal estimate",
                    "weather_code": None,
                    "rain_probability": None,
                    "wind_kmh": None,
                    "uv_index_max": None,
                    "is_forecast": False,
                }
            try:
                forecast = await self._forecast_for_date(
                    client,
                    latitude=float(location["latitude"]),
                    longitude=float(location["longitude"]),
                    event_date=event_date,
                )
            except httpx.HTTPError:
                if 0 <= days_ahead <= 2:
                    return await self._fetch_wttr_for_date(
                        client,
                        city=normalized_city,
                        location=location,
                        event_date=event_date,
                        hour=hour,
                        timezone=timezone,
                    )
                raise
            hourly = forecast.get("hourly", {})
            daily = forecast.get("daily", {})
            if not isinstance(hourly, dict) or not isinstance(daily, dict):
                raise WeatherServiceError("The weather provider returned an incomplete forecast.")
            times = hourly.get("time", [])
            if not isinstance(times, list) or not times:
                raise WeatherServiceError("The weather provider returned an incomplete forecast.")
            best = min(
                range(len(times)),
                key=lambda i: abs(int(str(times[i])[-5:-3]) - hour),
            )
            temps = hourly.get("temperature_2m", [])
            feels = hourly.get("apparent_temperature", [])
            codes = hourly.get("weather_code", [])
            rains = hourly.get("precipitation_probability", [])
            winds = hourly.get("wind_speed_10m", [])
            code = int(codes[best]) if len(codes) > best else 2
            daily_rain = daily.get("precipitation_probability_max", [])
            daily_uv = daily.get("uv_index_max", [])
            return {
                **base,
                "temperature_c": round(float(temps[best]), 1) if len(temps) > best else None,
                "feels_like_c": round(float(feels[best]), 1) if len(feels) > best else None,
                "condition": self._condition(code),
                "weather_code": code,
                "rain_probability": round(float(rains[best])) if len(rains) > best else None,
                "wind_kmh": round(float(winds[best]), 1) if len(winds) > best else None,
                "uv_index_max": round(float(daily_uv[0]), 1) if daily_uv else None,
                "daily_rain_max": round(float(daily_rain[0])) if daily_rain else None,
                "is_forecast": True,
            }

    async def _climate_normals(
        self,
        client: httpx.AsyncClient,
        *,
        latitude: float,
        longitude: float,
        event_date: date,
        years: int = 10,
    ) -> dict[str, object] | None:
        """10-year ERA5 averages for the event's month-day (free archive API).

        Returns numbers with ``is_forecast=False`` and source
        ``climate normals (ERA5)``, or None when unavailable. Results are
        cached in memory: climate normals barely change.
        """
        month, day = event_date.month, event_date.day
        if month == 2 and day == 29:
            day = 28
        cache_key = f"{round(latitude, 2)},{round(longitude, 2)}|{month:02d}-{day:02d}"
        if cache_key in self._normals_cache:
            return self._normals_cache[cache_key]
        current_year = datetime.now(UTC).date().year
        params = {
            "latitude": latitude,
            "longitude": longitude,
            "start_date": f"{current_year - years}-{month:02d}-{day:02d}",
            "end_date": f"{current_year - 1}-{month:02d}-{day:02d}",
            "daily": "temperature_2m_max,precipitation_sum,wind_speed_10m_max",
            "timezone": "auto",
        }
        try:
            response = await _get_with_retry(
                client,
                "https://archive-api.open-meteo.com/v1/archive",
                params=params,
            )
            result = self._summarize_normals(response.json(), month=month, day=day)
        except (httpx.HTTPError, ValueError, KeyError, TypeError):
            result = None
        self._normals_cache[cache_key] = result
        return result

    @staticmethod
    def _summarize_normals(
        payload: dict[str, object], *, month: int, day: int
    ) -> dict[str, object] | None:
        daily = payload.get("daily", {})
        if not isinstance(daily, dict):
            return None
        times = daily.get("time", [])
        highs = daily.get("temperature_2m_max", [])
        rains = daily.get("precipitation_sum", [])
        winds = daily.get("wind_speed_10m_max", [])
        if not isinstance(times, list):
            return None
        wanted = f"{month:02d}-{day:02d}"
        samples: list[tuple[float, float, float | None]] = []
        for index, stamp in enumerate(times):
            if not isinstance(stamp, str) or stamp[5:] != wanted:
                continue
            try:
                high = float(highs[index])
            except (IndexError, TypeError, ValueError):
                continue
            try:
                rain = float(rains[index])
            except (IndexError, TypeError, ValueError):
                rain = 0.0
            try:
                wind: float | None = float(winds[index])
            except (IndexError, TypeError, ValueError):
                wind = None
            samples.append((high, rain, wind))
        if len(samples) < 5:
            return None
        mean_high = sum(sample[0] for sample in samples) / len(samples)
        rain_days = sum(1 for sample in samples if sample[1] > 1.0)
        rain_fraction = rain_days / len(samples)
        wind_values = [sample[2] for sample in samples if sample[2] is not None]
        mean_wind = (
            sum(wind_values) / len(wind_values) if wind_values else None
        )
        if rain_fraction >= 0.5:
            condition = "Often rainy"
        elif rain_fraction >= 0.3:
            condition = "Sometimes rainy"
        elif rain_fraction >= 0.15:
            condition = "Occasionally wet"
        else:
            condition = "Usually dry"
        return {
            "temperature_c": round(mean_high, 1),
            "feels_like_c": round(mean_high, 1),
            "condition": condition,
            "weather_code": None,
            "rain_probability": round(rain_fraction * 100),
            "wind_kmh": round(mean_wind, 1) if mean_wind is not None else None,
            "uv_index_max": None,
            "is_forecast": False,
            "source": "climate normals (ERA5)",
            "sample_years": len(samples),
        }

    async def _geocode(
        self,
        client: httpx.AsyncClient,
        city: str,
    ) -> dict[str, object]:
        attempts = self._city_attempts(city)
        last_error: WeatherServiceError | None = None
        for name, hint, province in attempts:
            for search_name in self._search_variants(name):
                response = await _get_with_retry(
                    client,
                    "https://geocoding-api.open-meteo.com/v1/search",
                    params={
                        "name": search_name,
                        "count": 20,
                        "language": "en",
                        "format": "json",
                    },
                )
                results = response.json().get("results", [])
                if not results:
                    last_error = WeatherServiceError(
                        f'No weather location matched "{city}". Try adding the country.'
                    )
                    continue
                try:
                    return self._pick_geocode_result(
                        results,
                        name=name,
                        hint=hint,
                        query=city,
                        province=province,
                    )
                except WeatherServiceError as error:
                    last_error = error
                    continue
        raise last_error or WeatherServiceError(
            f'No weather location matched "{city}". Try adding the country.'
        )

    @classmethod
    def _city_attempts(
        cls,
        city: str,
    ) -> list[tuple[str, str | None, str | None]]:
        name, hint = cls._split_city_query(city)
        seat = cls._province_seat(name, hint)
        if seat is not None:
            seat_name, province = seat
            return [(seat_name, "Philippines", province), (name, hint, None)]
        if hint is None or hint.casefold() in ("ph", "philippines"):
            disambiguation = PH_CITY_DISAMBIGUATION.get(name.casefold())
            if disambiguation is not None:
                search_name, province = disambiguation
                if search_name.casefold() != name.casefold():
                    return [(search_name, hint or "Philippines", province)]
                return [(name, hint, province), (name, hint, None)]
        return [(name, hint, None)]

    @staticmethod
    def _search_variants(name: str) -> list[str]:
        normalized = WeatherStyleService._normalized_place_name(name)
        if normalized != name.casefold():
            return [name, normalized]
        return [name]

    @staticmethod
    def _province_seat(
        name: str,
        hint: str | None,
    ) -> tuple[str, str] | None:
        if hint is not None and hint.casefold() not in ("ph", "philippines"):
            return None
        return PH_PROVINCE_SEATS.get(name.casefold())

    @staticmethod
    def _admin_matches(admin_value: object, province: str) -> bool:
        if not isinstance(admin_value, str) or not admin_value:
            return False
        normalized = admin_value.casefold()
        if normalized.startswith("province of "):
            normalized = normalized[len("province of ") :]
        return normalized == province.casefold()

    @staticmethod
    def _split_city_query(city: str) -> tuple[str, str | None]:
        parts = [part.strip() for part in city.split(",") if part.strip()]
        if not parts:
            return city.strip(), None
        if len(parts) == 1:
            return parts[0], None
        return parts[0], parts[-1]

    @staticmethod
    def _normalized_place_name(value: str) -> str:
        folded = value.casefold()
        for suffix in (" city", " town", " municipality"):
            if folded.endswith(suffix):
                return folded[: -len(suffix)]
        return folded

    @staticmethod
    def _pick_geocode_result(
        results: list[dict[str, object]],
        *,
        name: str,
        hint: str | None,
        query: str,
        province: str | None = None,
    ) -> dict[str, object]:
        folded_name = WeatherStyleService._normalized_place_name(name)
        folded_hint = hint.casefold() if hint else None
        biased: list[tuple[float, dict[str, object]]] = []
        for index, result in enumerate(results):
            score = -float(index)
            result_name = WeatherStyleService._normalized_place_name(
                str(result.get("name", ""))
            )
            country = str(result.get("country", "")).casefold()
            country_code = str(result.get("country_code", "")).casefold()
            admin1 = str(result.get("admin1", "")).casefold()
            admin2 = str(result.get("admin2", "")).casefold()
            if result_name == folded_name:
                score += 100.0
            elif result_name.startswith(folded_name) or folded_name.startswith(
                result_name
            ):
                score += 40.0
            if admin1 == folded_name or admin2 == folded_name:
                score += 120.0
            population = result.get("population")
            if isinstance(population, (int, float)) and population > 0:
                score += min(int(population).bit_length(), 24)
            if folded_hint:
                hint_match = (
                    folded_hint in (country, country_code)
                    or country.startswith(folded_hint)
                    or folded_hint in country.split()
                    or WeatherStyleService._admin_matches(
                        result.get("admin1"), hint or ""
                    )
                    or WeatherStyleService._admin_matches(
                        result.get("admin2"), hint or ""
                    )
                )
                score += 1000.0 if hint_match else -1000.0
            elif country_code == DEFAULT_COUNTRY_BIAS.casefold():
                score += 150.0
            if province is not None:
                in_province = WeatherStyleService._admin_matches(
                    result.get("admin1"), province
                ) or WeatherStyleService._admin_matches(
                    result.get("admin2"), province
                )
                score += 1000.0 if in_province else -500.0
            biased.append((score, result))
        best_score, best = max(biased, key=lambda pair: pair[0])
        if folded_hint and best_score < 0:
            raise WeatherServiceError(
                f'No weather location matched "{query}". Try adding the country.'
            )
        return best

    async def _forecast(
        self,
        client: httpx.AsyncClient,
        *,
        latitude: float,
        longitude: float,
    ) -> dict[str, object]:
        response = await _get_with_retry(
            client,
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
        return response.json()

    async def _forecast_for_date(
        self,
        client: httpx.AsyncClient,
        *,
        latitude: float,
        longitude: float,
        event_date: date,
    ) -> dict[str, object]:
        iso = event_date.isoformat()
        response = await _get_with_retry(
            client,
            "https://api.open-meteo.com/v1/forecast",
            params={
                "latitude": latitude,
                "longitude": longitude,
                "hourly": (
                    "temperature_2m,apparent_temperature,precipitation_probability,"
                    "weather_code,wind_speed_10m"
                ),
                "daily": "weather_code,precipitation_probability_max,uv_index_max",
                "timezone": "auto",
                "start_date": iso,
                "end_date": iso,
                "forecast_days": 16,
            },
        )
        return response.json()

    async def _fetch_wttr_for_date(
        self,
        client: httpx.AsyncClient,
        *,
        city: str,
        location: dict[str, object],
        event_date: date,
        hour: int,
        timezone: str,
    ) -> dict[str, object]:
        """wttr.in fallback for event dates within its 3-day window."""
        query = f"{float(location['latitude'])},{float(location['longitude'])}"
        try:
            query_city = str(location.get("name") or city)
        except (ValueError, TypeError, KeyError):
            query_city = city
        response = await _get_with_retry(
            client, f"https://wttr.in/{query}", params={"format": "j1"}
        )
        payload = response.json()
        days = payload.get("weather") or []
        target = event_date.isoformat()
        day = next(
            (
                entry
                for entry in days
                if isinstance(entry, dict) and entry.get("date") == target
            ),
            None,
        )
        if day is None:
            raise WeatherServiceError(
                "The dated forecast is temporarily unavailable. Please try again."
            )
        hours = day.get("hourly") or []
        if not hours:
            raise WeatherServiceError(
                "The dated forecast is temporarily unavailable. Please try again."
            )

        def _slot_value(slot: object) -> int:
            try:
                return int(str(slot))
            except (TypeError, ValueError):
                return 0

        best = min(
            (slot for slot in hours if isinstance(slot, dict)),
            key=lambda slot: abs(_slot_value(slot.get("time")) // 100 - hour),
            default={},
        )
        descriptions = best.get("weatherDesc") or []
        desc = (
            str(descriptions[0].get("value", "")).strip()
            if descriptions and isinstance(descriptions[0], dict)
            else ""
        ) or "Mixed conditions"

        def _number(value: object, default: float = 0.0) -> float:
            try:
                return float(str(value))
            except (TypeError, ValueError):
                return default

        return {
            "location": location,
            "timezone": timezone,
            "hour": hour,
            "temperature_c": round(_number(best.get("tempC")), 1),
            "feels_like_c": round(
                _number(best.get("FeelsLikeC"), _number(best.get("tempC"))), 1
            ),
            "condition": desc,
            "weather_code": None,
            "rain_probability": round(_number(best.get("chanceofrain"))),
            "wind_kmh": round(_number(best.get("windspeedKmph")), 1),
            "uv_index_max": round(_number(best.get("uvIndex")) or 0, 1),
            "is_forecast": True,
            "source": "wttr.in fallback",
            "city": query_city,
        }

    async def _fetch_wttr_fallback(
        self,
        client: httpx.AsyncClient,
        *,
        city: str,
        location: dict[str, object] | None,
        size_label: str | None,
        color_season: str | None,
    ) -> WeatherHomeResponse:
        if location is not None:
            query = f"{float(location['latitude'])},{float(location['longitude'])}"
        else:
            query = city
        response = await client.get(
            f"https://wttr.in/{query}",
            params={"format": "j1"},
        )
        response.raise_for_status()
        payload = response.json()

        current_list = payload.get("current_condition") or []
        days = payload.get("weather") or []
        if not current_list or len(days) < 2:
            raise WeatherServiceError("The next-day forecast is temporarily unavailable.")

        current = current_list[0]
        area = (payload.get("nearest_area") or [{}])[0]
        place_name = ((area.get("areaName") or [{}])[0]).get("value", city)
        region = ((area.get("region") or [{}])[0]).get("value", "")
        country = ((area.get("country") or [{}])[0]).get("value", "")
        if location is not None:
            place_name = str(location.get("name") or place_name)
            region = str(location.get("admin1") or region)
            country = str(location.get("country") or country)

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
            apparent=current_weather.apparent_temperature_c,
            humidity=current_weather.humidity_percent,
            condition=current_weather.condition,
            code=current_code,
            tomorrow=day_list[1],
            wind=float(current.get("windspeedKmph", 0)),
            size_label=size_label,
            color_season=color_season,
        )
        return WeatherHomeResponse(
            requested_city=city,
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
        requested_city: str | None = None,
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
            apparent=current_weather.apparent_temperature_c,
            humidity=current_weather.humidity_percent,
            condition=current_weather.condition,
            code=current_code,
            tomorrow=tomorrow,
            wind=float(current.get("wind_speed_10m", 0)),
            size_label=size_label,
            color_season=color_season,
        )
        return WeatherHomeResponse(
            requested_city=requested_city,
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
        apparent: float,
        humidity: int,
        condition: str,
        code: int,
        tomorrow: WeatherDay,
        wind: float,
        size_label: str | None,
        color_season: str | None,
    ) -> list[FashionWeatherTip]:
        wet = self._is_wet(code) or tomorrow.precipitation_probability >= 45
        feels = apparent
        if feels >= 33:
            title = "Ultralight heat-ready layers"
            reason = (
                f"It feels like {round(feels)}°C in {condition.lower()}: choose a loose linen or "
                "mesh-weave top, cropped or wide trousers, and open footwear that breathes."
            )
        elif feels >= 27:
            title = "Airy warm-weather separates"
            reason = (
                f"Feels like {round(feels)}°C with {humidity}% humidity: a moisture-wicking tee or "
                "sleeveless top with relaxed shorts or a breezy skirt keeps you cool indoors and out."
            )
        elif feels >= 21:
            title = "Light everyday separates"
            reason = (
                f"A comfortable {round(feels)}°C feels-like temperature suits a breathable top and "
                "relaxed trousers that layer well against indoor air-conditioning."
            )
        elif feels >= 13:
            title = "Add one removable layer"
            reason = (
                f"At {round(feels)}°C feels-like, use a cardigan, overshirt, or light blazer that can "
                "come off as the day warms."
            )
        elif feels >= 5:
            title = "Soft knit plus jacket"
            reason = (
                f"A {round(feels)}°C feels-like chill calls for a warm mid-layer and a wind-blocking "
                "outer layer."
            )
        else:
            title = "Insulated cold-weather layers"
            reason = (
                f"It feels like {round(feels)}°C: combine a thermal base, knit, and insulated coat "
                "while keeping movement comfortable."
            )
        if wet:
            title = f"Rain-ready: {title[0].lower()}{title[1:]}" if title else title
            reason += " Add quick-dry fabrics and water-resistant shoes for the wet spells."
        base = FashionWeatherTip(kind="outfit", title=title, reason=reason)

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
