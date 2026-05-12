# Booking Payment Mode Flow

This document summarizes the current booking payment architecture after the new `paymentMode` support was added. It is intended for the Flutter team so they can integrate front-end behavior correctly.

## Core concept

`Booking` now has a new field:

- `paymentMode`: one of `upfront` or `afterCompletion`

Default behavior: `upfront`.

Meaning:

- `upfront`: booking is created and payment is initialized immediately, as before.
- `afterCompletion`: booking is accepted without upfront payment. After the service is done, the customer must pay and the payment must be verified before the booking can be marked completed.

---

## Models / data

### Booking

Booking schema now includes:

- `paymentMode: { type: String, enum: ['upfront', 'afterCompletion'], default: 'upfront' }`
- `paymentStatus: 'unpaid' | 'paid'`
- `status` values unchanged: `pending`, `awaiting-acceptance`, `accepted`, `in-progress`, `completed`, `closed`, `cancelled`

### Transaction

Payments are still represented by `Transaction` records.

- `pending`: initialized but not yet confirmed
- `holding`: payment held in escrow
- `released`: completion has triggered payout processing
- `paid`: artisan payout or wallet credit has completed

---

## Booking creation flows

### 1. Direct booking (`POST /booking`)

Request can now include:

- `paymentMode: 'upfront' | 'afterCompletion'`

Behavior:

- `upfront`: booking is created, Paystack transaction initialization occurs, and a `Transaction` is recorded as `pending`.
- `afterCompletion`: booking is created and returned immediately. No immediate payment initialization occurs.

If Paystack is not configured, the booking is still created; payment must be handled externally.

Example request body (`afterCompletion`):

```json
{
  "artisanId": "642e9e2f8b3b4f0012345678",
  "schedule": "2026-04-25T10:00:00.000Z",
  "price": 4500,
  "notes": "Install the new kitchen faucet",
  "paymentMode": "afterCompletion"
}
```

Example response:

```json
{
  "success": true,
  "message": "Booking created with pay-after-service payment; customer must pay before completion.",
  "data": {
    "booking": {
      "_id": "644a1f2b8fa4d50045a1c2b3",
      "artisanId": "642e9e2f8b3b4f0012345678",
      "price": 4500,
      "status": "pending",
      "paymentMode": "afterCompletion",
      "paymentStatus": "unpaid"
    }
  }
}
```

### 2. Hire flow (`POST /booking/hire`)

This endpoint also accepts:

- `paymentMode: 'upfront' | 'afterCompletion'`

Behavior is the same as the direct booking flow.

Example request body:

```json
{
  "artisanId": "642e9e2f8b3b4f0012345678",
  "schedule": "2026-04-25T10:00:00.000Z",
  "price": 4500,
  "email": "customer@example.com",
  "paymentMode": "afterCompletion"
}
```

Example response:

```json
{
  "success": true,
  "data": {
    "booking": {
      "_id": "644a1f2b8fa4d50045a1c2b3",
      "artisanId": "642e9e2f8b3b4f0012345678",
      "price": 4500,
      "status": "pending",
      "paymentMode": "afterCompletion",
      "paymentStatus": "unpaid"
    }
  }
}
```

### 3. Quote-based booking acceptance

There are two quote flows:

#### a. Quote attached to an existing booking (`POST /booking/:id/quotes/:quoteId/accept`)

- Accepts optional `paymentMode`
- If `paymentMode === 'afterCompletion'`, the booking stays accepted but payment initialization is skipped.
- If `paymentMode !== 'afterCompletion'`, the existing flow initializes Paystack payment for the quote service charge.

Example request body:

```json
{
  "paymentMode": "afterCompletion"
}
```

Example response:

```json
{
  "success": true,
  "data": {
    "quote": {
      "_id": "644a2b3c7e6f450012345678",
      "status": "accepted"
    },
    "booking": {
      "_id": "644a1f2b8fa4d50045a1c2b3",
      "paymentMode": "afterCompletion",
      "paymentStatus": "unpaid"
    }
  }
}
```

#### b. Job-level quote accept (`POST /jobs/:id/quotes/:quoteId/accept`)

- Accepts optional `paymentMode`
- It marks the quote accepted and initializes payment.
- The actual `Booking` is created later after payment webhook confirmation, using related metadata.
- The selected `paymentMode` is preserved when the booking is created automatically from quote metadata.

Example request body:

```json
{
  "paymentMode": "afterCompletion"
}
```

Example response:

```json
{
  "success": true,
  "data": {
    "quote": {
      "_id": "644a2b3c7e6f450012345678",
      "status": "accepted"
    },
    "message": "Quote accepted; payment will be initialized when the booking is created from the webhook."
  }
}
```

### 4. Special service request payment flow

Special service request acceptance now defers booking creation until payment confirmation.

- When the request is accepted, payment initialization happens with metadata containing `specialRequestId`.
- The booking is created in the webhook path once payment succeeds.
- The new deferred payment support preserves `paymentMode` when creating the booking from metadata.

Example request body:

```json
{
  "paymentMode": "afterCompletion",
  "selectedPrice": 5200,
  "specialRequestId": "643b1c2d3e4f5a0012345678"
}
```

Example response:

```json
{
  "success": true,
  "data": {
    "specialRequest": {
      "_id": "643b1c2d3e4f5a0012345678",
      "status": "confirmed"
    },
    "message": "Payment initialized for special request; booking will be created after payment confirmation."
  }
}
```

---

