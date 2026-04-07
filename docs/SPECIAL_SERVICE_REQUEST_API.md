**Special Service Requests (Server) — API & Notes

- **Purpose:** Allow clients to create ad-hoc service requests for artisans, enable artisans to respond (quote/message), and let clients accept responses which creates a `Booking` + optional payment initialization.

**Model (storage)
- **Collection:** specialservicerequests
- **Mongoose model:** `SpecialServiceRequest` (see `src/models/SpecialServiceRequest.js`)
- **Key fields:**
  - **artisanId:** ObjectId (ref User)
  - **clientId:** ObjectId (ref User)
  - **description, title, location, date, time**: request details
  - **urgency:** enum ['Normal','High','Low'] (controller normalizes inputs like "urgent" → 'High')
  - **attachments:** array of `{ url, filename, mimeType }` (populated by Cloudinary stream middleware)
  - **status:** enum ['pending','responded','accepted','confirmed','in_progress','completed','cancelled','rejected','declined']
  - **artisanReply:** { quote, message, responseAt, artisanId } — contains the artisan's response/quote
  - **bookingId:** ObjectId (ref Booking) — set when client accepts and booking is created

**Routes (prefix: `/api/special-service-requests`)
- POST `/` — Create request
  - Auth: Bearer token (role: `client` or `customer`)
  - Supports `application/json` OR `multipart/form-data` with attachments.
  - NOTE: create route intentionally has no body JSON schema to allow multipart parsing.
  - Example body (JSON):
    ```json
    {
      "artisanId":"609...",
      "description":"I need kitchen tiling",
      "title":"Kitchen tiling",
      "budget": 40000,
      "urgency":"Urgent"
    }
    ```
  - On create, server ensures `artisanReply` exists (empty object) and notifies artisan.

- GET `/` — List requests
  - Auth: Bearer token
  - Query filters: `artisanId`, `clientId`, `status`, `page`, `limit`

- GET `/:id` — Get single request
  - Auth: Bearer token

- GET `/:id/response` — Same as `GET /:id` (keeps client code that expects `/response` working)
  - Auth: Bearer token

- PUT `/:id` — Update request (generic; respond/accept can be done here)
  - Auth: Bearer token
  - Body: may include `status`, `note`, `urgency`, `attachments`, etc.
  - Use for admin or owners to perform updates.

- PUT `/:id/response` — Artisan-specific response (delegates to existing update handler)
  - Auth: Bearer token (artisan role required)
  - Body: set `status: "responded"` and `note` (JSON string or object) — controller parses `note` into `artisanReply.quote` and `artisanReply.message`.

- POST `/:id/response` — New convenience endpoint (artisan-only)
  - Auth: Bearer token (artisan role required)
  - Body example:
    ```json
    {
      "note": { "quote": "50000", "message": "Ready to start" },
      "urgency": "urgent"
    }
    ```
  - Behavior: idempotent create/update of `artisanReply`, sets `status: 'responded'`, updates `responseAt`, and notifies client.

  - Artisan quote options
    - Fixed price: send `{ "note": { "quote": 50000, "message": "..." } }`. This sets a single fixed `quote`.
    - Price range: send `{ "note": { "min": 30000, "max": 70000, "message": "..." } }`. The server will store `minQuote`/`maxQuote`, set `quoteType: "range"` and generate 5 evenly spaced `options` (numbers) for the client to choose from.
    - Example range request:
      ```json
      { "note": { "min": 30000, "max": 70000, "message": "I can do this, choose a price" } }
      ```
    - The generated `options` are stored on `artisanReply.options` (array of 5 integers).

- POST `/:id/pay` — Initialize payment for a special request's booking
  - Auth: Bearer token (owner of booking / client required)
  - Body: optional `{ "email": "buyer@example.com" }` (only required if booking customer email is not present)
  - Behavior: initializes a Paystack transaction for the `Booking` linked to the special request (creates a `Transaction` with status `pending` on success) and returns the Paystack initialize payload. Useful when payment init did not complete during the accept flow or when re-initializing payment.

