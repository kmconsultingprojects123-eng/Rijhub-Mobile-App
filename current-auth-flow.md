# Current Authentication And Verification Flow

This document explains the current client-facing authentication flow for RijHub/Artisan API, including password auth, OTP registration, social auth, guest auth, password reset, Firebase phone registration, JWT usage, and KYC verification through manual upload or Dojah NIN + selfie.

Base URL:

```text
https://rijhub.com
```

Local development usually uses:

```text
http://localhost:5000
```

Interactive API docs:

```text
GET /api/documentation
GET /api/documentation/json
```

## Response Shape

Most endpoints return JSON. Older endpoints may not always use the exact same envelope, so client code should read both top-level `token`/`user` and `data.token`/`data.user` when integrating.

Typical success:

```json
{
  "success": true,
  "message": "Operation completed",
  "data": {}
}
```

Typical error:

```json
{
  "success": false,
  "message": "Invalid credentials",
  "code": "OPTIONAL_ERROR_CODE"
}
```

## JWT Authentication

Protected endpoints require:

```http
Authorization: Bearer <jwt>
```

The API signs JWTs with the user id and role:

```json
{
  "id": "6624b1b15e0c8c2c64a00001",
  "role": "artisan"
}
```

Current token lifetime is 7 days.

### Verify Current Token

```http
GET /api/auth/verify
Authorization: Bearer <jwt>
```

Success:

```json
{
  "success": true,
  "payload": {
    "id": "6624b1b15e0c8c2c64a00001",
    "role": "customer",
    "iat": 1777800000,
    "exp": 1778404800
  }
}
```

Failure:

```json
{
  "message": "Unauthorized"
}
```

## Standard Email/Password Registration

Normal email/password registration is a two-step flow:

1. Client calls `POST /api/auth/register`.
2. Server creates a pending registration record and sends an OTP by phone provider or email.
3. Client calls `POST /api/auth/verify-otp`.
4. Server creates the user and returns a JWT.

Allowed user roles during normal registration are:

```text
customer
artisan
```

Clients cannot create admins directly with `role: "admin"` unless the admin invite flow is used.

### Start Registration

```http
POST /api/auth/register
Content-Type: application/json
```

Request:

```json
{
  "name": "Ada Okafor",
  "email": "ada@example.com",
  "password": "secret123",
  "phone": "+2348012345678",
  "role": "artisan"
}
```

Response when phone is provided and OTP delivery is accepted:

```json
{
  "success": true,
  "message": "Verification request accepted. You will receive the code shortly."
}
```

Response when email OTP is used:

```json
{
  "success": true,
  "message": "Verification code sent. Use /api/auth/verify-otp to complete registration."
}
```

Common errors:

```json
{
  "message": "Email is required"
}
```

```json
{
  "message": "Provide password or Google token"
}
```

```json
{
  "message": "User already exists"
}
```

## Complete Registration With OTP

```http
POST /api/auth/verify-otp
Content-Type: application/json
```

Request:

```json
{
  "email": "ada@example.com",
  "otp": "123456"
}
```

Success:

