# Search API — GET /api/artisans/search

Purpose
- Returns a list of artisans who offer the requested job categories or sub-categories (service-based search) and/or match geographic filters.
- The response includes server-authoritative `services` (from `ArtisanService`) and user details needed by the client UI.

Auth
- `optionalJWT` on the route: callers may send a bearer token. Results are filtered to `verified` artisans for non-admins.

Endpoint
- GET /api/artisans/search

- Query parameters
- `q` (string) — free-text search. If it matches JobCategory or JobSubCategory names, the server resolves those and filters artisans who offer the matched services.
- `categoryId` (string) — JobCategory._id to filter artisans who offer services in this category.
- `subCategoryId` (string) — JobSubCategory._id to filter artisans who offer this exact sub-service.
- `lat` (number), `lon` (number) — coordinates for geospatial search.
- `radiusKm` (number, default 10) — radius around `lat`/`lon` in kilometers.
- `location` (string) — free-text location; server will geocode (if configured) or fallback to address matching.
- `page` (integer, default 1) — paging page index.
- `limit` (integer, default 20) — number of items per page.
- `sortBy` (string, default `rating`) — field used for sorting (e.g., `rating`).
- `lat` (number), `lon` (number) — coordinates for geospatial search.
- `radiusKm` (number, default 10) — radius around `lat`/`lon` in kilometers.
- `location` (string) — free-text location; server will geocode (if configured) or fallback to address matching.
- `page` (integer, default 1) — paging page index.
- `limit` (integer, default 20) — number of items per page.
- `sortBy` (string, default `rating`) — field used for sorting (e.g., `rating`).

Response shape
- HTTP 200 JSON: `{ "success": true, "data": [ artisanObj, ... ] }`.
- Each `artisanObj` contains the following important fields for client display:
  - `_id`: Artisan document id (Artisan._id).
  - `userId`: canonical User._id for this artisan (use this as the unique person id where possible).
  - `user`: compact user info (if available): `{ _id, name, profileImageUrl, email, phone, role, kycVerified, isVerified }`.
  - `artisanAuthDetails`: quick auth summary `{ name, profileImage, email, phone, kycVerified, isVerified }`.
  - `profileProgress`: integer 0..100 (server-computed; KYC/profile/verified rules).
  - `verified`: boolean (artisan.verified).
  - `rating`, `reviewsCount` or `reviewsSummary`: rating averages and counts.
  - `services`: array of `ArtisanService` documents for this artisan (server-authoritative prices). Each service object includes:
    - `_id` (ArtisanService._id), `artisanId` (User._id), `categoryId` (populated name), and `services` (array with `subCategoryId` populated and `price`, `currency`, `notes`).
  - `bookingsStats`: `{ total, completed }` (optional)
  - `kycDetails`: limited KYC info (status, verified flag) — admin sees full payload.
  - `bio`, `serviceArea`: address/coordinates for mapping and short description.

- Notes about search behavior & pagination
- Search is service-based: the server first resolves `categoryId` / `subCategoryId` (or `q` mapped to category/subcategory names) against `ArtisanService` documents, finds artisans who offer matching services, then returns artisan profiles filtered by those artisans and any geo filters.
- The current API returns an array only (no `total` or `next` token). Use `page`/`limit` to advance pages.
- If returned array length < `limit`, you are likely at the last page.
- The current API returns an array only (no `total` or `next` token). Use `page`/`limit` to advance pages.
- If returned array length < `limit`, you are likely at the last page.

Recommended fields for Android list view
- `id` for list identity: use `userId` (preferred) and fall back to `_id` when necessary.
- `avatar`: `user.profileImageUrl` or `artisanAuthDetails.profileImage?.url`.
- `title`: `user.name` or `artisanAuthDetails.name`.
- `subtitle`: first line of `bio` or service summary.
- `rating`: `reviewsSummary.avgRating` (or `rating` field).
- `price`: display price from `services[0].services[0].price` and currency (server authoritative); show range if multiple services.
- `distance`: compute using `serviceArea.coordinates` vs device location if both present.
- `progressBadge`: `profileProgress` (0..100)

Example request
GET /api/artisans/search?categoryId=60f7f9c8b4d1f23a1c8b4567&lat=6.5244&lon=3.3792&radiusKm=15&page=1&limit=10