**Accepting a response (client)
- Action: client updates request to `status: 'accepted'` (PUT `/:id` or same update flow)
- Behavior:
  - Idempotency: if `bookingId` already exists, server returns the existing booking.
  - Price selection: the server will compute the effective price using precedence `selectedPrice` → fixed `quote` → first `options` → `budget`.
    - To select a price from a range, send `{ "status": "accepted", "selectedPrice": 45000 }` in the PUT body.
    - Deferred booking creation on accept: when a client accepts a response the server will set the `SpecialServiceRequest.status` to `accepted` and will NOT create a `Booking` immediately. This prevents creating bookings until payment is confirmed.
    - Payment initialization: if `PAYSTACK_SECRET_KEY` is configured the server will attempt to initialize a Paystack transaction and create a local `Transaction` (status: `pending`). The Paystack init payload includes metadata `{ specialRequestId, selectedPrice }` (note: no `bookingId` when booking is deferred) so the gateway/webhook or verify endpoint can create the booking idempotently once payment is successful.
    - The initial `PUT /:id` response will typically return the updated `request`, `booking: null` (since booking is created only after payment confirmation), and the optional `payment` object (may be `null` if initialization failed or Paystack is not configured). Clients that do not receive a `payment` object should call `POST /:id/pay` to initialize payment explicitly. Notifications are sent to both parties indicating payment is required.

**Multipart uploads
- Multipart files are streamed to Cloudinary by `src/middlewares/cloudinaryStream.js`. Use `multipart/form-data` with file fields; the middleware populates `request.uploadedFiles` and the controller stores `attachments`.
- Important: create route intentionally omits body JSON schema so Fastify does not validate before multipart parsing.

**Client API examples (create request)**

1) JSON request (fields + optional image URLs)

Request (JSON):
```bash
curl -X POST "https://yourhost/api/special-service-requests" \
  -H "Authorization: Bearer <CLIENT_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "artisanId": "609...",
    "service": "Tiling",
    "serviceDescription": "Tiling for kitchen floor",
    "location": "Lagos, Nigeria",
    "date": "2026-04-10T09:00:00.000Z",
    "time": "09:00",
    "urgency": "Urgent",
    "imageUrls": ["https://example.com/photo1.jpg"],
    "budget": 45000
  }'
```

Notes:
- `service` maps to `categoryName`/`title` when `title` is not provided.
- `serviceDescription` maps to `description` when `description` is not provided.

2) Multipart/form-data (upload files)

Request (multipart with file fields):
```bash
curl -X POST "https://yourhost/api/special-service-requests" \
  -H "Authorization: Bearer <CLIENT_TOKEN>" \
  -F "artisanId=609..." \
  -F "service=Tiling" \
  -F "serviceDescription=Tiling for kitchen floor" \
  -F "location=Lagos, Nigeria" \
  -F "date=2026-04-10T09:00:00.000Z" \
  -F "time=09:00" \
  -F "urgency=Normal" \
  -F "budget=45000" \
  -F "files[]=@/path/to/photo1.jpg" \
  -F "files[]=@/path/to/photo2.jpg"
```

Notes for multipart:
- Files are streamed to Cloudinary by `src/middlewares/cloudinaryStream.js`.
- Uploaded files become `req.uploadedFiles` and are merged into the `attachments` array on the created document.

3) Example server response (created request)

```json
{
  "success": true,
  "data": {
    "_id": "69ce8179f7ad7248149c7867",
    "artisanId": "609...",
    "clientId": "699...",
    "title": "Tiling",
    "description": "Tiling for kitchen floor",
    "location": "Lagos, Nigeria",
    "date": "2026-04-10T09:00:00.000Z",
    "urgency": "High",
    "attachments": [{ "url": "https://res.cloudinary.com/.../photo1.jpg", "filename": "photo1.jpg" }],
    "artisanReply": {},
    "status": "pending",
    "createdAt": "2026-04-03T18:00:00.000Z"
  }
}
```

API JSON examples

- Accept request (client) — `PUT /api/special-service-requests/:id`

Request body:
```json
{
  "status": "accepted",
  "selectedPrice": 45000
}
```

Example response when payment initialization completed in time (booking deferred; payment initialized):

```json
{
  "success": true,
  "data": {
    "request": { "_id": "69ce...", "status": "accepted", "bookingId": null },
    "booking": null,
    "payment": {
      "authorization_url": "https://checkout.paystack.co/abcd...",
      "access_code": "xyz",
      "reference": "PSK_123456789"
    }
  }
}
```

