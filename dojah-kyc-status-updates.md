# Dojah KYC Status Updates

This document records the recent backend updates made to the Dojah KYC flow so the app can clearly tell an artisan when verification failed instead of leaving them on "Verification pending".

## Goal

When Dojah verification works, the artisan should be approved as before.

When Dojah verification does not work, fails, rejects, or cannot complete, the artisan should see a clear failed/rejected status with a reason. The frontend should no longer keep showing a pending verification card for a failed Dojah attempt.

## Files Updated

- `src/controllers/dojahKycController.js`
- `src/controllers/artisanController.js`
- `src/controllers/userController.js`
- `src/controllers/kycController.js`
- `src/routes/kycRoutes.js`
- `src/plugins/swagger.js`

## 1. Dojah NIN Selfie Failure Now Saves Rejected

Endpoint:

```http
POST /api/kyc/dojah/nin-selfie
Authorization: Bearer <token>
Content-Type: application/json
```

Before this update, if the Dojah request failed, the backend saved:

```json
{
  "status": "pending_review",
  "providerStatus": "failed"
}
```

That made the artisan dashboard keep showing "Verification pending".

Now, if Dojah throws an error or the verification call does not go through, the backend saves:

```json
{
  "provider": "dojah",
  "verificationType": "nin_selfie",
  "status": "rejected",
  "providerStatus": "failed",
  "failureReason": "Dojah error message here"
}
```

The user and artisan verification flags are also synced to false:

```json
{
  "kycLevel": 1,
  "kycVerified": false,
  "isVerified": false,
  "artisan.verified": false
}
```

## 2. Dojah Failure Response JSON

When the Dojah call fails but the backend handled it, the endpoint returns HTTP `202`.

Example response:

```json
{
  "success": true,
  "message": "Dojah verification did not go through. Please retry or contact support.",
  "data": {
    "status": "rejected",
    "providerStatus": "failed",
    "failureReason": "Dojah verification failed"
  }
}
```

If Dojah is not configured on the server, the endpoint returns HTTP `500`.

Example response:

```json
{
  "success": false,
  "message": "Dojah verification is not configured",
  "data": {
    "status": "rejected",
    "providerStatus": "failed",
    "failureReason": "Missing Dojah configuration: DOJAH_APP_ID, DOJAH_SECRET_KEY"
  }
}
```

## 3. Normal Dojah Approval Response

If Dojah verifies the NIN selfie successfully and confidence is above the threshold, the KYC record is approved.

Example response:

```json
{
  "success": true,
  "message": "NIN selfie verification approved",
  "data": {
    "status": "approved",
    "providerStatus": "verified",
    "match": true,
    "confidenceValue": 98.4,
    "threshold": 90,
    "failureReason": null,
    "user": {
      "_id": "6624b1b15e0c8c2c64a00001",
      "kycVerified": true,
      "isVerified": true,
      "kycLevel": 2
    },
    "artisan": {
      "_id": "6624b1b15e0c8c2c64a00002",
      "verified": true
    }
  }
}
```

## 4. Normal Dojah Rejection Response

If Dojah responds but selfie match fails or the confidence score is below threshold, the KYC record is rejected.

Example response:

```json
{
  "success": true,
  "message": "NIN selfie verification rejected",
  "data": {
    "status": "rejected",
    "providerStatus": "not_verified",
    "match": false,
    "confidenceValue": 41.2,
    "threshold": 90,
    "failureReason": "Selfie verification failed or confidence below threshold (41.2/90)",
    "user": {
      "_id": "6624b1b15e0c8c2c64a00001",
      "kycVerified": false,
      "isVerified": false,
      "kycLevel": 1
    },
    "artisan": {
      "_id": "6624b1b15e0c8c2c64a00002",
      "verified": false
    }
  }
}
```

## 5. Profile Responses Now Include KYC Details

The profile endpoints now expose enough KYC status information for the frontend to render the correct card.

### User Profile

Endpoint:

```http
GET /api/users/me
Authorization: Bearer <token>
```

New field:

```json
{
  "success": true,
  "data": {
    "_id": "6624b1b15e0c8c2c64a00001",
    "name": "Simon Adewumi",
    "kycVerified": false,
    "isVerified": false,
    "kycDetails": {
      "status": "rejected",
      "providerStatus": "failed",
      "failureReason": "Dojah verification failed",
      "idType": "NIN",
      "verified": false,
      "submittedAt": "2026-05-10T10:30:00.000Z"
    }
  }
}
```

### Artisan Profile

Endpoints that now include `kycDetails`:

```http
GET /api/artisans/:id
GET /api/artisans/user/:id
GET /api/artisans
GET /api/artisans/search
```

Example `kycDetails`:

