# ArtisanService — ID semantics and flow changes

Summary
- `ArtisanService.artisanId` now stores the underlying `User._id` (the `userId` from the `Artisan` document), not the `Artisan._id`.
- When an artisan creates or updates services, the server uses the authenticated user id (`req.user.id`) to resolve the associated `Artisan` and stores `ArtisanService.artisanId = artisan.userId`.
- Public listing endpoints accept either an `Artisan._id` or a `User._id` for backward compatibility; the server will resolve to the artisan's `userId` before querying `ArtisanService`.

Why this change
- Bookings, quotes, reviews and many other models use `User._id` as the source-of-truth for the person performing work.
- Using `User._id` in `ArtisanService` avoids cross-model mismatches (previously some flows used `Artisan._id` and others `User._id`, causing missing lookups like "No services configured").

What changed (developer-facing)
- Server behavior
  - Create/update (artisan): `POST /artisan-services` (artisan-only) will ignore any client-supplied `artisanId` and use `req.user.id` to find `Artisan` and then store `artisan.userId` in `ArtisanService.artisanId`.
  - List mine (`GET /artisan-services/me`): queries `ArtisanService` where `artisanId = artisan.userId`.
  - Public list by artisan (`GET /artisan-services/artisan/:artisanId`): accepts either an `Artisan._id` or `User._id`. The handler resolves the artisan document and then queries by `artisan.userId`.
  - Search/listing (`searchArtisans` / `listArtisans`): service enrichment now queries `ArtisanService.artisanId` using the artisan `userId` values collected from `Artisan.userId`.
  - `getArtisan`: will attach `ArtisanService` docs by querying `artisan.userId`.

- Model
  - `src/models/ArtisanService.js`: `artisanId` ref changed to `User` (User._id). Existing documents must be migrated.

Migration
- A migration script `scripts/migrate-artisanservice-to-userid.js` was added to map existing `ArtisanService.artisanId` (which may contain Artisan._id values) to the corresponding `User._id` using `Artisan.userId`.
- Recommended steps:
  1. Run a dry-run locally to see which docs would change:

```bash
node scripts/migrate-artisanservice-to-userid.js --dry-run
```

  2. If output looks correct, run migration (ensure you have a backup):

```bash
node scripts/migrate-artisanservice-to-userid.js
```

Notes and compatibility
- Until migration is run, the server code attempts to be tolerant in public endpoints by resolving artisan identifiers (the public `listByArtisan` accepts either ID type). However internal flows (booking, quotes) must be updated to normalize incoming artisan identifiers to `User._id` — see "Booking" below.
- Admin override: currently artisan endpoints use `req.user.id`. Allowing admins to create services for other artisans is a separate change and is not yet implemented. If you want that, we can add an admin-only path or support an optional `artisanId` in the request body when the caller is an admin.

Booking and other flows
- Booking/quote handlers must lookup `ArtisanService` by `User._id` (the booking should store `artisanId` as `User._id`). If clients pass `Artisan._id`, the server must resolve it to the corresponding `Artisan.userId` before querying `ArtisanService`.
- There's an outstanding item: update `src/controllers/bookingController.js` to normalize artisan identifiers (accept `Artisan._id` or `User._id`, resolve to `User._id`) and ensure bookings store `artisanId` as the `User._id`.

Developer checklist
- [ ] Run the migration script in a staging environment and verify that `ArtisanService.artisanId` now contains `User._id`.
- [ ] Update frontend clients to stop sending `Artisan._id` for `artisanId` where possible and prefer `User._id` (user id from JWT payload).
- [ ] Patch booking and quote controllers to normalize incoming identifiers (I can implement this if you want).
- [ ] Optionally implement admin override for creating/updating `ArtisanService`.

Files touched
- Models: `src/models/ArtisanService.js`
- Controllers: `src/controllers/artisanServiceController.js`, `src/controllers/artisanController.js`
- Migration: `scripts/migrate-artisanservice-to-userid.js`

