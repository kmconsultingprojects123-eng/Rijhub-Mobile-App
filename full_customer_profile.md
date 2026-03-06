# Full Customer Profile (aggregated)

Overview

Provides a single aggregated view of a customer's data across multiple collections (transactions, bookings, jobs, quotes, notifications, reviews, applications, chats).

Endpoint
- `GET /api/users/:id/full` — returns counts and paginated arrays for related resources.

Pagination
- Cursor-based pagination is used; the response returns `cursors` for each collection (ISO timestamps). Pass `?transactionsCursor=...&jobsCursor=...` as needed to fetch the next page of that collection.

Response shape (summary)
- `counts`: object with totals per collection
- `data`: object with arrays for `transactions`, `bookings`, `jobs`, `quotes`, `notifications`, `reviews`, `applications`, `chats`
- `cursors`: next-cursor values per collection

Notes
- Many subdocuments are populated (e.g., `Job.clientId`, `Booking.artisanId`) to make the client payloads friendly.
