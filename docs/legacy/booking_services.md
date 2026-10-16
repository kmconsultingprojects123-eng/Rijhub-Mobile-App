# Booking Services API

This document describes the updated booking endpoints which support selecting multiple sub-services (e.g., "Mechanic" -> "Oil Change", "Brake Check", "Tire Rotation") and server-side total calculation.

## Summary
- No new endpoint is required: the existing endpoints accept a `services` array.
- Endpoints affected:
  - `POST /api/bookings` — create a booking (used by standard booking flow)
  - `POST /api/bookings/hire` — create booking + initialize payment (Paystack)

Both endpoints now accept an optional `services` array. When provided, the server will:
1. Validate each `subCategoryId` against the artisan's configured `ArtisanService` prices for the given `categoryId`.
2. Compute `unitPrice`, `quantity` and `totalPrice` per selected sub-service.
3. Sum the totals to produce a server-trusted `price` for the booking (client-supplied price is ignored).
4. Persist the normalized `services` array on the `Booking` record.

## Request: `services` payload
- Type: array of objects
- Each item:
  - `subCategoryId` (string, required): ObjectId of the `JobSubCategory`.
  - `quantity` (integer, optional, default 1): Number of units for that service.

Example (client):

```json
POST /api/bookings
Content-Type: application/json
Authorization: Bearer <JWT>

{
  "artisanId": "605c...",
  "categoryId": "606d...",
  "services": [
    { "subCategoryId": "60a1...", "quantity": 1 },
    { "subCategoryId": "60a2...", "quantity": 2 }
  ],
  "schedule": "2026-03-01T10:00:00Z",
  "notes": "Please bring parts",
  "email": "customer@example.com"
}
```

## Server behavior
- The server looks up the artisan's `ArtisanService` document for the given `artisanId` and `categoryId`.
- For each selected `subCategoryId`, the server finds the configured price and computes `unitPrice * quantity`.
- The server sets `booking.price` to the summed total, and stores a normalized `services` array on the booking document with these fields:
  - `subCategoryId`, `name`, `unitPrice`, `quantity`, `totalPrice`.
- The server will ignore any client-supplied `price` when `services` is present.

## Response (success)
The booking creation response contains the persisted `booking` object (including `services` and `price`) — example:

```json
HTTP/1.1 201 Created
{
  "success": true,
  "data": {
    "_id": "623...",
    "artisanId": "605c...",
    "service": "Oil Change, Brake Check",
    "services": [
      { "subCategoryId": "60a1...", "name": "Oil Change", "unitPrice": 3000, "quantity": 1, "totalPrice": 3000 },
      { "subCategoryId": "60a2...", "name": "Brake Check", "unitPrice": 1500, "quantity": 2, "totalPrice": 3000 }
    ],
    "price": 6000,
    "schedule": "2026-03-01T10:00:00Z",
    "notes": "Please bring parts",
    "createdAt": "2026-02-28T..."
  }
}
```

## Client integration notes for mobile developers
- Render the `JobSubCategory` list (from `/api/job-subcategories?category=<id>`), show each item's price, and let users select multiple items and quantities.
- For a good UX show a live total computed client-side from the fetched prices, but always use the server-provided `price` from the booking response as authoritative.
- Submit `services` as an array of `{ subCategoryId, quantity }`.
- The `hire` endpoint (`POST /api/bookings/hire`) accepts the same `services` payload and will return payment initialization details when Paystack is enabled.

## Validation and errors
- If any `subCategoryId` is not offered by the artisan, the server will respond with `400` and an error message.
- If `categoryId` is omitted when sending `services`, the server will respond with `400`.

## Suggested UI flow
1. User taps a category (e.g., Mechanic).
2. Fetch sub-services for that category and the selected artisan.
3. User toggles services and sets quantities.
4. Show live total (client-calculated) and a confirmation screen.
5. Submit `services` to booking endpoint; on success use returned `price` to show final total and proceed to payment if required.

---
If you want I can also add a short sample mobile component snippet (React Native) or attach the exact example IDs pulled from a test DB. 