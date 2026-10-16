# Dojah KYC Pending Resolution for Mobile

This document explains how the mobile app should handle Dojah SDK KYC so users do not remain stuck on `pending`.

## Key Point

`POST /api/kyc/dojah/start-session` only starts the KYC session. It creates a backend KYC record with:

```json
{
  "status": "pending",
  "provider": "dojah_sdk",
  "providerStatus": "started"
}
```

The app must later call `verify-reference` with the same `referenceId` to move the KYC record from `pending` to `approved` or `rejected`.

## Required Mobile Flow

### 1. Start Dojah session

```http
POST /api/kyc/dojah/start-session
Authorization: Bearer <token>
```

Example response:

```json
{
  "success": true,
  "data": {
    "referenceId": "rij_kyc_labc123_6624b1b15e0c8c2c64a00001"
  }
}
```

Mobile must save this `referenceId`.

### 2. Launch Dojah SDK

Pass the `referenceId` from step 1 into the Dojah SDK flow if the SDK supports custom/reference metadata.

The backend expects the same `referenceId` when verifying the result.

### 3. Verify after SDK closes

When the Dojah SDK closes, completes, or returns control to the app, call:

```http
POST /api/kyc/dojah/verify-reference
Authorization: Bearer <token>
Content-Type: application/json
```

Request body:

```json
{
  "referenceId": "rij_kyc_labc123_6624b1b15e0c8c2c64a00001"
}
```

This endpoint asks Dojah for the final result and updates the existing pending KYC record.

## Possible Responses

### Approved

```json
{
  "success": true,
  "message": "KYC verification approved",
  "data": {
    "status": "approved",
    "provider": "dojah",
    "verificationType": "sdk_widget",
    "referenceId": "rij_kyc_labc123_6624b1b15e0c8c2c64a00001"
  }
}
```

Mobile should show verified state and refresh the user/artisan profile.

### Rejected

```json
{
  "success": true,
  "message": "KYC verification rejected",
  "data": {
    "status": "rejected",
    "failureReason": "Liveness or face match check failed",
    "provider": "dojah",
    "verificationType": "sdk_widget",
    "referenceId": "rij_kyc_labc123_6624b1b15e0c8c2c64a00001"
  }
}
```

Mobile should show failed state and display `failureReason`.

### Still Pending

```json
{
  "success": true,
  "message": "Verification still in progress",
  "data": {
    "status": "pending",
    "provider": "dojah",
    "providerStatus": "Pending",
    "verificationType": "sdk_widget",
    "referenceId": "rij_kyc_labc123_6624b1b15e0c8c2c64a00001",
    "retryAfterSeconds": 2
  }
}
```

Mobile should not treat this as stuck. It means Dojah has not returned a final result yet.

Recommended behavior:

1. Show "Verification still processing".
2. Wait `retryAfterSeconds` if present, otherwise wait 5-10 seconds.
3. Call `POST /api/kyc/dojah/verify-reference` again with the same `referenceId`.
4. Stop retrying after a reasonable limit, such as 3-5 attempts, and let the user manually refresh/check again.

## Webhook Behavior

The backend also supports:

```http
POST /api/kyc/dojah/webhook
```

If Dojah webhook is configured correctly, Dojah can update the KYC record automatically.

However, mobile should still call `verify-reference` after SDK completion. This avoids leaving users pending if the webhook is delayed, blocked, or not configured.

## UI Rules

Use the KYC `status` returned by `verify-reference`, profile endpoints, or `/api/kyc/artisan/:id/status`.

```json
{
  "approved": "Show verified state",
  "pending": "Show verification still processing and retry/check again",
  "pending_review": "Show manual review pending",
  "rejected": "Show verification failed and display failureReason",
  "not_submitted": "Show start verification"
}
```

## Common Mistake

Do not only call `start-session`.

If the app calls `start-session` but never calls `verify-reference`, the backend may keep showing:

```json
{
  "status": "pending"
}
```

That is expected because `start-session` means "verification started", not "verification completed".

## Summary for Mobile Developer

Always call:

```http
POST /api/kyc/dojah/verify-reference
```

with the same `referenceId` after the Dojah SDK finishes or closes.

That is the step that changes KYC from `pending` to `approved` or `rejected`.
