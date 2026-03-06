# Artisan Services (per-artisan offerings)

Overview

Artisans may declare which sub-services they offer within a main `JobCategory` and set a price per sub-service. Clients can then directly book a specific sub-service from an artisan; the booking price will be derived from the artisan's configured offering.

Model
- `ArtisanService` documents store an `artisanId`, `categoryId`, and an array of `services`:
  - `subCategoryId` — id of `JobSubCategory`
  - `price` — numeric price (e.g., 50000)
  - `currency` — e.g. `NGN`

Endpoints
- `POST /api/artisan-services` — create or update an artisan's offerings for a category (artisan only). Body: `{ categoryId, services: [{ subCategoryId, price, currency?, notes? }, ...] }`.
- `GET /api/artisan-services/me` — list the authenticated artisan's current offerings.
- `GET /api/artisan-services/:id` — get a single ArtisanService entry (artisan only).
- `PUT /api/artisan-services/:id` — update (artisan only).
- `DELETE /api/artisan-services/:id` — remove (soft-delete) (artisan only).

Booking integration
- When creating a booking, clients may provide `categoryId` and `subCategoryId` (and `artisanId`) instead of a raw `price`:
  - Server will look up the artisan's `ArtisanService` entry and resolve the `price` for the selected sub-service.
  - If the sub-service isn't offered, the server returns a 400 error.
  - After resolution the booking's `service` field is set to the subcategory name and `price` is set to the artisan's configured price.

Client flow example (book a sub-service)
1. Fetch artisan offerings: `GET /api/artisan-services/me` (artisan) or `GET /api/artisans/:id` to view profile.
2. Choose `categoryId` and `subCategoryId` from the artisan's offerings.
3. POST `/api/bookings` with `{ artisanId, schedule, categoryId, subCategoryId }` — server resolves `price` and creates booking.