```json
{
  "kycDetails": {
    "status": "rejected",
    "providerStatus": "failed",
    "failureReason": "Dojah verification failed",
    "idType": "NIN",
    "verified": false,
    "submittedAt": "2026-05-10T10:30:00.000Z"
  }
}
```

Frontend display rule suggestion:

```json
{
  "approved": "Show verified state",
  "pending": "Show verification pending",
  "pending_review": "Show manual review pending",
  "rejected": "Show verification failed and display failureReason",
  "not_submitted": "Show start verification"
}
```

## 6. New Endpoint: Check Any Artisan KYC Status

A new endpoint was added so the app can check the latest KYC status for any artisan.

Endpoint:

```http
GET /api/kyc/artisan/:id/status
```

The `:id` can be either:

- the artisan profile `_id`
- the linked artisan `userId`

This endpoint uses optional auth, so it can work with or without a logged-in user.

Example request:

```http
GET /api/kyc/artisan/6624b1b15e0c8c2c64a00002/status
```

Example response when rejected:

```json
{
  "success": true,
  "data": {
    "status": "rejected",
    "provider": "dojah",
    "providerStatus": "failed",
    "verificationType": "nin_selfie",
    "failureReason": "Dojah verification failed",
    "reviewedBy": null,
    "submittedAt": "2026-05-10T10:30:00.000Z",
    "verifiedAt": null,
    "verified": false,
    "artisan": {
      "_id": "6624b1b15e0c8c2c64a00002",
      "userId": "6624b1b15e0c8c2c64a00001",
      "verified": false
    },
    "user": {
      "_id": "6624b1b15e0c8c2c64a00001",
      "kycVerified": false,
      "isVerified": false,
      "kycLevel": 1
    }
  }
}
```

Example response when approved:

```json
{
  "success": true,
  "data": {
    "status": "approved",
    "provider": "dojah",
    "providerStatus": "verified",
    "verificationType": "nin_selfie",
    "failureReason": null,
    "reviewedBy": null,
    "submittedAt": "2026-05-10T10:30:00.000Z",
    "verifiedAt": "2026-05-10T10:31:00.000Z",
    "verified": true,
    "artisan": {
      "_id": "6624b1b15e0c8c2c64a00002",
      "userId": "6624b1b15e0c8c2c64a00001",
      "verified": true
    },
    "user": {
      "_id": "6624b1b15e0c8c2c64a00001",
      "kycVerified": true,
      "isVerified": true,
      "kycLevel": 2
    }
  }
}
```

Example response when the artisan has no KYC record:

```json
{
  "success": true,
  "data": {
    "status": "not_submitted",
    "provider": null,
    "providerStatus": null,
    "verificationType": null,
    "failureReason": null,
    "reviewedBy": null,
    "submittedAt": null,
    "verifiedAt": null,
    "verified": false,
    "artisan": {
      "_id": "6624b1b15e0c8c2c64a00002",
      "userId": "6624b1b15e0c8c2c64a00001",
      "verified": false
    },
    "user": {
      "_id": "6624b1b15e0c8c2c64a00001",
      "kycVerified": false,
      "isVerified": false,
      "kycLevel": 0
    }
  }
}
```

Error responses:

```json
{
  "success": false,
  "message": "invalid artisan id"
}
```

```json
{
  "success": false,
  "message": "Artisan not found"
}
```

## 7. Swagger/OpenAPI Updates

The Swagger docs were updated in `src/plugins/swagger.js`.

Updated documentation includes:

- Dojah NIN selfie failures now describe `rejected` instead of `pending_review`.
- `DojahNinSelfieResponse` now includes `providerStatus` and `failureReason`.
- `DojahNinSelfieManualReviewResponse` now documents the failed Dojah request response.
- New path documented: `/api/kyc/artisan/{id}/status`.
- New schema documented: `ArtisanKycStatusResponse`.

## 8. Validation Performed

Syntax checks were run on the changed files:

```bash
node --check src/controllers/dojahKycController.js
node --check src/controllers/artisanController.js
node --check src/controllers/userController.js
node --check src/controllers/kycController.js
node --check src/routes/kycRoutes.js
node --check src/plugins/swagger.js
```

All syntax checks passed.

The repo does not currently have a real build script:

```bash
npm run build
```

Result:

```text
Missing script: "build"
```

## 9. Summary For Frontend

Use `kycDetails.status` or the new artisan KYC status endpoint.

Recommended UI behavior:

```json
{
  "status": "approved",
  "ui": "Show verified"
}
```

```json
{
  "status": "pending",
  "ui": "Show verification pending"
}
```

```json
{
  "status": "pending_review",
  "ui": "Show manual review pending"
}
```

```json
{
  "status": "rejected",
  "ui": "Show verification failed and display failureReason"
}
```

```json
{
  "status": "not_submitted",
  "ui": "Show start verification"
}
```