Example response (abridged)
{
  "success": true,
  "data": [
    {
      "_id": "6423a1b2c3d4e5f678901234",
      "userId": "611122223333444455556666",
      "user": { "_id": "611122223333444455556666", "name": "John Doe", "profileImageUrl": "https://..." },
      "artisanAuthDetails": { "name": "John Doe", "kycVerified": true },
      "profileProgress": 80,
      "verified": true,
      "reviewsSummary": { "avgRating": 4.8, "count": 12 },
      "services": [
        {
          "_id": "6423a1b2c3d4e5f678901999",
          "artisanId": "611122223333444455556666",
          "categoryId": { "_id": "60f7f9c8...", "name": "Plumbing" },
          "services": [ { "subCategoryId": { "_id": "60f7fa12...", "name": "Tap Repair" }, "price": 5000, "currency": "NGN" } ],
          "isActive": true
        }
      ],
      "bio": "Experienced plumber...",
      "serviceArea": { "address": "Ikeja, Lagos", "coordinates": [3.3792, 6.5244], "radius": 20 }
    }
  ]
}

Backward compatibility
- The server accepts both `Artisan._id` and `User._id` in public lookups, but returned `artisanId` and bookings use `User._id` as canonical id.

Error handling
- Validation errors return `400` with details (e.g., bad ObjectId patterns).
- Server errors return `500`.

Client tips
- Prefer using `userId` for follow-up calls (bookings, quotes) because it's the canonical person id.
- When showing prices, always use `services` returned by the API (do not rely on client-side pricing).
- If you need a compact payload for list items, request only the fields you need and the backend can be adjusted to return a trimmed version — tell me which fields and I will add a compact endpoint.

Questions or additions
- If you want a Kotlin sample showing how to call this endpoint and map the JSON into models for display, tell me which networking library you use (Retrofit/OkHttp/Ktor) and I will provide a snippet.

Search Modes (how mobile should call the API)
- 1) Category ID (exact): use when your UI presents a category list and you have the selected `categoryId`.
  - Request: `GET /api/artisans/search?categoryId=<categoryId>&page=1&limit=20`
  - Use-case: category browse screens.

- 2) Sub-category ID (exact): use when user selects a specific service option.
  - Request: `GET /api/artisans/search?subCategoryId=<subCategoryId>&lat=...&lon=...&radiusKm=20`
  - Use-case: service detail → list artisans who offer that service.

- 3) Free-text mapping (`q`): type-friendly search where users enter terms like "event catering" or "tap repair".
  - Behavior: the server attempts a case-insensitive partial match of `q` against `JobCategory.name` and `JobSubCategory.name`. If matches are found, those categories/subcategories are resolved to ids and used to filter artisans who offer the matched services.
  - Request examples:
    - `GET /api/artisans/search?q=event%20catering&page=1`
    - `GET /api/artisans/search?q=catering&lat=6.5&lon=3.3&radiusKm=25`
  - Use-case: universal search box for users who type human-readable terms.

- 4) Geospatial search (lat/lon + radius): combine with any of the above to find nearby artisans.
  - Request: `GET /api/artisans/search?categoryId=...&lat=6.5244&lon=3.3792&radiusKm=15`
  - Use-case: show nearby providers for a selected service.

- 5) Location text fallback: if device cannot provide coordinates, `location` text is geocoded (if MAPBOX_TOKEN configured) or matched against artisan addresses.
  - Request: `GET /api/artisans/search?q=plumbing&location=Ikeja&page=1`

Parameter precedence & notes
- If `categoryId` or `subCategoryId` is provided, they are used directly and `q` is ignored for category/subcategory resolution.
- If `q` is present and no explicit category/subCategory ids, the server will try to map `q` → category/subCategory names and filter by resolved ids.
- When both category/subCategory filters and geospatial filters are present, both constraints apply (intersection).

Compact response schema (recommended for list views)
Each list item can be mapped from the full artisan object to a compact payload for UI performance. Example minimal fields:

{
  "id": "611122223333444455556666",        // prefer `userId`
  "artisanId": "6423a1b2c3d4e5f678901234", // Artisan._id (optional)
  "name": "John Doe",
  "avatarUrl": "https://...",
  "rating": 4.8,
  "reviewsCount": 12,
  "profileProgress": 80,
  "primaryService": "Tap Repair",
  "price": 5000,
  "currency": "NGN",
  "distanceKm": 3.4
}

Implementation tips for mobile
- Prefer `userId` as the stable identifier for follow-up calls (bookings, messages, quotes).
- When showing price or service options, rely on the `services` array returned by the API — price is authoritative server-side.
- Cache category/subcategory id → name mapping locally to avoid extra lookups; use the free-text `q` flow when users type arbitrary terms.

