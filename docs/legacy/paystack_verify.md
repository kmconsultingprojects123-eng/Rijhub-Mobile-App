# Paystack Setup Guide — Backend Integration

This guide is for the backend dev. The mobile app already handles payment flows correctly *if* Paystack is configured to redirect the WebView and notify the backend after payment. Right now Paystack isn't configured to do either reliably on **live**, which is why payments succeed on Paystack's side but the mobile app never knows about it.

API base URL (from mobile `.env`): `https://rijhub.com`

---

## What needs to exist

Two independent things, each on Paystack:

| Thing            | Purpose                                                                | Who consumes it                | Required for                                                  |
| ---------------- | ---------------------------------------------------------------------- | ------------------------------ | ------------------------------------------------------------- |
| **Callback URL** | Browser-side redirect after the user pays                              | The user's WebView             | Mobile WebView auto-closing & triggering verification         |
| **Webhook URL**  | Server-to-server POST from Paystack when a transaction event happens   | Backend (Node.js handler)      | Backend marking payments paid / emitting socket events to app |

They are **not** the same and they are **not** dependent on each other. Both should be configured for full reliability.

---

## 1. Callback URL

### Purpose

After a user successfully pays, Paystack redirects the WebView to this URL, automatically appending the transaction reference as a query param. The mobile WebView intercepts that redirect, extracts the reference, calls `POST /api/payments/verify` with it, and completes the booking.

### Endpoint to create

Create a single endpoint on `https://rijhub.com`:

```
GET /api/payments/callback
```

**It does not need to do anything meaningful.** The mobile WebView intercepts the navigation *before* the page actually loads. The endpoint just needs to exist (or return any 200) so the request doesn't 404 in the rare case the WebView lets it through. A minimal Express handler:

```js
// Express
app.get('/api/payments/callback', (req, res) => {
  // The mobile WebView reads `reference` and `trxref` from the URL itself.
  // We don't need to do verification here — that's what the mobile app
  // calls /api/payments/verify for, and what the webhook handles authoritatively.
  res.status(200).send(`
    <html>
      <body style="font-family: sans-serif; text-align: center; padding: 40px;">
        <h2>Payment received</h2>
        <p>You can return to the Rijhub app.</p>
      </body>
    </html>
  `);
});
```

The HTML body is only for users on a desktop browser who somehow land here. Mobile WebView never renders it.

### Telling Paystack about it

**Option A — Dashboard (fastest, no deploy):**

1. Log into Paystack → Settings → API Keys & Webhooks
2. Set **Callback URL** to: `https://rijhub.com/api/payments/callback`
3. Save. Do this for **both Test Mode and Live Mode** (top-right toggle).

**Option B — Per-transaction (in code, more flexible):**

Add `callback_url` to the body when calling Paystack's initialize endpoint. This overrides the dashboard default per transaction:

```js
// In the existing /api/payments/initialize handler, when calling Paystack:
const paystackResp = await axios.post(
  'https://api.paystack.co/transaction/initialize',
  {
    email,
    amount: amount * 100, // Paystack expects kobo
    metadata,
    callback_url: 'https://rijhub.com/api/payments/callback', // <-- add this
  },
  {
    headers: { Authorization: `Bearer ${process.env.PAYSTACK_SECRET_KEY}` },
  }
);
```

Either option works. Dashboard is recommended unless you need per-transaction overrides.

### What Paystack does with it

After successful payment, Paystack redirects the WebView to:
```
https://rijhub.com/api/payments/callback?reference=<ref>&trxref=<ref>
```

The mobile app's WebView intercepts this, sees `rijhub.com` is not a Paystack host, and pops with `success: true` and the reference.

---

## 2. Webhook URL

### Purpose

Paystack POSTs transaction events (`charge.success`, etc.) directly to your server. This is the source of truth — it fires reliably even if the user closes the app, has bad network, or the callback redirect fails. The mobile app already listens for socket events that come from this webhook (`payment_confirmed`, `booking_paid`); without the webhook, those socket events never fire.

### Endpoint to create

```
POST /api/webhooks/paystack
```

This endpoint must:
1. **Verify the request actually came from Paystack** by checking the `x-paystack-signature` header (HMAC-SHA512 of the raw body using your secret key).
2. **Respond with 200 immediately** (Paystack treats anything else as a delivery failure and retries — and it expects a fast response).
3. Process the event asynchronously: mark the payment paid in the DB, emit the socket event to the app, etc.

```js
// Express + crypto
const crypto = require('crypto');
const express = require('express');

// IMPORTANT: get raw body for signature verification.
// Mount this BEFORE express.json() for this route, or use express.raw():
app.post(
  '/api/webhooks/paystack',
  express.raw({ type: 'application/json' }),
  async (req, res) => {
    const secret = process.env.PAYSTACK_SECRET_KEY;
    const signature = req.headers['x-paystack-signature'];
    const expected = crypto
      .createHmac('sha512', secret)
      .update(req.body) // raw Buffer
      .digest('hex');

    if (signature !== expected) {
      return res.status(401).send('invalid signature');
    }

    // Acknowledge fast, then process.
    res.sendStatus(200);

    let event;
    try {
      event = JSON.parse(req.body.toString('utf8'));
    } catch {
      return;
    }

    if (event.event === 'charge.success') {
      const data = event.data;
      const reference = data.reference;
      const metadata = data.metadata || {};
      const bookingId = metadata.bookingId;
      const specialRequestId = metadata.specialRequestId;

      // 1. Mark the payment paid in DB (idempotent — webhook can be retried).
      // 2. If linked to a booking, mark booking.paymentStatus = 'paid'.
      // 3. Emit a socket event to the relevant user so the mobile app
      //    can complete the booking flow:
      //
      //    io.to(userId).emit('payment_confirmed', {
      //      bookingId,
      //      specialRequestId,
      //      reference,
      //    });
    }
  }
);
```

