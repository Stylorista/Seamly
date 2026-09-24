from __future__ import annotations

import os
from typing import Literal

import httpx
from fastapi import FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from .ai_engine import StyloristaEngine
from .account_store import (
    AccountExistsError,
    InvalidCredentialsError,
    StaleMeasurementsError,
    create_account_store,
)
from .appearance_analysis import AppearanceAnalysisError, AppearanceAnalyzer
from .body_scan import BodyScanError, BodyScanEstimator
from .news_feed import FashionNewsService
from .schemas import (
    AccountAuthResponse,
    AccountLoginRequest,
    AccountProfile,
    AccountProfileUpdateRequest,
    AccountRegisterRequest,
    BodyScanRequest,
    BodyScanResponse,
    AppearanceAnalysisRequest,
    AppearanceAnalysisResponse,
    ColorRequest,
    ColorResponse,
    FashionNewsResponse,
    SizeRequest,
    SizeResponse,
    SavedMeasurementsRequest,
    ShopProductsResponse,
    StyleRequest,
    StyleResponse,
    WeatherHomeResponse,
)
from .weather_service import WeatherServiceError, WeatherStyleService
from .shop_catalog import ShopCatalogService


app = FastAPI(
    title="FashionTech API",
    description="Privacy-first fashion fit, personal color and seasonal styling MVP.",
    version="1.7.0",
)

configured_origins = [
    origin.strip()
    for origin in os.getenv("CORS_ALLOWED_ORIGINS", "").split(",")
    if origin.strip()
] or ["https://stylorista-ai.jadesalvador3257.chatgpt.site"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=configured_origins,
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "OPTIONS"],
    allow_headers=["*"],
)

engine = StyloristaEngine()
body_scan_estimator = BodyScanEstimator()
appearance_analyzer = AppearanceAnalyzer()
fashion_news_service = FashionNewsService()
weather_style_service = WeatherStyleService()
shop_catalog_service = ShopCatalogService()
account_store = create_account_store()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "fashiontech", "version": app.version}


def _bearer_token(authorization: str | None) -> str:
    scheme, _, token = (authorization or "").partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise HTTPException(status_code=401, detail="Please sign in to continue.")
    return token.strip()


@app.post("/v1/auth/register", response_model=AccountAuthResponse, status_code=201)
def register_account(request: AccountRegisterRequest) -> AccountAuthResponse:
    try:
        token, profile = account_store.register(
            name=request.name,
            email=request.email,
            password=request.password,
            height_cm=request.height_cm,
            phone=request.phone,
            location=request.location,
        )
    except AccountExistsError as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    return AccountAuthResponse(
        token=token,
        is_new_account=True,
        profile=AccountProfile.model_validate(profile),
    )


@app.post("/v1/auth/login", response_model=AccountAuthResponse)
def login_account(request: AccountLoginRequest) -> AccountAuthResponse:
    try:
        token, profile = account_store.login(
            email=request.email,
            password=request.password,
        )
    except InvalidCredentialsError as error:
        raise HTTPException(status_code=401, detail=str(error)) from error
    return AccountAuthResponse(
        token=token,
        is_new_account=False,
        profile=AccountProfile.model_validate(profile),
    )


@app.get("/v1/account/profile", response_model=AccountProfile)
def account_profile(authorization: str | None = Header(default=None)) -> AccountProfile:
    try:
        return AccountProfile.model_validate(
            account_store.profile_for_token(_bearer_token(authorization))
        )
    except InvalidCredentialsError as error:
        raise HTTPException(status_code=401, detail=str(error)) from error


@app.put("/v1/account/measurements", response_model=AccountProfile)
def save_account_measurements(
    request: SavedMeasurementsRequest,
    authorization: str | None = Header(default=None),
) -> AccountProfile:
    try:
        profile = account_store.save_measurements(
            token=_bearer_token(authorization),
            measurements=request.measurements.model_dump(),
            size_label=request.size_label,
            scan_confidence=request.scan_confidence,
        )
    except InvalidCredentialsError as error:
        raise HTTPException(status_code=401, detail=str(error)) from error
    except StaleMeasurementsError as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    return AccountProfile.model_validate(profile)


@app.put("/v1/account/profile", response_model=AccountProfile)
def update_account_profile(
    request: AccountProfileUpdateRequest,
    authorization: str | None = Header(default=None),
) -> AccountProfile:
    try:
        profile = account_store.update_profile(
            token=_bearer_token(authorization), name=request.name,
            height_cm=request.height_cm, avatar_base64=request.avatar_base64,
            update_avatar="avatar_base64" in request.model_fields_set,
        )
        return AccountProfile.model_validate(profile)
    except InvalidCredentialsError as error:
        raise HTTPException(status_code=401, detail=str(error)) from error


@app.post("/v1/auth/logout")
def logout_account(authorization: str | None = Header(default=None)) -> dict[str, bool]:
    account_store.logout(_bearer_token(authorization))
    return {"signed_out": True}


@app.get("/v1/news/feed", response_model=FashionNewsResponse)
async def fashion_news_feed(
    category: Literal[
        "all",
        "y2k",
        "gothic",
        "alternative",
        "formal",
        "casual",
        "wedding",
        "streetwear",
        "vintage",
    ] = "all",
    limit: int = Query(default=16, ge=4, le=30),
) -> FashionNewsResponse:
    return await fashion_news_service.fetch(category=category, limit=limit)


@app.get("/v1/shop/products", response_model=ShopProductsResponse)
async def shop_products(
    limit: int = Query(default=40, ge=1, le=80),
) -> ShopProductsResponse:
    return await shop_catalog_service.fetch(limit=limit)


@app.get("/v1/weather/home", response_model=WeatherHomeResponse)
async def home_weather(
    city: str = Query(default="Manila", min_length=2, max_length=100),
    size_label: str | None = Query(default=None, max_length=12),
    color_season: Literal["Spring", "Summer", "Autumn", "Winter"] | None = None,
) -> WeatherHomeResponse:
    try:
        return await weather_style_service.fetch(
            city=city,
            size_label=size_label,
            color_season=color_season,
        )
    except WeatherServiceError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except httpx.HTTPError as error:
        raise HTTPException(
            status_code=503,
            detail="Live weather is temporarily unavailable. Please try again.",
        ) from error


@app.post("/v1/size/recommend", response_model=SizeResponse)
def recommend_size(request: SizeRequest) -> SizeResponse:
    return engine.recommend_size(request)


@app.post("/v1/body-scan/analyze", response_model=BodyScanResponse)
def analyze_body_scan(request: BodyScanRequest) -> BodyScanResponse:
    try:
        return body_scan_estimator.analyze(request)
    except BodyScanError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error


@app.post("/v1/profile/analyze", response_model=AppearanceAnalysisResponse)
def analyze_profile_photo(
    request: AppearanceAnalysisRequest,
) -> AppearanceAnalysisResponse:
    try:
        return appearance_analyzer.analyze(request)
    except AppearanceAnalysisError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error


@app.post("/v1/color/analyze", response_model=ColorResponse)
def analyze_color(request: ColorRequest) -> ColorResponse:
    return engine.analyze_color(request)


@app.post("/v1/style/recommend", response_model=StyleResponse)
def recommend_style(request: StyleRequest) -> StyleResponse:
    return engine.recommend_style(request)