Example response when payment init did not complete (or Paystack not configured):

```json
{
  "success": true,
  "data": {
    "request": { "_id": "69ce...", "status": "accepted", "bookingId": null },
    "booking": null,
    "payment": null
  }
}
```


4) Read the artisan response

After the artisan responds (fixed or range), client fetches the updated request:
```bash
curl -H "Authorization: Bearer <CLIENT_TOKEN>" "https://yourhost/api/special-service-requests/69ce8179f7ad7248149c7867/response"
```

The returned JSON includes `artisanReply` with `quoteType`, `quote` or `minQuote`/`maxQuote`/`options`, and `message`.

**How the client sees an artisan response**

When an artisan responds, the client can fetch the request (`GET /:id` or `GET /:id/response`) and will receive the `artisanReply` object. Examples below show the two common cases.

- Fixed price response (artisan set a single price):

```json
{
  "_id": "69ce...",
  "status": "responded",
  "artisanReply": {
    "quoteType": "fixed",
    "quote": 50000,
    "message": "I can do this for a fixed price",
    "responseAt": "2026-04-05T19:00:00.000Z",
    "artisanId": "609..."
  }
}
```

- Range response (artisan provided a min/max and server generated 5 options):

```json
{
  "_id": "69ce...",
  "status": "responded",
  "artisanReply": {
    "quoteType": "range",
    "minQuote": 30000,
    "maxQuote": 70000,
    "options": [30000, 40000, 50000, 60000, 70000],
    "message": "Choose a price that suits you",
    "responseAt": "2026-04-05T19:00:00.000Z",
    "artisanId": "609..."
  }
}
```

Client next steps:
- If `quoteType` is `fixed`, the client can accept by calling `PUT /:id` with `{ "status":"accepted" }` (or include `selectedPrice` equal to the fixed quote). The server will create a `Booking` and proceed to payment initialization if configured.
- If `quoteType` is `range`, the client can pick one of the `options` and accept by calling `PUT /:id` with `{ "status":"accepted", "selectedPrice": <one_of_options> }`.
- Alternatively, an artisan may update the request later and convert a range into a fixed quote (posting a fixed `quote`), in which case the client will see a fixed `quote` on subsequent GETs.

Security & validation notes:
- The server validates `selectedPrice` when accepting and will use the precedence: `selectedPrice` → fixed `quote` → first `options` value → request `budget` when creating a booking.
- Only the request `clientId` may accept (`403` otherwise).

**Client payment flow (step-by-step) — web & Flutter examples**

Flow summary:
1. Client reviews `artisanReply` via `GET /api/special-service-requests/:id`.
2. Client accepts a quote by calling `PUT /api/special-service-requests/:id` with `{ "status": "accepted", "selectedPrice": <number> }` when applicable.
3. Server computes the price and starts payment initialization if `PAYSTACK_SECRET_KEY` is configured. The server will NOT create the `Booking` on accept; instead it initializes payment with metadata containing `specialRequestId` and `selectedPrice`. The `Booking` is created idempotently by the webhook/verify flow only after the gateway reports a successful payment. The `PUT` response includes a `payment` object and `booking: null` when initialization completed in time.
4. If the `payment` object is present it contains Paystack's `authorization_url` and `reference`; client must open `authorization_url` (web redirect or in-app browser) to complete payment.
5. If `payment` is `null`, client should call `POST /api/special-service-requests/:id/pay` to explicitly initialize payment (pass `{ "email": "buyer@example.com" }` in the body if booking customer email is not present). The endpoint returns the Paystack init payload on success.
6. Paystack webhook notifies the server; server updates `Transaction` and advances booking lifecycle. Client can poll `GET /api/bookings/:id` to observe status changes.

Important: the `payment` object returned by the server (either from the `PUT` accept call or from `POST /:id/pay`) is the Paystack initialize response and contains `authorization_url`, `reference`, and other metadata. If initialization fails or Paystack is not configured the `payment` field will be `null`.