If you'd like, I can now:
- Implement admin override for artisan service creation (admin may set artisan by user id), and/or
- Patch booking handlers to normalize and use `User._id` for service lookups and bookings.

---

Detailed endpoint breakdowns and examples

1. Create / Update artisan services (artisan-only)
- Endpoint: `POST /artisan-services`
- Auth: `Authorization: Bearer <JWT>` (artisan role)
- Body (JSON):

```json
{
  "categoryId": "60f7f9c8b4d1f23a1c8b4567",
  "services": [
    { "subCategoryId": "60f7fa12b4d1f23a1c8b4568", "price": 5000, "currency": "NGN", "notes": "Includes labor" },
    { "subCategoryId": "60f7fa38b4d1f23a1c8b4569", "price": 8000, "currency": "NGN" }
  ]
}
```

- Server behavior: the server resolves the authenticated user (`req.user.id`) → finds the `Artisan` doc for that user → stores `ArtisanService.artisanId = artisan.userId` (the `User._id`). Any `artisanId` provided by the client will be ignored for security.

- Success response (201/200):

```json
{
  "success": true,
  "data": {
    "_id": "6423a1b2c3d4e5f678901234",
    "artisanId": "611122223333444455556666",
    "categoryId": "60f7f9c8b4d1f23a1c8b4567",
    "services": [ { "subCategoryId": "60f7fa12b4d1f23a1c8b4568", "price": 5000, "currency": "NGN", "notes": "Includes labor" } ],
    "isActive": true,
    "createdAt": "2026-03-07T12:00:00.000Z"
  }
}
```

2. List my services (artisan)
- Endpoint: `GET /artisan-services/me`
- Auth: `Authorization: Bearer <JWT>` (artisan role)
- Response: array of `ArtisanService` docs filtered by `artisanId = artisan.userId`.

3. Public list for an artisan
- Endpoint: `GET /artisan-services/artisan/:artisanId`
- Parameter: `artisanId` may be either an `Artisan._id` (legacy) or a `User._id` (preferred).
- Behavior: the endpoint resolves an `Artisan` document by id or by `userId`, then queries `ArtisanService` using the resolved `artisan.userId`.
- Example request (client has only Artisan._id): `GET /artisan-services/artisan/60aabbccddeeff0011223344`
- Example response:

```json
{
  "success": true,
  "data": [
    {
      "_id": "6423a1b2c3d4e5f678901234",
      "artisanId": "611122223333444455556666",
      "categoryId": { "_id": "60f7f9c8b4d1f23a1c8b4567", "name": "Plumbing" },
      "services": [ { "subCategoryId": { "_id": "60f7fa12b4d1f23a1c8b4568", "name": "Tap Repair" }, "price": 5000 } ],
      "isActive": true
    }
  ]
}
```

4. How booking should use services (service-based booking)