```json
{
  "success": true,
  "message": "Registration completed",
  "user": {
    "_id": "6624b1b15e0c8c2c64a00001",
    "name": "Ada Okafor",
    "email": "ada@example.com",
    "role": "artisan",
    "kycVerified": false,
    "isVerified": false,
    "kycLevel": 1
  },
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

Client should store the token securely and send it as `Authorization: Bearer <token>`.

## Resend Registration OTP

```http
POST /api/auth/resend-otp
Content-Type: application/json
```

Request:

```json
{
  "email": "ada@example.com",
  "phone": "+2348012345678"
}
```

Example success:

```json
{
  "success": true,
  "message": "OTP resent successfully"
}
```

## Verify Sendchamp OTP/Reference

Some Sendchamp flows use a provider reference plus OTP.

```http
POST /api/auth/verify-sendchamp
Content-Type: application/json
```

Request:

```json
{
  "email": "ada@example.com",
  "reference": "sendchamp_reference_123",
  "otp": "123456"
}
```

Success:

```json
{
  "success": true,
  "message": "Registration completed",
  "user": {
    "_id": "6624b1b15e0c8c2c64a00001",
    "email": "ada@example.com",
    "role": "customer"
  },
  "token": "jwt..."
}
```

## Login

```http
POST /api/auth/login
Content-Type: application/json
```

Request:

```json
{
  "email": "ada@example.com",
  "password": "secret123",
  "deviceToken": "fcm_token_optional",
  "platform": "android"
}
```

Success:

```json
{
  "success": true,
  "message": "Login successful",
  "user": {
    "_id": "6624b1b15e0c8c2c64a00001",
    "name": "Ada Okafor",
    "email": "ada@example.com",
    "role": "artisan",
    "kycVerified": false,
    "isVerified": false,
    "kycLevel": 1
  },
  "token": "jwt...",
  "deviceTokens": [
    {
      "token": "fcm_token_optional",
      "platform": "android"
    }
  ]
}
```

Common failures:

```json
{
  "message": "Email and password required"
}
```

```json
{
  "message": "Invalid credentials"
}
```

```json
{
  "message": "Account banned"
}
```

## Guest Login

Guest login creates a temporary guest account and returns a JWT.

```http
POST /api/auth/guest
Content-Type: application/json
```

Request:

```json
{}
```

Success:

```json
{
  "success": true,
  "guest": {
    "_id": "6624b1b15e0c8c2c64a00001",
    "name": "Guest",
    "email": "guest+1777800000000@guest.local",
    "role": "guest",
    "isGuest": true
  },
  "token": "jwt..."
}
```

Guest accounts should be treated as limited accounts by the client. They should not be used for artisan job actions.

## Google OAuth

Mobile or web clients obtain a Google ID token, then send it to the backend. The backend verifies the token with Google, creates or links the user, and returns a RijHub JWT.

```http
POST /api/auth/oauth/google
Content-Type: application/json
```

Request:

```json
{
  "idToken": "google_id_token",
  "role": "customer"
}
```

`id_token` is also accepted:

```json
{
  "id_token": "google_id_token",
  "role": "artisan"
}
```

Success:

```json
{
  "success": true,
  "user": {
    "_id": "6624b1b15e0c8c2c64a00001",
    "name": "Ada Okafor",
    "email": "ada@example.com",
    "provider": "google",
    "googleId": "google-sub-id",
    "role": "customer"
  },
  "token": "jwt...",
  "deviceTokens": []
}
```

Common failure:

```json
{
  "message": "idToken required (body.idToken or body.id_token)"
}
```

```json
{
  "message": "Google OAuth failed (audience=unknown)"
}
```

## Apple OAuth

Apple auth supports either:

- Mobile identity token flow: `identityToken` + `nonce`
- Server exchange flow: `authorizationCode`

```http
POST /api/auth/oauth/apple
Content-Type: application/json
```

Mobile identity token request:

```json
{
  "identityToken": "apple_identity_token",
  "nonce": "raw_nonce_used_by_client",
  "name": "Ada Okafor",
  "email": "ada@example.com",
  "role": "customer"
}
```

Authorization code request:

```json
{
  "authorizationCode": "apple_authorization_code",
  "name": "Ada Okafor",
  "email": "ada@example.com",
  "role": "artisan"
}
```

Success:

```json
{
  "success": true,
  "user": {
    "_id": "6624b1b15e0c8c2c64a00001",
    "name": "Ada Okafor",
    "email": "ada@example.com",
    "provider": "apple",
    "role": "artisan"
  },
  "token": "jwt..."
}
```

Common failures:

```json
{
  "message": "identityToken or authorizationCode required"
}
```

```json
{
  "message": "nonce required for identityToken flow"
}
```

```json
{
  "message": "Invalid Apple identity token"
}
```

## Firebase Phone Registration

Client verifies phone number with Firebase, receives a Firebase ID token, then registers with the backend.

```http
POST /api/auth/registeruserfirebase
Content-Type: application/json
```

Request:

```json
{
  "idToken": "firebase_id_token",
  "name": "Ada Okafor",
  "email": "ada@example.com",
  "password": "secret123",
  "phone": "+2348012345678",
  "role": "customer"
}
```

Success:

```json
{
  "token": "jwt...",
  "user": {
    "_id": "6624b1b15e0c8c2c64a00001",
    "name": "Ada Okafor",
    "email": "ada@example.com",
    "phone": "+2348012345678",
    "role": "customer",
    "firebaseUid": "firebase_uid",
    "phoneVerified": true,
    "createdAt": "2026-05-04T10:30:00.000Z"
  }
}
```

Common failures:

```json
{
  "message": "idToken, name, email, password and role are required"
}
```

```json
{
  "message": "Firebase not configured on server"
}
```

```json
{
  "message": "Invalid or expired Firebase token"
}
```

## Remote Token Verification

This endpoint verifies a token against a remote verifier. It first checks the `Authorization` header and falls back to `body.token`.

```http
POST /api/auth/verify-remote
Authorization: Bearer <token>
Content-Type: application/json
```

Request body can be empty when using the Authorization header:

```json
{}
```

Or:

```json
{
  "token": "jwt_or_remote_token"
}
```

Success:

```json
{
  "valid": true,
  "payload": {
    "success": true,
    "payload": {
      "id": "6624b1b15e0c8c2c64a00001",
      "role": "customer"
    }
  }
}
```

Failure:

```json
{
  "valid": false,
  "message": "remote verification failed",
  "remoteStatus": 401
}
```

## Password Reset

Password reset is a two-step flow:

1. Request a reset token.
2. Submit the reset token with a new password.

### Request Reset Token

```http
POST /api/auth/forgot-password
Content-Type: application/json
```

Request:

```json
{
  "email": "ada@example.com"
}
```

Success:

```json
{
  "success": true,
  "message": "If an account with that email exists, a password reset link has been sent."
}
```

In development, the response may also include:

```json
{
  "resetToken": "123456",
  "resetUrl": "https://rijhub.com/aa/reset-password?token=123456"
}
```

### Reset Password

```http
POST /api/auth/reset-password
Content-Type: application/json
```

Request:

```json
{
  "resetToken": "123456",
  "newPassword": "newSecret123"
}
```

Success:

```json
{
  "success": true,
  "message": "Password has been reset successfully",
  "token": "jwt...",
  "user": {
    "id": "6624b1b15e0c8c2c64a00001",
    "email": "ada@example.com",
    "name": "Ada Okafor",
    "role": "customer"
  }
}
```

Failures:

```json
{
  "message": "Invalid or expired reset token"
}
```

```json
{
  "message": "Password must be at least 6 characters"
}
```

## KYC And Artisan Verification

KYC is required before an artisan can perform verified-artisan actions such as:

- Applying to jobs
- Creating job quotes
- Accepting/rejecting bookings
- Creating booking quotes
- Responding to special service requests

Artisan onboarding/profile setup can happen before approval, but marketplace actions are blocked until verification is approved.

Verification state is synced across:

- `User.kycVerified`
- `User.isVerified`
- `User.kycLevel`
- `Artisan.verified`
- latest KYC record status

Approved KYC sets:

```json
{
  "kycVerified": true,
  "isVerified": true,
  "kycLevel": 2,
  "artisanVerified": true
}
```

Rejected or pending KYC sets:

```json
{
  "kycVerified": false,
  "isVerified": false,
  "kycLevel": 1,
  "artisanVerified": false
}
```

## Dojah NIN + Selfie Verification

This is the preferred automatic KYC route for Nigerian NIN verification.

Backend env:

```env
DOJAH_BASE_URL=https://sandbox.dojah.io
DOJAH_APP_ID=your_dojah_app_id
DOJAH_SECRET_KEY=your_dojah_private_secret_key
DOJAH_NIN_SELFIE_CONFIDENCE_THRESHOLD=90
DOJAH_TIMEOUT_MS=30000
```

`DOJAH_SECRET_KEY` must be the private/secret key. Do not expose it in frontend or mobile code.

The client calls RijHub backend only:

```text
Client app -> RijHub backend -> Dojah
```

### Verify NIN With Selfie

```http
POST /api/kyc/dojah/nin-selfie
Authorization: Bearer <jwt>
Content-Type: application/json
```

JSON request:

```json
{
  "nin": "70123456789",
  "selfieImage": "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQ...",
  "firstName": "Ada",
  "lastName": "Okafor"
}
```

Accepted JSON aliases:

```json
{
  "idNumber": "70123456789",
  "selfie_image": "/9j/4AAQSkZJRgABAQ...",
  "first_name": "Ada",
  "last_name": "Okafor"
}
```

Multipart request:

```http
POST /api/kyc/dojah/nin-selfie
Authorization: Bearer <jwt>
Content-Type: multipart/form-data
```

Multipart fields:

```text
nin=70123456789
selfie=<image file>
firstName=Ada
lastName=Okafor
```

Accepted selfie file field names:

```text
selfie
selfieImage
selfie_image
```

Approved response:

```json
{
  "success": true,
  "message": "NIN selfie verification approved",
  "data": {
    "status": "approved",
    "match": true,
    "confidenceValue": 98.4,
    "threshold": 90,
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

Rejected response:

```json
{
  "success": true,
  "message": "NIN selfie verification rejected",
  "data": {
    "status": "rejected",
    "match": false,
    "confidenceValue": 41.2,
    "threshold": 90,
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

Manual review response when Dojah is temporarily unavailable:

```json
{
  "success": true,
  "message": "Automatic verification could not be completed. KYC moved to manual review.",
  "data": {
    "status": "pending_review",
    "failureReason": "Dojah verification failed"
  }
}
```

Server configuration error:

```json
{
  "success": false,
  "message": "Dojah verification is not configured",
  "data": {
    "status": "pending_review",
    "failureReason": "Dojah AppId and Secret Key are required"
  }
}
```

Validation errors:

```json
{
  "success": false,
  "message": "nin is required"
}
```

```json
{
  "success": false,
  "message": "nin must be 11 digits"
}
```

```json
{
  "success": false,
  "message": "selfieImage is required"
}
```

### Dojah Approval Logic

The backend reads Dojah selfie verification data and approves only when:

```text
selfie_verification.match == true
confidence_value >= DOJAH_NIN_SELFIE_CONFIDENCE_THRESHOLD
```

Default threshold:

```text
90
```

If approved:

- KYC status becomes `approved`
- Provider becomes `dojah`
- Verification type becomes `nin_selfie`
- User is marked verified
- Artisan profile is marked verified if it exists
- Verification notification is sent

If rejected:

- KYC status becomes `rejected`
- User verification flags are false
- Artisan verification flag is false

If Dojah call fails but backend is configured:

- KYC status becomes `pending_review`
- Admin can review manually

## Manual KYC Fallback

Manual KYC is available when automatic Dojah verification is not used or fails.

```http
POST /api/kyc/submit
Authorization: Bearer <jwt>
Content-Type: multipart/form-data
```

Example fields:

```text
IdType=NIN
idNumber=70123456789
front=<file>
back=<file>
selfie=<file>
document=<file>
```

Example success:

```json
{
  "success": true,
  "message": "KYC submitted successfully",
  "data": {
    "status": "pending",
    "IdType": "NIN",
    "provider": "manual"
  }
}
```

## Check KYC Status

```http
GET /api/kyc/status
Authorization: Bearer <jwt>
```

Success:

```json
{
  "success": true,
  "message": "KYC status fetched",
  "data": {
    "status": "approved",
    "provider": "dojah",
    "verificationType": "nin_selfie",
    "failureReason": null,
    "selfieVerification": {
      "match": true,
      "confidenceValue": 98.4,
      "threshold": 90
    }
  }
}
```

Possible statuses:

```text
pending
pending_review
approved
rejected
```

## Delete KYC File

```http
DELETE /api/kyc/{id}/file
Authorization: Bearer <jwt>
```

Success:

```json
{
  "success": true,
  "message": "KYC file deleted"
}
```

## Verified Artisan Gate

Some artisan actions require the authenticated user to be an active, verified artisan.

The guard checks live database state, not only JWT claims:

- User exists
- User is not banned
- User role is `artisan`
- User or artisan has approved verification state

Failure example:

```json
{
  "success": false,
  "message": "Artisan verification required",
  "code": "ARTISAN_VERIFICATION_REQUIRED",
  "data": {
    "kycStatus": "pending_review",
    "provider": "dojah",
    "verificationType": "nin_selfie",
    "failureReason": "Automatic verification could not be completed"
  }
}
```

Client behavior:

1. Show the artisan their KYC status.
2. If rejected, allow retry or manual KYC depending on product rules.
3. If pending or pending_review, show waiting/manual review state.
4. If approved, allow artisan marketplace actions.

## Recommended Client Flow

### Customer

1. Register with email/password or OAuth.
2. Verify OTP if using email/password registration.
3. Login and store JWT.
4. Browse artisans/jobs/services.
5. Create bookings, jobs, support tickets, and payments using the JWT.

### Artisan

1. Register with `role: "artisan"` or OAuth with `role: "artisan"`.
2. Verify OTP if using email/password registration.
3. Login and store JWT.
4. Create or update artisan profile.
5. Add artisan services and prices.
6. Submit Dojah NIN + selfie KYC.
7. If approved, proceed to apply for jobs, accept bookings, create quotes, and respond to special service requests.
8. If pending_review, wait for admin review or submit manual KYC if requested.

## Security Notes

- Never expose `JWT_SECRET`, `DOJAH_SECRET_KEY`, Paystack secret keys, Apple private key, or Firebase admin credentials to frontend/mobile apps.
- Mobile apps should send selfies and NIN only to RijHub backend.
- RijHub backend should be the only service that calls Dojah.
- Store JWT securely on the client.
- Always send JWT as `Authorization: Bearer <token>`.
- Treat `guest` users as limited users.
- Treat `kycVerified`, `isVerified`, and `Artisan.verified` as server-owned fields. Clients should not attempt to set them directly.

## Quick Endpoint Summary

| Flow | Method | Endpoint | Auth |
| --- | --- | --- | --- |
| Register | POST | `/api/auth/register` | No |
| Verify registration OTP | POST | `/api/auth/verify-otp` | No |
| Resend OTP | POST | `/api/auth/resend-otp` | No |
| Sendchamp verification | POST | `/api/auth/verify-sendchamp` | No |
| Login | POST | `/api/auth/login` | No |
| Guest login | POST | `/api/auth/guest` | No |
| Google OAuth | POST | `/api/auth/oauth/google` | No |
| Apple OAuth | POST | `/api/auth/oauth/apple` | No |
| Firebase phone registration | POST | `/api/auth/registeruserfirebase` | No |
| Forgot password | POST | `/api/auth/forgot-password` | No |
| Reset password | POST | `/api/auth/reset-password` | No |
| Verify JWT | GET | `/api/auth/verify` | Yes |
| Remote token verify | POST | `/api/auth/verify-remote` | Optional token/header |
| Dojah NIN + selfie | POST | `/api/kyc/dojah/nin-selfie` | Yes |
| Manual KYC submit | POST | `/api/kyc/submit` | Yes |
| KYC status | GET | `/api/kyc/status` | Yes |
| Delete KYC file | DELETE | `/api/kyc/{id}/file` | Yes |