### Telling Paystack about it

**Dashboard:**

1. Settings → API Keys & Webhooks
2. Set **Webhook URL** to: `https://rijhub.com/api/webhooks/paystack`
3. Save for **both Test Mode and Live Mode**. (The screenshot showed live had no webhook configured — that's the immediate gap to close.)

You can hit "Test Webhook" on the dashboard to fire a sample event and confirm your endpoint responds 200.

---

## 3. Verify endpoint (already exists, just confirming the contract)

The mobile app calls `POST /api/payments/verify` with `{ "reference": "<ref>" }` after the WebView closes. The backend should:

1. Call `GET https://api.paystack.co/transaction/verify/<reference>` with the secret key.
2. Return a response the mobile parses. The mobile accepts any of these shapes as success (so be liberal):
   ```json
   { "success": true,  "data": { "status": "success" } }
   { "ok": true,       "data": { "status": "success" } }
   { "data": { "status": "success" } }
   { "data": { "paymentStatus": "paid" } }
   ```
3. On the same call, if the payment is verified and not yet processed, mark the booking paid in the DB (in case the webhook hasn't arrived yet — verify is the fallback).

---

## 4. Putting it together — checklist

For both **Test Mode** and **Live Mode** on Paystack:

- [ ] **Callback URL** = `https://rijhub.com/api/payments/callback` is set on the dashboard.
- [ ] `GET /api/payments/callback` exists on the backend and returns 200.
- [ ] **Webhook URL** = `https://rijhub.com/api/webhooks/paystack` is set on the dashboard.
- [ ] `POST /api/webhooks/paystack` exists, verifies the `x-paystack-signature`, returns 200 immediately, processes `charge.success` events.
- [ ] On `charge.success`, backend marks the booking/payment paid **and** emits a socket event (`payment_confirmed` / `booking_paid`) to the relevant user.
- [ ] `POST /api/payments/verify` works and returns one of the success shapes above.
- [ ] (Optional) `callback_url` is also passed in the body of `https://api.paystack.co/transaction/initialize` for per-transaction control.

---

## 5. How to test end-to-end

After deploying:

1. In the mobile app, start a booking payment that opens the Paystack WebView.
2. Pay with a Paystack test card (`4084 0840 8408 4081`, any future date, any 3-digit CVV, OTP `123456`).
3. **Expected:**
   - The WebView auto-closes within ~1s of pressing the final "Pay" button.
   - The app shows "Payment verified!" and opens the rating sheet.
   - Mobile logs show:
     ```
     PaymentWebView[onNavigationRequest]: https://rijhub.com/api/payments/callback?reference=...&trxref=...
     PaymentWebView[match=success on onNavigationRequest] reference=... url=...
     MessageClient: WebView returned result: {success: true, ...}
     MessageClient: verifying payment reference ... via https://rijhub.com/api/payments/verify
     MessageClient: payment verify response 200 ...
     ```
4. Repeat in **Live Mode** with a real card to confirm parity.

If the WebView still doesn't auto-close, the callback URL isn't being applied — check (a) it's saved on the correct mode (Test vs Live), (b) it's not being overridden by `callback_url` in the initialize body pointing somewhere else.

---

## 6. Common pitfalls

- **Webhook configured on Test only, not Live.** This was the immediate issue. Always configure both modes identically.
- **Webhook endpoint takes too long to respond.** Paystack expects 200 quickly; do work async after responding.
- **`express.json()` parsing the body before signature verification.** Use `express.raw()` on the webhook route specifically — signature verification needs the raw bytes.
- **Treating callback URL as authoritative.** It's a UX signal only. Always trust the webhook + verify endpoint, never the callback redirect alone, for marking payments as paid.
- **Different secret keys between modes.** Test and Live secret keys are different — make sure the webhook signature verification uses the right one for the current mode. Easiest: use the live key in production, the test key in staging, both sourced from environment variables.

---

## 7. Mobile app behavior summary (for reference)

The mobile app already does the following — no changes needed once the above is in place:

- Opens Paystack `authorization_url` returned by `/api/payments/initialize` in a WebView.
- Watches every URL the WebView navigates to. As soon as it sees a non-paystack host with a `reference` query param, it pops the WebView and proceeds.
- After the WebView closes — *regardless* of whether it returned `success: true` or `false` — the app calls `POST /api/payments/verify` with the reference (defense-in-depth so the user doesn't get stuck if the redirect fails).
- Listens for `payment_confirmed` / `booking_paid` socket events from the webhook handler. If the WebView is already closed when the socket arrives, it auto-completes the booking.

So: backend sets up the callback + webhook, mobile is already ready to receive both signals.