- Workflow summary:
  1. Client picks an artisan (UI should prefer exposing `User._id` from the artisan's profile when possible). The JWT payload for the logged-in artisan or user contains the `user.id` value to use.
  2. Client requests available services for the artisan via `GET /artisan-services/artisan/:artisanId` (server resolves to `User._id` internally).
  3. Client displays service options and prices (trusted source: server-provided prices). The client should send only the selected `service` items (subCategoryId, quantity) and the `artisanId` (preferably `User._id`) when creating a booking.
  4. Booking creation endpoint must normalize the `artisanId` before looking up `ArtisanService`:

```js
// bookingController (conceptual)
const artisanParam = req.body.artisanId || req.params.artisanId;
// If client passed an Artisan._id, resolve to Artisan.userId
const artisanDoc = await Artisan.findById(artisanParam) || await Artisan.findOne({ userId: artisanParam });
const artisanUserId = artisanDoc ? artisanDoc.userId : artisanParam;
// Use artisanUserId (User._id) to find services
const svc = await ArtisanService.findOne({ artisanId: artisanUserId, categoryId });
// compute totals from svc.services (server-authoritative)
```

- Booking request example (client sends):

```json
{
  "artisanId": "611122223333444455556666",
  "items": [ { "subCategoryId": "60f7fa12b4d1f23a1c8b4568", "quantity": 1 } ],
  "scheduledAt": "2026-03-15T09:00:00.000Z",
  "location": { "address": "123 Main St", "coordinates": [3.45, 6.78] }
}
```

- Booking server responsibilities (must):
  - Normalize `artisanId` to `User._id`.
  - Load `ArtisanService` for the `artisanUserId` and requested `subCategoryId`.
  - Compute item prices and totals server-side using the authoritative `ArtisanService.services` prices.
  - Reject or adjust bookings if requested subCategoryId is not offered by the artisan.

Example server booking response (successful):

```json
{
  "success": true,
  "data": {
    "bookingId": "70a1b2c3d4e5f67890123456",
    "artisanId": "611122223333444455556666",
    "items": [ { "subCategoryId": "60f7fa12b4d1f23a1c8b4568", "price": 5000, "quantity": 1 } ],
    "subtotal": 5000,
    "serviceCharge": 500,
    "total": 5500,
    "status": "pending"
  }
}
```

5. Admin override (optional)

- Current state: admin override to create services for other artisans is not implemented. If enabled, two approaches are possible:
  - Add a separate admin-only endpoint `POST /admin/artisan-services` that accepts `artisanUserId` and behaves like `POST /artisan-services` but uses the supplied user id.
  - Extend `POST /artisan-services` to accept an optional `artisanId` when caller role is `admin` and validate the user id carefully.

Recommendations
- Run the migration in staging and verify client flows before deploying to production.
- Update frontend: whenever possible use `User._id` from the artisan's profile (`userId`) for API calls.
- Update booking/quote controllers to compute prices from `ArtisanService.services` and normalize `artisanId` (I can implement this normalization if you want).
 - The server now normalizes incoming `artisanId` values in booking endpoints: `hireAndInitialize` and `createBooking` call `resolveToUserId()` to accept either an `Artisan._id` or a `User._id` and convert it to the canonical `User._id` before querying `ArtisanService`.
 
 Example of the implemented helper (server-side):

```js
// src/controllers/bookingController.js
async function resolveToUserId(id) {
  if (!id) return null;
  // try as Artisan._id
  const byArtisanId = await Artisan.findById(id).lean();
  if (byArtisanId && byArtisanId.userId) return String(byArtisanId.userId);
  // try as Artisan.userId
  const byUserId = await Artisan.findOne({ userId: id }).lean();
  if (byUserId && byUserId.userId) return String(byUserId.userId);
  // try as User._id
  const UserModel = (await import('../models/User.js')).default;
  const u = await UserModel.findById(id).select('_id').lean();
  if (u) return String(u._id);
  return null;
}
```

What changed in booking flows
- `hireAndInitialize` and `createBooking` now:
  - resolve `incomingArtisanId` → `artisanUserId` via `resolveToUserId()`;
  - use `artisanUserId` to query `ArtisanService` and to persist `booking.artisanId`;
  - return 404 if `resolveToUserId()` cannot locate a matching artisan or user.

Why this keeps quote-based bookings working
- Quotes and job-quote flows already use `User._id` as the `artisanId` (or populate `booking.artisanId` as a user doc). By ensuring bookings store `booking.artisanId` as `User._id`, quote endpoints that compare or populate `booking.artisanId` continue to function correctly.

Testing notes
- Exercise these flows in staging:
  1. Create a booking using an `Artisan._id` and verify the booking is stored with `artisanId` = `User._id` and services/prices computed correctly.
  2. Create a booking using a `User._id` (JWT or direct param) and verify same behavior.
  3. Create/accept a quote for a booking and confirm payments and notifications behave as expected.