## Pay-after-service flow

### `paymentMode: 'afterCompletion'` behavior

If a booking is created with `paymentMode: 'afterCompletion'`:

- The booking is created with `paymentStatus: 'unpaid'`.
- The booking does not initialize payment immediately.
- The artisan performs the service while the booking is `accepted` or `in-progress`.
- After the service is done, the customer pays using the deferred payment endpoint.
- Paystack verification/webhook must move the transaction to `holding`.
- Only after payment is verified can the customer mark the booking `completed`.
- Completion releases the held payment: company commission is kept and the artisan receives the remainder.

### Endpoint for pay-after-service payment initialization

- `POST /booking/:id/pay-after-completion`

Requirements:

- Booking must exist
- Booking must have `paymentMode === 'afterCompletion'`
- Booking status must be `accepted`, `in-progress`, or `completed`
- Booking must not already be `paid`

If Paystack is configured:

- It initializes a Paystack transaction for the booking amount.
- It creates a local `Transaction` record with status `pending`.

If Paystack is not configured:

- It creates a local pending `Transaction` record and returns a note that payment should be handled externally.

Example request body:

```json
{
  "email": "customer@example.com",
  "customerCoords": { "lat": 6.5244, "lon": 3.3792 }
}
```

Example response:

```json
{
  "success": true,
  "data": {
    "booking": {
      "_id": "644a1f2b8fa4d50045a1c2b3",
      "status": "in-progress",
      "paymentMode": "afterCompletion",
      "paymentStatus": "unpaid"
    },
    "payment": {
      "authorization_url": "https://checkout.paystack.com/abc123",
      "access_code": "abc123",
      "reference": "pf_1mx..."
    }
  }
}
```

### Artisan cancellation for after-completion bookings

- New endpoint: `POST /booking/:id/artisan-cancel`
- Only allowed for bookings with `paymentMode === 'afterCompletion'`
- Only allowed for the artisan who owns the booking
- Requires a cancellation `reason` in the request body
- Does not work for `upfront` bookings
- Cancels only unpaid/unfinished bookings; completed or already paid bookings are rejected
- If a pending or holding transaction exists, it is marked as `refunded`

---

## Booking completion and release

### Completing a booking

- Customer marks booking complete using `POST /booking/:id/complete`
- For `afterCompletion` bookings, the backend requires a verified `holding` transaction first.
- If payment has not been verified, the endpoint returns `400` and the booking remains uncompleted.
- The booking status moves to `completed`
- If a holding transaction exists, the payment release process begins

### Payment release behavior

There are two main release paths:

1. `bookingController.completeBooking()`
   - This releases a held transaction after booking completion.
   - It calculates company commission and handles payouts or internal wallet credit.

2. `paymentController.releaseCompletedDeferredBookingPayment()`
   - Safety path for deferred payments that are verified when the booking is already completed.
   - It also calculates commission and releases payment.

### Company commission

Yes — commission still works.

How it is applied:

- The system reads `COMPANY_FEE_PCT` from configuration.
- The commission is calculated from the total amount.
- The artisan receives the amount after commission.
- A `CompanyEarning` record is created for the fee.
- If `COMPANY_USER_ID` is configured, the company wallet is also credited.

This commission flow is applied both for upfront payments and for pay-after-service payments released on completion.

---

## Webhook and payment verification

### Paystack verification

The backend verifies Paystack transaction references via:

- `POST /payment/verify`

When a payment is confirmed, the code:

- marks the transaction `holding`
- links it to a booking if possible
- creates a booking from quote or special request metadata when necessary
- marks the booking `paid`
- ensures a chat exists
- notifies the artisan

### Booking creation from payment metadata

If the payment metadata contains:

- `quoteId` or `quote_id`
- `jobId` or `job_id`
- `specialRequestId` or `special_request_id`

Then the backend can create or attach a booking automatically.

The payment mode is preserved when bookings are created from metadata.

---

## What the Flutter developer needs to do

### 1. Send `paymentMode` where appropriate

- `POST /booking` (`create booking`)
- `POST /booking/hire`
- `POST /booking/:id/quotes/:quoteId/accept`
- `POST /jobs/:id/quotes/:quoteId/accept`
- `POST /job/:id/applications/:appId/accept` (if this route is used)

### 2. Use deferred payment flow when needed

For bookings with `paymentMode: 'afterCompletion'`, the front-end must:

- wait until the artisan has finished the service
- call `POST /booking/:id/pay-after-completion` while the booking is `accepted` or `in-progress`
- open Paystack checkout using the returned `authorization_url`
- call `POST /payment/verify` with the returned Paystack reference, or wait for the webhook to update the booking
- only call `POST /booking/:id/complete` after payment is verified and `booking.paymentStatus === 'paid'`

### 3. Handle `upfront` as existing flow

The `upfront` behavior that initializes payment immediately remains unchanged.

### 4. Payment confirmation

- If Paystack is used, the flow still relies on Paystack webhook or `payment/verify` to confirm success.
- For pay-after-service bookings, payment verification happens before completion and payout release happens on completion.

---

## Summary

- `upfront` = existing payment-first flow
- `afterCompletion` = pay after service, where booking is created now, payment is verified before completion, and payout is released on completion
- Company commission is still calculated and applied after payment release
- `paymentMode` is centralized in `src/utils/paymentMode.js`
- `POST /booking/:id/pay-after-completion` is the new deferred-payment trigger

If the Flutter team wants, I can also provide example request payloads for each flow.