Web (JavaScript) example — accept then redirect to Paystack:
```javascript
// Accept selected price and redirect to Paystack (if payment init returned)
async function acceptAndPay(requestId, token, selectedPrice) {
  const res = await fetch(`/api/special-service-requests/${requestId}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
    body: JSON.stringify({ status: 'accepted', selectedPrice })
  });
  const payload = await res.json();
  if (!payload.success) throw new Error(payload.message || 'Accept failed');
  const payment = payload.data.payment;
  if (payment && payment.authorization_url) {
    // Open Paystack checkout
    window.location.href = payment.authorization_url;
    return;
  }
  // If payment wasn't returned, explicitly initialize it and then redirect
  const payRes = await fetch(`/api/special-service-requests/${requestId}/pay`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` } });
  const payPayload = await payRes.json();
  if (payPayload.success && payPayload.data && payPayload.data.payment && payPayload.data.payment.authorization_url) {
    window.location.href = payPayload.data.payment.authorization_url;
    return;
  }
  // Fallback: return booking info so UI can instruct manual payment
  return payload.data;
}

// Optional: poll booking status after redirect/back
async function pollBookingStatus(bookingId, token, onUpdate) {
  const max = 30; let i = 0;
  while (i++ < max) {
    const r = await fetch(`/api/bookings/${bookingId}`, { headers: { Authorization: `Bearer ${token}` } });
    const j = await r.json();
    if (j.success && j.data && j.data.status && j.data.status !== 'pending') {
      onUpdate(j.data);
      break;
    }
    await new Promise(resolve => setTimeout(resolve, 3000));
  }
}
```

**Paystack UX: opening checkout & redirects**

- When the server returns a `payment` object (the Paystack initialize response) the app must open the provided `authorization_url` so the user can complete payment.
- Mobile apps: prefer opening `authorization_url` in an in-app browser or system browser that supports a redirect back to your app (custom URI scheme or universal link). After the user completes/aborts payment Paystack will redirect to the configured callback URL — your app should detect the redirect and resume by polling the booking/request status or calling the `verify` endpoint with the returned `reference`.
- Web apps: redirect the browser to `authorization_url` (or open a new tab). After redirect back, call `POST /api/payments/verify` with the Paystack `reference` or poll the booking endpoint.
- UX note: do not assume immediate booking creation — in the deferred flow the server creates the `Booking` only when the gateway confirms payment (webhook or `verify`). The client should show a loading state and poll `GET /api/special-service-requests/:id` or `GET /api/bookings/:id` until the booking appears/updates.

**Metadata used for deferred special-request payments**

- When initializing Paystack for a special request the server attaches metadata like:

```json
{
  "specialRequestId": "69ce8179f7ad7248149c7867",
  "selectedPrice": 45000
}
```

- Important: in the deferred flow the server does NOT include a `bookingId` in metadata because the `Booking` does not exist yet. The webhook/verify flow uses `specialRequestId` to create the booking idempotently once payment succeeds.

**Verify & webhook — how it works**

- Paystack webhook: when Paystack posts `charge.success` the server validates the `x-paystack-signature`, reads `data.metadata`, and if `specialRequestId` is present it will create (or reuse) a `Booking` for that request, set `booking.paymentStatus = 'paid'`, set `SpecialServiceRequest.status = 'confirmed'`, attach the `bookingId` to the request, create a `Chat` if missing, create a holding `Transaction`, and notify the artisan and client.
- Manual verify: your app can call `POST /api/payments/verify` with JSON `{ "reference": "PSK_123456789" }`. The server will call Paystack `/transaction/verify/:reference` and run the same idempotent booking/transaction logic as the webhook. Use `verify` when webhooks are delayed/missed or when testing locally.
- Signature testing: to test webhooks locally include the correct `x-paystack-signature` header (HMAC-SHA512 of the raw JSON body using `PAYSTACK_SECRET`) — an example is included earlier in this doc.
Flutter example (launch URL + poll status):
```dart
// pubspec: add http, url_launcher
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher_string.dart';

Future<void> acceptAndPay(String requestId, String token, int selectedPrice) async {
  final res = await http.put(Uri.parse('https://yourhost/api/special-service-requests/$requestId'),
    headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
    body: '{"status":"accepted","selectedPrice":$selectedPrice}');
  final payload = jsonDecode(res.body);
  if (!payload['success']) throw Exception(payload['message'] ?? 'Accept failed');
  var payment = payload['data']['payment'];
  // If payment wasn't returned, initialize explicitly
  if (payment == null) {
    final payRes = await http.post(Uri.parse('https://yourhost/api/special-service-requests/$requestId/pay'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'});
    final payPayload = jsonDecode(payRes.body);
    if (payPayload['success'] && payPayload['data'] != null) {
      payment = payPayload['data']['payment'];
    }
  }
  if (payment == null) return; // handle external payment fallback
  final authUrl = payment['authorization_url'];
  // launch in external browser or in-app webview
  await launchUrlString(authUrl);
  // Optionally poll booking status (GET /api/bookings/:id) after payment completes
}
```

Webhook / server confirmation:
- Paystack will call your configured webhook URL with payment status. The server updates `Transaction` and booking status accordingly.
- You can also use `POST /api/bookings/:id/confirm-payment` for admin/webhook-driven confirmation flows.

Payment verification
- The server exposes an authoritative verify endpoint: `POST /api/payments/verify` which accepts JSON `{ "reference": "<paystack_reference>" }`.
- Use this endpoint to force reconciliation when a webhook was missed or delayed. The endpoint calls Paystack `/transaction/verify/:reference` and runs the same booking/transaction update logic as the webhook (idempotent).

Example: verify by reference (curl)
```bash
curl -X POST "https://your-server/api/payments/verify" \
  -H "Content-Type: application/json" \
  -d '{"reference":"PSK_123456789"}'
```

Webhook simulation (Paystack signature)
- To test your webhook handler locally or from a tool, send Paystack-like payloads and include the correct `x-paystack-signature` header. The signature is HMAC-SHA512 of the raw JSON body using `PAYSTACK_SECRET`.

Example (bash + openssl):
```bash
payload='{"event":"charge.success","data":{"reference":"PSK_123456789","metadata":{"bookingId":"<BOOKING_ID>"}}}'
signature=$(printf '%s' "$payload" | openssl dgst -sha512 -hmac "$PAYSTACK_SECRET" | sed 's/^.* //')
curl -X POST https://your-server/api/payments/webhook \
  -H "Content-Type: application/json" \
  -H "x-paystack-signature: $signature" \
  -d "$payload"
```

Expected webhook behavior:
- `paymentWebhook` validates the signature, processes `charge.success`, marks the `Transaction` as `holding`, creates or attaches a `Booking` if metadata indicates a `quoteId`/`jobId`, sets `booking.paymentStatus = 'paid'`, creates a `Chat` if missing, and sends notifications to the artisan.

If you prefer, the `verify` endpoint is the simplest reconciliation route when testing manually.


**Urgency normalization
- Controller normalizes common inputs: e.g. `urgent` or `Urgent` → 'High', `low` → 'Low', otherwise 'Normal'. This prevents Mongoose enum validation errors.

**Backfill (DB) tips
- To find docs missing `artisanReply`:
  ```js
  db.specialservicerequests.find({ artisanReply: { $exists: false } })
  ```
- Backfill to add empty artisanReply:
  ```js
  db.specialservicerequests.updateMany({ artisanReply: { $exists: false } }, { $set: { artisanReply: {} } })
  ```
- To list requests with responses:
  ```js
  db.specialservicerequests.find({ 'artisanReply.responseAt': { $exists: true } })
  ```

**Notes & operational points
- `artisanReply` is stored inside the `specialservicerequests` collection — not a separate collection.
- Keep `RegistrationOtp`/OTP provider changes separate — unrelated but implemented in this release.
- Tests: exercise flows: create (multipart + json), artisan respond (POST `/response`), client accept → booking + payment initialization.

**Files to review in codebase
- `src/models/SpecialServiceRequest.js` — schema
- `src/controllers/specialServiceRequestController.js` — create / respond / accept logic
- `src/routes/specialServiceRequestRoutes.js` — route bindings
- `src/middlewares/cloudinaryStream.js` — multipart → Cloudinary handling

**Next steps (optional)
- Add content-type gated validation so JSON clients are validated while multipart clients are allowed.
- Add integration tests for the end-to-end flow.