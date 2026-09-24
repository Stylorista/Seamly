from __future__ import annotations

from datetime import UTC, datetime, timedelta

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
        attempts = self._city_attempts(city)
        last_error: WeatherServiceError | None = None
        for name, hint, province in attempts:
            for search_name in self._search_variants(name):
                response = await client.get(
                    "https://geocoding-api.open-meteo.com/v1/search",
                    params={
                        "name": search_name,
                        "count": 20,
                        "language": "en",
                        "format": "json",
                    },
                )
                response.raise_for_status()
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
