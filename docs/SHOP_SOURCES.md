# Seamly shop source contract

The shop displays a product photo only when the backend receives that photo in
the same normalized record as the exact marketplace listing. It does not scrape
marketplace search pages or substitute a generic fashion image.

## Connect an approved source

Create an approved seller, retailer, or affiliate integration for each
marketplace and normalize its output to the JSON contract below. Host that JSON
behind HTTPS, then set `FASHIONTECH_SHOP_CATALOG_URL` on the backend. If the feed
requires a bearer token, set `FASHIONTECH_SHOP_CATALOG_TOKEN` as a backend secret.

Do not put partner secrets in Flutter, Git, or the public web build.

```json
{
  "items": [
    {
      "id": "source-item-id",
      "title": "Exact product title from the source",
      "category": "Dresses",
      "marketplace": "Lazada",
      "seller": "Seller name from the source",
      "product_url": "https://www.lazada.com.ph/products/replace-with-exact-listing.html",
      "image_url": "https://my-live-02.slatic.net/p/replace-with-source-image.jpg",
      "image_source_url": "https://my-live-02.slatic.net/p/replace-with-source-image.jpg",
      "price_label": "₱1,290",
      "sizes": ["S", "M", "L"],
      "color_seasons": ["Autumn"],
      "source_updated_at": "2026-09-04T08:00:00Z"
    }
  ]
}
```

Allowed categories are `Tops`, `Bottoms`, `Dresses`, `Outerwear`, and
`Accessories`. Allowed marketplaces are `Shopee`, `Lazada`, and `Temu`.

The `image_url` and `image_source_url` must be identical HTTPS URLs. The backend
checks the exact listing host and image-CDN host against the declared
marketplace, removes duplicate listing and image URLs, and hides invalid
records. If no approved feed is connected, the UI shows an honest setup state
and image-free marketplace searches.

## Marketplace onboarding

- Shopee: register and obtain the required product-data access through Shopee
  Open Platform, including seller authorization when required.
- Lazada: register an application through Lazada Open Platform and use its
  authorization and product APIs for the stores that authorize Seamly.
- Temu: register through Temu Partner Platform and request the applicable
  product-data permissions.

Before launch, confirm that the applicable agreement permits displaying each
field, image hotlinking or caching, affiliate attribution, pricing freshness,
and the intended territory. A search-result page is not a product feed.
