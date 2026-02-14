(Auth / Google OAuth)

Overview:: Server-side endpoint to accept a Google ID token (idToken / id_token), verify it with Google's OAuth servers, create or link a User record, and return your app JWT. Use this when a user registered via Google or wants to sign-in with Google.

Env vars:: Ensure GOOGLE_CLIENT_ID is set in your .env (the value from your Google Cloud OAuth client).

Endpoint:: POST /api/auth/oauth/google

Body (application/json):
idToken: string — the Google ID token obtained from the client SDK (required)
Response (200): { success: true, user: { ... }, token: "<JWT>" }
Errors: 400 for missing/invalid token, 500 for server errors.

How it works (server):: The server verifies the idToken using the Google OAuth2Client (the project uses google-auth-library). After verification the server reads payload.email, payload.sub (Google user id), payload.name, and payload.picture. The server then:

Finds an existing user by googleId or email.
If a user exists but lacks googleId, the server links the account (sets googleId and provider: 'google').
If no user exists, the server creates a new User with provider='google' and googleId set.
The server issues a JWT (token) that the client uses for authenticated requests.

Client (web) example:

Use Google Identity Services to get an id_token:

// After user signs in with Google's client-side library

const idToken = googleUserCredential?.credential; // or response.credential

const res = await fetch('https://your-api.example.com/api/auth/oauth/google', {

	method: 'POST',

	headers: { 'Content-Type': 'application/json' },

	body: JSON.stringify({ idToken }),

});

const data = await res.json();

// data.token is your app JWT

Client (Flutter / mobile) example:
Use the platform's Google Sign-In plugin to obtain an idToken and POST it to the same endpoint:

// Pseudocode (Flutter)

final googleUser = await GoogleSignIn().signIn();

final auth = await googleUser.authentication; // contains idToken

final idToken = auth.idToken;

final resp = await http.post(Uri.parse('https://your-api/api/auth/oauth/google'),

	headers: {'Content-Type': 'application/json'},

	body: jsonEncode({'idToken': idToken}),

**Artisan API - Endpoints & Flutter Usage**

This document lists the server API endpoints in this project, required authentication, request payloads, and short Flutter examples (using `http` or `http.MultipartRequest`) so you can integrate from a mobile app.

Base URL: `http://<HOST>:<PORT>` (e.g. `http://localhost:5000`)

**Authentication**

**Contents**


- `GET /api/bookings/:id/quotes` — list quotes for booking (returns quote objects)

- `GET /api/bookings/:id/quotes/details` — list quotes with artisan and booking details (populated)

    - Response (200): `{ success: true, data: [ { _id, bookingId, artisanUser: { _id, name, email, profileImage }, artisanProfile: { ...artisan fields... }, items, total, status, createdAt, booking: { _id, customerId, artisanId, service, schedule, price, ... } } ] }`

    - Use this endpoint to display artisans who submitted quotes and the job (booking) details they quoted against.

- `POST /api/auth/register`

    - Accepts JSON (normal users) or multipart (profile image). Use `adminCode` to create an Admin account.

    - Body (JSON): `name`, `email` (required), `password` (required unless using Google), `phone`, `role` (server allows `customer` or `artisan`), `adminCode` (optional — creates Admin when matches env `ADMIN_INVITE_CODE`).

    - Response: `201` with created `user` or created `admin` and `token`.

- `POST /api/auth/login`

    - Body: `{ email: string, password: string }`

    - Response: `{ success: true, user, token }`

Note about Admins:

	- Admins authenticate using the same endpoint `POST /api/auth/login`.

	- If you created an admin via `POST /api/auth/register` with `adminCode`, use the admin's email/password here.

	- Successful admin login returns `{ success: true, admin, token }` where `token` contains `role: 'admin'` in its payload.

	- Example (curl):

```bash

curl -X POST 'http://localhost:5000/api/auth/login' -H 'Content-Type: application/json' -d '{"email":"admin@example.com","password":"secret"}'

POST /api/auth/guest

Creates a guest user and returns a token.

GET /api/auth/verify — (protected)

Verify the Authorization bearer token and return the decoded payload.
Header: Authorization: Bearer <TOKEN>
Response (200): { success: true, payload: { id, role, iat, exp, ... } }
Use this endpoint from your frontend to confirm the token is valid and to retrieve the server-verified claims.

POST /api/auth/oauth/google

Body: { idToken: string } — server verifies token with Google and issues app JWT.

POST /api/auth/forgot-password

Body: { email: string }
Generates a password reset token and sends email to user
Email contains link: https://rijhub.com/aa/reset-password?token=...
Response (200): { success: true, message: 'If an account with that email exists, a password reset link has been sent.' }
Security: Always returns success even if email not found (prevents email enumeration)
Token expires in 1 hour
Email Configuration: Requires env vars: SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_FROM

POST /api/auth/reset-password

Body: { resetToken: string, newPassword: string }
Validates the reset token and updates the password
Response (200): { success: true, message: 'Password has been reset successfully', token, user }
Returns a new auth token so user can login immediately
Errors: 400 if token is invalid/expired or password is too short

Flutter example (login)

import 'dart:convert';

import 'package:http/http.dart' as http;

final res = await http.post(Uri.parse('http://localhost:5000/api/auth/login'),

	headers: {'Content-Type': 'application/json'},

	body: jsonEncode({'email': 'you@example.com', 'password': 'secret'}),

);

final body = jsonDecode(res.body);

final token = body['token'];

// store token securely (flutter_secure_storage)

Register (with optional adminCode)

final resp = await http.post(Uri.parse('http://localhost:5000/api/auth/register'),

	headers: {'Content-Type': 'application/json'},

	body: jsonEncode({

		'name': 'Alice',

		'email': 'alice@example.com',

		'password': 'secret',

		// 'adminCode': 'THE_BOOTSTRAP_CODE' // only when creating an admin

	}),

);

Forgot Password Flow

// Step 1: Request password reset (sends email)

final forgotResp = await http.post(

	Uri.parse('http://localhost:5000/api/auth/forgot-password'),

	headers: {'Content-Type': 'application/json'},

	body: jsonEncode({'email': 'user@example.com'}),

);

// User receives email with reset link: https://rijhub.com/aa/reset-password?token=abc123...

// Step 2: In your app's reset password screen, extract token from deep link

// Uri: rijhub.com/aa/reset-password?token=abc123...

final uri = Uri.parse(deepLink);

final resetToken = uri.queryParameters['token'];

// Step 3: Submit new password with token

final resetResp = await http.post(

	Uri.parse('http://localhost:5000/api/auth/reset-password'),

	headers: {'Content-Type': 'application/json'},

	body: jsonEncode({

		'resetToken': resetToken,

		'newPassword': 'newSecurePassword123'

	}),

);

final resetBody = jsonDecode(resetResp.body);

final newToken = resetBody['token']; // User is automatically logged in

// Store token and navigate to home screen

Email Configuration (add to your .env file):

SMTP_HOST=smtp.gmail.com

SMTP_PORT=587

SMTP_USER=your-email@gmail.com

SMTP_PASS=your-app-password

SMTP_FROM=noreply@rijhub.com

For Gmail, use an App Password instead of your regular password.
POST /api/jobs — (protected) create a job
Users

GET /api/users/me — (protected) returns authenticated user's full record (includes isVerified, kycVerified, kycLevel).
GET /api/users — returns up to 50 users (public by default).
PUT /api/users/me — (protected) update authenticated user's profile. Accepts application/json or multipart/form-data. - Allowed fields (JSON body or form fields): name (string), email (string, email), phone (string), password (string, min 6). To upload a new profile image send a profileImage file field in multipart form. - If profileImage is provided the server uploads it to Cloudinary and stores { url, public_id } in the user's profileImage field. - Response (200): { success: true, data: <updated user> }. - Errors: 400 for invalid input; 401 for missing token; 409 if email already in use; 500 for server errors. - Example (JSON):

PUT /api/users/me

Authorization: Bearer <TOKEN>

Content-Type: application/json

{ "name": "Alice New", "phone": "+234812345678", "password": "newpass123" }

	- Example (multipart upload with profile image) (curl):

curl -X PUT 'http://localhost:5000/api/users/me' \

	-H 'Authorization: Bearer <TOKEN>' \

	-F 'name=Alice New' \

	-F 'profileImage=@/path/to/photo.jpg'

GET /api/jobs — list jobs. By default this endpoint returns only open jobs for public listing. It supports the following query parameters:

POST /api/users — create user (public; used by some clients).
DELETE /api/users/profile-image — (protected) deletes authenticated user's profile image.

Device Tokens / Push Notifications

POST /api/devices/register — (protected)

Purpose: Register (upsert) an FCM/device push token for the authenticated user. The server stores the token and associates it with the user so push notifications can be delivered to all of a user's devices.
Headers: Authorization: Bearer <TOKEN>
Body (application/json): { "token": "<FCM_OR_PLATFORM_TOKEN>", "platform": "ios|android|web" } — token is required.
Behavior: Upserts the token. If the same token exists and is owned by another user, the server will reassign it and write an audit record. Registrations are rate-limited per user to prevent abuse.
Response (200): { success: true } or 429 when rate-limited.

POST /api/devices/unregister — (protected)

Purpose: Unregister/remove a device token for the authenticated user.
Headers: Authorization: Bearer <TOKEN>
Body (application/json): { "token": "<FCM_OR_PLATFORM_TOKEN>" } — token required.
Behavior: Only the owner of a token may remove it. If token not found the endpoint returns success (idempotent).
Response (200): { success: true } or 403 if trying to remove a token owned by another user.

GET /api/devices/my — (protected)

Purpose: List the authenticated user's registered device tokens.
Headers: Authorization: Bearer <TOKEN>
Response (200): { success: true, tokens: [ { token, platform, createdAt, updatedAt }, ... ] }

Account Deletion (Self & Admin)

DELETE /api/users/me — (protected)

Purpose: Permanently delete the authenticated user's account and all related data. This is irreversible.
Headers: Authorization: Bearer <TOKEN>
Behavior: The server:
Validates the user id (sanitizes common client formats such as user:<id>).
Attempts to delete related documents across multiple collections: Artisan, Booking, Transaction, Chat, Quote, Job, DeviceToken, Kyc, Notification, Review, Wallet, DeviceTokenAudit and any media stored in Cloudinary referenced by the user or their KYC/job attachments.
Returns a single success response when deletion completes or a 500 if removing related data fails.
Response (200): { success: true, message: 'Account and related data deleted' }
Errors: 400 if user id invalid; 404 if user not found; 500 on server error.

DELETE /api/users/:id — (admin-only)

Purpose: Admins can delete any user and their related data (same behavior as self-delete).
Headers: Authorization: Bearer <ADMIN_TOKEN>
Params: id — target user ObjectId (24 hex chars). The server accepts common prefixed formats but will validate before deletion.
Response (200): { success: true, message: 'Account and related data deleted' }
Notes & Cautions: This action permanently removes user data across the system. Consider adding an admin confirmation step, a deletion grace period, or a soft-delete mechanism if you need recoverability.

Flutter example (get my profile)

final res = await http.get(Uri.parse('http://localhost:5000/api/users/me'),

	headers: {'Authorization': 'Bearer $token'},

);

Admin: Ban / Unban Users

Overview: Admins can ban or unban user accounts (customers or artisans). The server sets User.banned = true when banned and false when unbanned. A notification is persisted and emitted to the user; an email is sent if SMTP is configured.

Endpoints (admin-only):

PUT /api/admin/users/:id/ban — Ban a user
Headers: Authorization: Bearer <ADMIN_TOKEN>
Response (200): { success: true, data: <updated user> }
PUT /api/admin/users/:id/unban — Unban a user
Headers: Authorization: Bearer <ADMIN_TOKEN>
Response (200): { success: true, data: <updated user> }

Examples (curl):

curl -X PUT "https://api.yourdomain.com/api/admin/users/<USER_ID>/ban" \

	-H "Authorization: Bearer <ADMIN_TOKEN>"

curl -X PUT "https://api.yourdomain.com/api/admin/users/<USER_ID>/unban" \

	-H "Authorization: Bearer <ADMIN_TOKEN>"

Notes:
Routes are protected by verifyJWT and requireRole('admin').
The action creates an in-app Notification for the user and requests an email send when SMTP_* env vars are present.
If you want login to be blocked for banned users, add a check in the authentication flow to reject access when user.banned === true.

KYC (Know Your Customer)

POST /api/kyc/submit — (protected) submit KYC documentation for verification
PreHandler: verifyJWT, cloudinaryStream (streams files directly to Cloudinary)
Headers: Authorization: Bearer <TOKEN>
Content-Type: multipart/form-data
Form Fields:
businessName: string (optional) — business/trade name
country: string (default: 'Nigeria')
state: string (required) — state/region
lga: string (optional) — local government area
IdType: string (required) — ID type (e.g., 'national_id', 'drivers_license', 'passport', 'voters_card')
serviceCategory: string (optional) — type of service provided
yearsExperience: number (default: 0)
File Fields (uploaded to Cloudinary 'kyc' folder):
profileImage: image file (optional) — profile photo
IdUploadFront: image file (required) — front of ID document
IdUploadBack: image file (required) — back of ID document
Response (201):

{

	"success": true,

	"data": {

		"_id": "64a1e2f...",

		"userId": "64a1d3c...",

		"businessName": "Alice Services",

		"country": "Nigeria",

		"state": "Lagos",

		"lga": "Ikeja",

		"IdType": "national_id",

		"profileImage": {

			"url": "https://res.cloudinary.com/.../profile.jpg",

			"public_id": "kyc/abc123"

		},

		"IdUploadFront": {

			"url": "https://res.cloudinary.com/.../id-front.jpg",

			"public_id": "kyc/def456"

		},

		"IdUploadBack": {

			"url": "https://res.cloudinary.com/.../id-back.jpg",

			"public_id": "kyc/ghi789"

		},

		"serviceCategory": "plumbing",

		"yearsExperience": 5,

		"status": "pending",

		"createdAt": "2026-01-15T10:30:00.000Z"

	}

}

- **Errors:**

	- 400: Invalid payload or missing required fields

	- 401: Unauthorized (no valid token)

	- 502: File upload failed

**Example (curl):**

curl -X POST 'http://localhost:5000/api/kyc/submit' \

	-H 'Authorization: Bearer <TOKEN>' \

	-F 'businessName=Alice Services' \

	-F 'country=Nigeria' \

	-F 'state=Lagos' \

	-F 'lga=Ikeja' \

	-F 'IdType=national_id' \

	-F 'serviceCategory=plumbing' \

	-F 'yearsExperience=5' \

	-F 'profileImage=@/path/to/profile.jpg' \

	-F 'IdUploadFront=@/path/to/id-front.jpg' \

	-F 'IdUploadBack=@/path/to/id-back.jpg'

**Flutter example:**

import 'package:http/http.dart' as http;

final uri = Uri.parse('http://localhost:5000/api/kyc/submit');

final req = http.MultipartRequest('POST', uri);

req.headers['Authorization'] = 'Bearer $token';

// Form fields

req.fields['businessName'] = 'Alice Services';

req.fields['country'] = 'Nigeria';

req.fields['state'] = 'Lagos';

req.fields['lga'] = 'Ikeja';

req.fields['IdType'] = 'national_id';

req.fields['serviceCategory'] = 'plumbing';

req.fields['yearsExperience'] = '5';

// Attach files - field names MUST match exactly: profileImage, IdUploadFront, IdUploadBack

req.files.add(await http.MultipartFile.fromPath('profileImage', '/path/to/profile.jpg'));

req.files.add(await http.MultipartFile.fromPath('IdUploadFront', '/path/to/id-front.jpg'));

req.files.add(await http.MultipartFile.fromPath('IdUploadBack', '/path/to/id-back.jpg'));

final streamed = await req.send();

final resp = await http.Response.fromStream(streamed);

final data = jsonDecode(resp.body);

// data['data'] contains the created KYC record with Cloudinary URLs

**Important Notes:**

- **Field names are case-sensitive**: Use exact names `IdUploadFront`, `IdUploadBack`, `profileImage`

- Files are streamed directly to Cloudinary (no local storage)

- Maximum file size: 10MB per file (configurable in `src/app.js`)

- After KYC submission, `User.kycLevel` is set to 1

- Admin must approve KYC (`status: 'approved'`) to set `User.kycVerified` and `User.isVerified` to true

GET /api/kyc/status — (protected) get current user's KYC verification status
PreHandler: verifyJWT
Headers: Authorization: Bearer <TOKEN>
Response (200):

{

	"success": true,

	"data": {

		"status": "pending",

		"reviewedBy": null

	}

}

- Errors: 404 if no KYC record found

DELETE /api/kyc/:id/file?field=<fieldName> — (protected) delete a specific KYC file
PreHandler: verifyJWT
Headers: Authorization: Bearer <TOKEN>
Params: id — KYC record ObjectId
Query: field — field name (one of: IdUploadFront, IdUploadBack, profileImage)
Access: Only KYC record owner or admin can delete
Example:

curl -X DELETE 'http://localhost:5000/api/kyc/<kyc_id>/file?field=IdUploadFront' \

	-H 'Authorization: Bearer <TOKEN>'

- Response (200): `{ success: true, message: 'File removed', data: <updated KYC record> }`

- Errors: 400 invalid field, 403 forbidden, 404 not found



Jobs

POST /api/jobs — (protected) create a job

PreHandler: verifyJWT and requireRole('client') (project uses role names; if your users have role customer, change to requireRole('customer') or update user roles).
Body JSON: required title (string). Optional: description, trade (array of strings), location (string), coordinates (array [lon, lat] or object { lat, lon }), budget (number), schedule (ISO date string), experienceLevel (string — one of entry, mid, senior).
categoryId (optional): Job category ObjectId (see /api/job-categories endpoints). Use this to group jobs under categories.
Server will set clientId to the authenticated user's id.
Response: 201 with created job document.

GET /api/jobs — list jobs

Query params:
page (number, default: 1)
limit (number, default: 20)
trade (string) — filter by trade/profession
categoryId (string) — filter by job category ObjectId
lat, lon, radiusKm (numbers) — geospatial search
q (string) — search in title/description
status (string) — filter by status (default: 'open')
mine (boolean string: 'true') — list authenticated user's jobs (requires auth)
Response (200): { success: true, data: [{ _id, title, description, trade, location, coordinates, budget, schedule, status, clientId, ... }] }
Admin View: When an admin user calls this endpoint, each job will include clientDetails and categoryDetails fields:

 {

   "success": true,

   "data": [{

     "_id": "...",

     "title": "Fix kitchen sink",

     "clientId": "123...",

     "categoryId": "456...",

     "clientDetails": {

       "_id": "123...",

       "name": "John Doe",

       "email": "john@example.com",

       "phone": "+1234567890",

       "profileImage": { "url": "..." }

     },

     "categoryDetails": {

       "_id": "456...",

       "name": "Plumbing",

       "slug": "plumbing",

       "description": "Pipe and waterworks"

     },

     ...

   }]

 }

Note: clientDetails and categoryDetails fields are only visible to admin users for moderation and management purposes. Regular users and artisans will not see these fields.
Example (admin fetching all jobs):

 curl -X GET 'http://localhost:5000/api/jobs?page=1&limit=20' \

 	-H 'Authorization: Bearer <ADMIN_TOKEN>'

Flutter example (admin):

 final response = await http.get(

 	Uri.parse('http://localhost:5000/api/jobs?page=1&limit=20'),

 	headers: {'Authorization': 'Bearer $adminToken'},

 );

 final data = jsonDecode(response.body);

 // Admin sees clientDetails in each job

 for (var job in data['data']) {

 	print('Job: ${job['title']} by ${job['clientDetails']['name']}');

 }

GET /api/jobs/:id — job details.

PUT /api/jobs/:id — update a job (owner only)

PreHandler: verifyJWT and requireRole(['client','customer'])
Notes: owner (the job's clientId) can update allowed fields. Admins are not automatically allowed by this route unless your admin token has client role.
Body (application/json): any of the fields below (all optional for partial updates):
title (string)
description (string)
trade (array of strings)
location (string)
coordinates (array [lon, lat] or object { lat, lon })
budget (number)
schedule (ISO date string)
categoryId (string — 24-char Mongo ObjectId)
experienceLevel (string — one of entry, mid, senior)
Example (curl):

curl -X PUT 'http://localhost:5000/api/jobs/<JOB_ID>' \

  -H 'Content-Type: application/json' \

  -H 'Authorization: Bearer <CLIENT_TOKEN>' \

  -d '{"title":"Updated title", "experienceLevel":"senior"}'



Company Earnings (Admin)

GET /api/admin/company-earnings — list company/platform earnings (admin only)

Query params:
page (number, default: 1)
limit (number, default: 20)
from (ISO date string) — filter earnings createdAt >= from
to (ISO date string) — filter earnings createdAt <= to
bookingId (string) — filter by booking ObjectId
transactionId (string) — filter by transaction ObjectId
Response (200):

 {

   "success": true,

   "data": {

     "items": [{ "_id", "transactionId", "bookingId", "amount", "note", "createdAt" }],

     "total": 123,

     "totalAmount": 4567.89

   }

 }

GET /api/admin/company-earnings/summary — summary totals for a date range (admin only)

Query params: from, to (ISO date strings)
Response (200): { "success": true, "data": { "totalAmount": 1234.56, "count": 12 } }

PowerShell example:

$body = @{ title='Updated title'; experienceLevel='senior' } | ConvertTo-Json

Invoke-RestMethod -Uri 'http://localhost:5000/api/jobs/<JOB_ID>' -Method Put -Headers @{ Authorization = 'Bearer <CLIENT_TOKEN>' } -Body $body -ContentType 'application/json'

- Response (200): `{ success: true, data: <updated job document> }`

- Errors:

	- `400` — invalid payload (e.g. invalid `categoryId` or `experienceLevel`)

	- `401` — missing/invalid token

	- `403` — authenticated but not job owner

	- `404` — job not found

PATCH /api/jobs/:id — same as PUT above, supports partial updates (owner only)

Use PATCH when you're only changing a subset of fields; server accepts same body as PUT.

POST /api/jobs/:id/apply — (protected, artisans) apply to a job. Body: { coverNote, proposedPrice }.

POST /api/jobs/:id/apply — (protected, artisans) apply to a job. Body can include quote-like details; applying will create an Application and also create/update a Quote so the job owner can review and accept a proposal.

Body (application/json):
coverNote: string (optional)
proposedPrice: number (optional)
items: array of { name: string, qty: integer, cost: number, note?: string } (optional)
attachments: array of { url: string, public_id: string } (optional)
Response (201): { success: true, data: { application: <application>, quote: <quote|null> } }

Example (curl):

curl -X POST 'http://localhost:5000/api/jobs/<JOB_ID>/apply' \

	-H 'Content-Type: application/json' \

	-H 'Authorization: Bearer <ARTISAN_TOKEN>' \

	-d '{ "coverNote": "I can do this next week", "proposedPrice": 12000, "items": [{ "name": "Materials", "cost": 8000, "qty": 1 }], "attachments": [{ "url": "https://res.cloudinary.com/.../file.jpg", "public_id": "jobs/..." }] }'

Sample response (201):

{

	"success": true,

	"data": {

		"application": {

			"_id": "64c0f1a2...",

			"jobId": "694191e1bc60c6c2426174ac",

			"artisanId": "6942b501bec0191b67732f74",

			"coverNote": "I can do this next week",

			"proposedPrice": 12000,

			"items": [{ "name": "Materials", "cost": 8000, "qty": 1 }],

			"attachments": [{ "url": "https://...", "public_id": "jobs/..." }],

			"status": "applied",

			"createdAt": "2025-12-17T14:08:47.000Z"

		},

		"quote": {

			"_id": "64c0f2b3...",

			"jobId": "694191e1bc60c6c2426174ac",

			"artisanId": "6942b501bec0191b67732f74",

			"customerId": "6942c901....",

			"items": [{ "name": "Materials", "cost": 8000, "qty": 1 }],

			"serviceCharge": 0,

			"notes": "I can do this next week",

			"total": 12000,

			"status": "proposed",

			"createdAt": "2025-12-17T14:08:48.000Z"

		}

	}

}

	**Apply vs Quote-only (recommended frontend flows)**

	- **Create both Application + Quote (single call)**: Call `POST /api/jobs/:id/apply` when the artisan wants to both *apply* for the job (create an `Application`) and *propose a price* (create/update a `Quote`) in one request. The server returns both objects in the response so the job owner can see the artisan's application and pricing proposal at the same time.

	  - Use this when you want application metadata (status, createdAt) and a surfaced quote for owner selection.

	- **Quote-only**: Call `POST /api/jobs/:id/quotes` when the artisan only wants to submit a quote (line items, serviceCharge, notes) without creating an `Application` record. This creates a `Quote` document only and it will appear in `GET /api/jobs/:id/quotes` for the owner to review.

	- **Recommended UI patterns**:

	  - If your mobile/web UI has both an "Apply" flow and a detailed "Quote" composer, call `POST /api/jobs/:id/apply` for the simple apply+quote case (one-button flow). If the artisan needs to provide detailed line-items or attachments first, call `POST /api/jobs/:id/quotes` from the dedicated quote UI and optionally call the apply endpoint separately if you still want an `Application` record.

	  - To show all proposals to the job owner, call `GET /api/jobs/:id/quotes` (it returns `artisanUser` and `artisanProfile` for each quote).

	Examples (summary):

	1) Apply + Quote (single call)

	```bash

	curl -X POST 'http://localhost:5000/api/jobs/<JOB_ID>/apply' \

	  -H 'Content-Type: application/json' \

	  -H 'Authorization: Bearer <ARTISAN_TOKEN>' \

	  -d '{ "coverNote": "I can do this next week", "proposedPrice": 12000, "items": [{ "name": "Materials", "cost": 8000, "qty": 1 }] }'

	```

	2) Quote-only (no Application created)

	```bash

	curl -X POST 'http://localhost:5000/api/jobs/<JOB_ID>/quotes' \

	  -H 'Content-Type: application/json' \

	  -H 'Authorization: Bearer <ARTISAN_TOKEN>' \

	  -d '{ "items": [{ "name": "Labor", "cost": 4000, "qty": 1 }], "serviceCharge": 250, "notes": "Can start soon" }'

	```

	Accepting a Job Quote (hire flow)

	- **Overview:** When the job owner selects an artisan's quote and wants to hire them, call the accept endpoint. The server will mark the `Quote` as accepted and initialize a payment for the full `quote.total` (returning the payment init payload to the client). The server will NOT create a `Booking` at this time — the `Booking` is created only after the payment is successfully confirmed by the gateway (webhook). When the server creates a `Booking` from an accepted job-quote it will also set the originating Job's `status` to `closed` to prevent further applications. After the gateway confirms payment, the server creates the `Booking`, holds funds in escrow, and when the customer later marks the booking complete the server releases funds to the artisan (wallet or auto-payout) and closes the chat.

	- **Endpoint:** `POST /api/jobs/:id/quotes/:quoteId/accept` — (protected, job owner only)

		- PreHandler: `verifyJWT`, `requireRole(['client','customer'])`

		- Behavior:

			1. Validates the `quoteId` belongs to the `jobId` and that the authenticated user is the job owner.

			2. Marks `Quote.status = 'accepted'`.

			3. Initializes a Paystack transaction for `quote.total` and persists a `Transaction` record referencing the `quoteId` with `status: 'pending'` and the gateway reference.

			4. Returns `{ quote, payment }` where `payment` contains the Paystack init payload the client uses to complete payment. The server will create the `Booking` only after the payment webhook confirms success.

	- **Example (curl):**

	```bash

	curl -X POST 'http://localhost:5000/api/jobs/<JOB_ID>/quotes/<QUOTE_ID>/accept' \

		-H 'Content-Type: application/json' \

		-H 'Authorization: Bearer <OWNER_TOKEN>' \

		-d '{ "email": "owner@example.com" }'

	```

	- **Quick end-to-end (summary):**

	```bash

	# 1) Accept the quote — server returns Paystack init (authorization_url + reference)

	curl -X POST 'http://localhost:5000/api/jobs/<JOB_ID>/quotes/<QUOTE_ID>/accept' \

	  -H 'Content-Type: application/json' \

	  -H 'Authorization: Bearer <OWNER_TOKEN>' \

	  -d '{ "email": "owner@example.com" }'

	# 2) Client completes checkout at the returned authorization_url (or via SDK)

	# 3) (Optional) Client can call the verify endpoint after redirect to check status:

	curl -X POST 'http://localhost:5000/api/payments/verify' \

	  -H 'Content-Type: application/json' \

	  -H 'Authorization: Bearer <OWNER_TOKEN>' \

	  -d '{ "reference": "<REFERENCE>", "email": "owner@example.com" }'

	# 4) Paystack will send a webhook to POST /api/payments/webhook with event 'charge.success'.

	#    The server will create the Booking from the quote metadata (quoteId/jobId), mark

	#    the Transaction as 'holding' and set booking.paymentStatus = 'paid'.

	```

	- **What to expect after accept:**

		- The response includes the Paystack `authorization_url` / `reference` (if Paystack configured). The client should complete the payment with the gateway.

		- The server expects the Paystack webhook to notify the app of payment success. The repo includes a webhook handler at `POST /api/payments/webhook` which validates `x-paystack-signature` and, on success, moves the `Transaction` to `holding`, sets `booking.paymentStatus = 'paid'`, creates/opens a `Chat` for the booking participants, and notifies the artisan.

	- **After payment (escrow) → completion:**

		1. The gateway calls the webhook (or you call the internal confirm endpoint): the server marks funds `holding` and `booking.paymentStatus = 'paid'`.

		2. The customer and artisan can chat (chat created on webhook). The app may expose the chat UI once `booking.paymentStatus === 'paid'`.

		3. When the customer marks the job complete (`POST /api/bookings/:id/complete`):

			 - Server checks for a `Transaction` in `holding`, computes the platform/company fee (configured via `COMPANY_FEE_PCT`), removes that fee from the held amount and pays the artisan the remainder. Payment may be performed via:

				 - Auto-payout (Paystack transfer) when `PAYSTACK_AUTO_PAYOUT=true`, Paystack is configured and the artisan has a recipient code — the server initiates a transfer; OR

				 - Internal wallet credit (the server credits the artisan's `Wallet` record) when auto-payout is disabled or transfer fails.

			 - After paying the artisan the payable amount, the server marks the `Transaction.status` as `paid` and records the `companyFee` and timestamps.

			 - The booking's `status` is set to `closed` and `paymentStatus` is set to `paid`. The booking is also flagged to prompt the customer for a review (`awaitingReview = true`).

			 - The server closes the chat (sets `chat.isClosed = true` when a chat exists for the booking), updates bookkeeping fields (artisan wallet, company wallet, `customerWallet.totalSpent`), and persists any transfer or payout metadata on the `Transaction` document for reconciliation.

			 - Notifications and emails are created and sent to both the artisan and the customer summarizing the job completion and payment (the notifier sends email when `sendEmail: true` and an email address is present). Example messages include a payment confirmation to the artisan and a thank-you/review prompt to the customer.

	- **Testing (simulate webhook for development):**

	```bash

	# Simulate Paystack webhook payload (for testing only). In production use actual gateway webhooks and signature validation.

	curl -X POST 'http://localhost:5000/api/payments/webhook' \

		-H 'Content-Type: application/json' \

		-d '{ "event":"charge.success", "data": { "reference": "tn_testref", "status":"success", "metadata": { "bookingId": "<BOOKING_ID>", "quoteId": "<QUOTE_ID>" } } }'

	```

	Make sure `PAYSTACK_SECRET` (webhook secret) is set when validating real Paystack webhooks.

	**Admin: Reconciliation Endpoint**

	- **Purpose:** Verify and reconcile `Transaction` records created for quotes that are still `pending` (e.g. when a webhook is missed or delayed). The endpoint will call the payment gateway to verify the reference and, if payment succeeded, create the `Booking` (if it doesn't already exist) and attach the `Transaction` to it.

	- **Endpoint:** `POST /api/payments/reconcile/pending-quotes` — (protected, admin)

	  - **Body (optional):** `{ "olderThanMinutes": 5 }` — only reconcile transactions older than this age to avoid races with in-flight webhooks.

	  - **Response:** `{ processed: <n>, results: [ { tx: <txId>, ok: true|false, booking?: <bookingId>, reason?: <text> } ] }`

	  - **Notes:** Use this endpoint from an admin dashboard or a scheduled cron job to ensure no paid transactions are left without bookings.

	**Wallet Payout Details (masked)**

	- **GET /api/wallet/payout-details** — (protected)

	  - **Purpose:** Retrieve the authenticated user's saved payout/bank details. The API returns masked account numbers (only last 4 digits visible) and a boolean `hasRecipient` indicating whether a Paystack recipient code exists for auto-payouts.

	  - **Response (200):** `{ payoutDetails: { name, account_number: '****1234', bank_code, bank_name, currency }, hasRecipient: true|false }`

	  - **Security:** This endpoint is protected and only returns masked account information to avoid exposing sensitive bank data.

**Paystack Helpers (server-side)**

- **Overview:** Small server-side helpers to make Paystack integration easier for mobile/web clients. These endpoints proxy Paystack's public bank list and account-resolution API so your client never needs the Paystack secret key.

- **Env vars:** `PAYSTACK_SECRET_KEY` must be set on the server for these to work.

- `GET /api/payments/banks` — (protected)

	- **Purpose:** Returns the list of banks supported by Paystack (useful to populate a bank picker in the UI).

	- **Headers:** `Authorization: Bearer <TOKEN>`

	- **Query:** none

	- **Response (200):** `{ success: true, data: [ { name, code, slug?, longcode?, currency?, type? }, ... ] }` — each item at minimum contains `name` and `code`.

	- **Errors:** 500 if `PAYSTACK_SECRET_KEY` is not set or fetching fails.

- `GET /api/payments/banks/resolve` — (protected)

	- **Purpose:** Resolve an account number + bank code to the account holder name using Paystack's resolve endpoint. Use this to confirm recipient names before saving payout details or initiating transfers.

	- **Headers:** `Authorization: Bearer <TOKEN>`

	- **Query params (required):** `account_number` (string), `bank_code` (string)

	- **Example request:** `GET /api/payments/banks/resolve?account_number=0123456789&bank_code=058`

	- **Response (200):** `{ success: true, data: { account_number: '0123456789', account_name: 'JOHN DOE', bank_id: 123, bank: 'GTBank' } }` — actual shape mirrors Paystack's `data` object and may include additional fields.

	- **Errors:** 400 if query params missing; 500 if Paystack is not configured or the gateway returns an error (response includes gateway error in `error` field).

**Notes & Best Practices**

- Never embed `PAYSTACK_SECRET_KEY` in your mobile or browser clients. Always call these endpoints from your app server which stores the secret key in environment variables.

- Handle 400/422 responses from `/banks/resolve` gracefully in the UI — show a clear message to the user if the account could not be resolved.

- For automated payouts, ensure the artisan's payout details are verified (you can call `/api/payments/banks/resolve` before creating a Paystack recipient).

	---

	**Ads & Announcements**

	- **Purpose:** Admins can create, view, edit, and delete ads (marquee text, banners, carousel items, and generic ads). Mobile clients can read these endpoints to render in-app announcements and visuals. The marquee endpoint returns a default text when no marquee ad is configured so the mobile app can always display something useful.

	- **Ad Types:**

		- **Marquee:** Scrolling text banner at top of app (only ONE active at a time)

		- **Banner:** Image-based promotional ads (multiple active, ordered display)

		- **Carousel:** Image slideshow/carousel (multiple items rotating, ordered)

		- **General:** Custom ad type for other purposes

	- **Routes:** (base prefix `/api/ads`)

	---

	### **Marquee Management**

	- `GET /api/ads/marquee` — (public) get active marquee text

		- Returns `{ text, active, id? }`

		- Default text if none configured:

		```json

		{ "text": "Welcome to Artisan — Book trusted professionals near you." }

		```

	

	- `POST /api/ads/marquee` — (admin only) create or update marquee

		- PreHandler: `verifyJWT`, `requireRole('admin')`

		- Headers: `Authorization: Bearer <TOKEN>`

		- Body:

		```json

		{

			"text": "New Year Sale — 20% off all services!",

			"active": true

		}

		```

		- **Note:** Upserts (creates if doesn't exist, updates if exists). Only ONE marquee exists at a time.

		- Example:

		```bash

		curl -X POST 'http://localhost:5000/api/ads/marquee' \

			-H 'Content-Type: application/json' \

			-H 'Authorization: Bearer <ADMIN_TOKEN>' \

			-d '{ "text": "Site maintenance at 2AM UTC. Expect brief downtime.", "active": true }'

		```

	---

	### **Banner Ads Management**

	- `GET /api/ads/banner` — (public) list active banner ads

		- Returns array of banners sorted by `order` (ascending), then `createdAt` (descending)

		- Response:

		```json

		[

			{

				"_id": "64a1e2f...",

				"type": "banner",

				"title": "Summer Promo",

				"image": "https://res.cloudinary.com/.../banner.jpg",

				"link": "https://example.com/promo",

				"order": 1,

				"active": true,

				"meta": { "campaign": "summer2026" },

				"createdBy": "64a1d3c...",

				"createdAt": "2026-01-15T10:00:00.000Z"

			}

		]

		```

	

	- `POST /api/ads/banner` — (admin only) create banner ad

		- PreHandler: `verifyJWT`, `requireRole('admin')`

		- Headers: `Authorization: Bearer <TOKEN>`

		- Body:

		```json

		{

			"title": "Summer Promo",

			"image": "https://cloudinary.com/.../banner.jpg",

			"link": "https://example.com/promo",

			"order": 1,

			"active": true,

			"meta": {

				"campaign": "summer2026",

				"targetAudience": "all"

			}

		}

		```

		- Example:

		```bash

		curl -X POST 'http://localhost:5000/api/ads/banner' \

			-H 'Content-Type: application/json' \

			-H 'Authorization: Bearer <ADMIN_TOKEN>' \

			-d '{

				"title": "Summer Sale",

				"image": "https://cloudinary.com/.../promo.jpg",

				"link": "/promotions",

				"order": 1,

				"active": true

			}'

		```

	---

	### **Carousel Management**

	- `GET /api/ads/carousel` — (public) list active carousel items

		- Returns array sorted by `order` (ascending), then `createdAt` (descending)

		- Same response structure as banners

	

	- `POST /api/ads/carousel` — (admin only) create carousel item

		- PreHandler: `verifyJWT`, `requireRole('admin')`

		- Headers: `Authorization: Bearer <TOKEN>`

		- Body: Same as banner (title, image, link, order, active, meta)

		- Example:

		```bash

		curl -X POST 'http://localhost:5000/api/ads/carousel' \

			-H 'Content-Type: application/json' \

			-H 'Authorization: Bearer <ADMIN_TOKEN>' \

			-d '{

				"title": "Featured Artisan",

				"image": "https://cloudinary.com/.../slide1.jpg",

				"link": "/artisans/featured",

				"order": 1,

				"active": true,

				"meta": { "duration": 3000 }

			}'

		```

	---

	### **Generic Ad Management (CRUD)**

	- `GET /api/ads` — (public) list all ads

		- Query params:

			- `type` (string) — filter by type: `marquee`, `banner`, `carousel`, `general`

		- Example: `GET /api/ads?type=banner`

	

	- `POST /api/ads` — (admin only) create generic ad

		- PreHandler: `verifyJWT`, `requireRole('admin')`

		- Headers: `Authorization: Bearer <TOKEN>`

		- Body:

		```json

		{

			"type": "general",

			"title": "Custom Ad",

			"text": "Ad description",

			"image": "https://...",

			"link": "https://...",

			"active": true,

			"order": 0,

			"meta": {}

		}

		```

	

	- `GET /api/ads/:id` — (public) get single ad by ID

		- Response: Single ad object

		- Errors: 404 if not found

	

	- `PUT /api/ads/:id` — (admin only) update ad

		- PreHandler: `verifyJWT`, `requireRole('admin')`

		- Headers: `Authorization: Bearer <TOKEN>`

		- Body: Any ad fields to update

		- Example:

		```bash

		curl -X PUT 'http://localhost:5000/api/ads/64a1e2f...' \

			-H 'Content-Type: application/json' \

			-H 'Authorization: Bearer <ADMIN_TOKEN>' \

			-d '{

				"active": false,

				"title": "Updated Title"

			}'

		```

	

	- `DELETE /api/ads/:id` — (admin only) delete ad

		- PreHandler: `verifyJWT`, `requireRole('admin')`

		- Headers: `Authorization: Bearer <TOKEN>`

		- Response: `{ "ok": true }`

		- Example:

		```bash

		curl -X DELETE 'http://localhost:5000/api/ads/64a1e2f...' \

			-H 'Authorization: Bearer <ADMIN_TOKEN>'

		```

	---

	### **Ad Model Fields**

	```javascript

	{

		_id: ObjectId,

		type: 'marquee' | 'banner' | 'carousel' | 'general',

		title: String,         // Ad title/heading

		text: String,          // Text content (primarily for marquee)

		image: String,         // Image URL (Cloudinary or external)

		link: String,          // Click destination URL

		active: Boolean,       // Show/hide ad (default: true)

		meta: Object,          // Custom metadata (duration, campaign, etc.)

		order: Number,         // Display order (lower = first, default: 0)

		createdBy: ObjectId,   // Admin user who created the ad

		createdAt: Date        // Creation timestamp

	}

	```

	---

	### **Admin Ad Management Workflow**

	**1. Create Marquee:**

	```bash

	POST /api/ads/marquee

	Body: { "text": "Welcome message", "active": true }

	```

	**2. List All Ads:**

	```bash

	GET /api/ads

	GET /api/ads?type=banner  # Filter by type

	```

	**3. Create Banner:**

	```bash

	POST /api/ads/banner

	Body: { "title": "Promo", "image": "https://...", "order": 1 }

	```

	**4. Update Ad:**

	```bash

	PUT /api/ads/:id

	Body: { "active": false }  # Disable ad

	```

	**5. Delete Ad:**

	```bash

	DELETE /api/ads/:id

	```

	**Tips:**

	- Use `order` field to control display sequence (lower numbers first)

	- Set `active: false` to hide ads without deleting

	- Use `meta` object for custom properties like animation duration, target audience, etc.

	- Upload images to Cloudinary first, then include URL in ad creation

	- Only one marquee text is active at a time (upsert behavior)

	---

GET /api/jobs/:id/applications — (protected, job owner client) list applications.
POST /api/jobs/:id/applications/:appId/accept — accept an application (creates Booking).
DELETE /api/jobs/:id — close job (owner only).

Chat (Realtime + REST)

Overview: The project stores chat threads in the Chat model (src/models/Chat.js) and supports both REST endpoints and a Socket.IO-based realtime API. Chats are usually tied to a Booking (server creates a chat when a booking is created/paid) but threads can also be fetched directly if you have the threadId and are a participant.

Model: Chat documents include bookingId, participants (array of User ids), messages (embedded array with senderId, message, timestamp, seen), and isClosed.

REST Endpoints:

GET /api/chat/:threadId — (protected) fetch a chat thread. Requires Authorization: Bearer <TOKEN>. Only participants or admin may fetch.

Response: { success: true, data: <chat document> }

POST /api/chat/:threadId — (protected) send a message via REST (falls back to same persistence as sockets).

Body: { text: string } — the controller now uses the authenticated user as the sender; do not include senderId in the body.
Response: 201 with the saved message.

GET /api/chat/booking/:bookingId — (protected) fetch chat by the bookingId and include participant name and profileImage for both artisan and customer.

Authorization: Authorization: Bearer <TOKEN> (must be a participant: the booking's customerId or the booked artisanId, or an admin).
Path params: bookingId — the booking ObjectId.
Behavior: returns the chat thread tied to the booking and populates participants (each with name, role, and profileImageUrl) and messages with sender name and senderImageUrl where available.
Response (200):

 {

   "success": true,

   "data": {

     "threadId": "64a1e2f...",

     "bookingId": "64b2c3d...",

     "participants": [ { "_id": "64c3d4e...", "name": "John Doe", "role": "artisan", "profileImageUrl": "https://.../john.jpg" }, { "_id": "64b2c3d...", "name": "Alice Customer", "role": "customer", "profileImageUrl": "https://.../alice.jpg" } ],

     "messages": [ { "_id": "64f0a1b...", "senderId": "64c3d4e...", "senderName": "John Doe", "senderImageUrl": "https://.../john.jpg", "message": "Hello", "timestamp": "2026-01-16T10:00:00.000Z", "seen": false } ],

     "isClosed": false

   }

 }

Errors: 400 invalid id, 401 unauthenticated, 403 forbidden (not a participant), 404 not found.

Realtime (Socket.IO)

Server exposes a Socket.IO endpoint attached to the same HTTP server. The client MUST send the app JWT in the handshake authentication. Example handshake (client):

// client (browser or Node) example using socket.io-client

import { io } from 'socket.io-client';

const socket = io('https://your-api.example.com', { auth: { token: '<JWT_TOKEN>' } });

socket.on('connect', () => console.log('connected', socket.id));

- Handshake: send `{ auth: { token: '<JWT>' } }` when creating the socket.

- Events supported (server -> client and client -> server):

	- `join` (client -> server): join a thread room. Payload: `{ threadId }`. Ack: `{ success: true }` or error.

	- `leave` (client -> server): leave a thread room. Payload: `{ threadId }`.

	- `message` (client -> server): send a message. Payload: `{ threadId, text, meta? }`. Server persists the message and emits it to the thread room and each participant's personal room. Ack returns the saved message object.

	- `thread_message` (server -> client): emitted to individual participants when a message is posted (useful if not joined to thread room).

	- `typing` (client -> server): broadcast typing state to other participants. Payload: `{ threadId, typing: true|false }`.

	- `read` (client -> server): mark messages as read. Payload: `{ threadId, messageIds: [ ... ] }`. Server marks `seen: true` for those messages and emits `read` to the thread room.

- Rooms:

	- Per-thread room: `threadId` — clients exchange `message`, `typing`, and `read` events in this room.

	- Per-user room: each connected socket joins a room named by the `userId` from the JWT. The server emits `thread_message` or `thread_created` to these rooms so offline users (or those not joined to a thread) can still receive notifications.

Authorization & Security:
The socket handshake is authenticated with your existing JWT. The server will disconnect sockets with invalid or missing tokens.

Support Chat (Realtime & REST)

The platform includes a lightweight support chat for users to reach admins. Support threads reuse the Chat model and are delivered via REST and Socket.IO.

REST endpoints:

POST /api/support — create support thread. Body: { subject?: string, message: string }. Auth: Bearer token. Response: created Chat thread.
POST /api/support/:threadId/messages — post message to support thread. Body: { message: string }. Auth: Bearer token. Response: saved message.
GET /api/support/mine — list support threads the authenticated user participates in. Auth: Bearer token.
GET /api/support — admin-only: list all support threads. Auth: Bearer token + admin role.

Socket events:

support_thread_created (server -> admin/user): { threadId, userId? } — emitted when a new support thread is created.
support_message (server -> admin/participants): { threadId, message } — emitted when a new message is posted.

Admin sockets automatically join an admin room on connection (when JWT includes role: 'admin') so admins receive support_thread_created and support_message events.

Server validates that a user is a participant of a thread before allowing join or message actions.
For REST sends, the server uses request.user.id as the sender and validates participant membership.

Client flow examples:

Connect with JWT.
When notified of a new booking (or after booking payment), fetch or receive thread_created which includes threadId.
socket.emit('join', { threadId }, ack => { /* joined */ }); then socket.emit('message', { threadId, text: 'Hello' }, ack => { /* message saved */ });

Server integration points:

The booking/quote accept flow creates a Booking and (after payment) will create a Chat for participants and emit a thread_created/notification so both parties can join the chat UI.
The notifier utility (src/utils/notifier.js) will emit notifications over Socket.IO when fastify.io exists, so client notifications and chat events can be combined.

Notes & recommendations:

Pagination: the current GET /api/chat/:threadId returns the whole thread. For production, consider adding paginated message fetching (e.g. GET /api/chat/:threadId/messages?page=&limit=) or moving messages to a separate Message collection for very active threads.
Scaling: when running multiple Node instances, attach a Redis adapter to Socket.IO so io.to() works across processes (use socket.io-redis or @socket.io/redis-adapter).
Attachments: upload files via your existing Cloudinary flow and include the returned URL in the meta field of a message.

Central Feed (Dashboard)

Overview: A single endpoint that aggregates important data across collections for dashboard views. The response is role-aware:

admin receives global summaries and recent items across Users, Bookings, Jobs, Quotes, and Transactions.
artisan receives their own recent bookings, quotes, transactions, reviews, and wallet summary (including totalJobs).
user (customer) receives their own recent bookings, quotes and transactions.

Endpoint: GET /api/admin/central — (protected)

Authentication: Authorization: Bearer <TOKEN> (JWT required). The endpoint tailors the response based on the role claim in the JWT.
Query params: limit (integer, optional) — number of recent items to return (default: 20).

Response (admin): { success: true, data: { summary: { counts: { users, artisans, bookings, transactionsTotal }, topArtisansByJobs: [...] }, recent: { bookings: [...], users: [...], transactions: [...], quotes: [...], jobs: [...] } } }

Response (artisan): { success: true, data: { summary: { ... }, mine: { bookings: [...], quotes: [...], transactions: [...], reviews: [...], wallet: { totalJobs, balance, totalEarned, ... } } } }

Response (user/customer): { success: true, data: { summary: { ... }, mine: { bookings: [...], quotes: [...], transactions: [...] } } }

Notes:

The wallet object for artisans exposes totalJobs (the number of jobs recorded in the Wallet collection), totalEarned, and balance and is useful for showing artisan performance stats.
The topArtisansByJobs array is derived from the Wallet collection and shows top artisans ordered by totalJobs (includes basic user profile and wallet totals).
The route is protected by JWT; if you want to restrict admin summaries strictly to admins, add requireRole('admin') to the route. Currently the endpoint returns role-specific payloads depending on the token claims.
For large teams or dashboards, consider requesting only specific sections with additional query parameters (e.g. ?sections=bookings,transactions) to reduce payload size.

Notifications

Overview: The app persists notifications in a Notification collection and emits real-time notifications over Socket.IO when available. Many server actions already create notifications (job created, artisan applied, booking created, quote events, payment events). These endpoints let clients list and manage notifications in-app.

Model: Notification documents include userId, type, title, body, data (mixed), read (boolean), and createdAt.

Endpoints: (all protected — require Authorization: Bearer <TOKEN>)

GET /api/notifications — list current user's notifications

Query params: page (number), limit (number), unread=true (optional to filter only unread)
Response: { success: true, data: [ ...notifications ], meta: { page, limit, total } }

GET /api/notifications/:id — fetch a single notification (must belong to authenticated user or admin)

POST /api/notifications/mark-read — mark notifications as read (bulk)

Body: { ids: ['<notifId1>', '<notifId2>'] }
Response: { success: true, modifiedCount: <n> }

POST /api/notifications/mark-all-read — mark all notifications for the authenticated user as read

DELETE /api/notifications/:id — delete a single notification (owner or admin)

Notifications created by server actions (mapping):

Job created: when a user creates a job (POST /api/jobs), the server calls notifyArtisansAboutJob() which creates notifications for matched artisans and sends optional emails inviting them to apply.
Artisan applies to job: when an artisan applies (POST /api/jobs/:id/apply), the job owner (client) receives a notification (type: 'application').
Chat messages: the chat flow emits realtime message events; you may also see notifications created in booking/quote lifecycle (e.g., thread_created, booking events) — clients should subscribe to Socket.IO notification events or poll GET /api/notifications.
Profile completion / KYC: when a user or artisan completes profile steps or KYC, the server may create notifications (e.g., kyc events). The client should call GET /api/notifications to surface these messages.
Payment history (success/fail): payment webhook and confirm flows create notifications for success, holding, refunds, and failures; both artisans and customers will receive notifications when transactions update.
Booking after payment: when payment is confirmed and a booking is created/held, the artisan receives a booking notification (see booking flows in POST /api/bookings and webhook handlers).
Quotes: when a client sends a quote request or an artisan replies with a quote, respective notifications with type: 'quote' are created for the recipient.

Client flow recommendations:

On app startup connect to Socket.IO with the app JWT and subscribe to notification events to receive push updates in real-time.
On app screens call GET /api/notifications?page=1&limit=20 to fetch recent notifications and display unread counts (filter unread=true to show badges).
Mark notifications read when the user opens them by calling POST /api/notifications/mark-read with the notification ids or POST /api/notifications/mark-all-read when clearing all.

Attachments

POST /api/jobs/:id/attachments — (protected, job client) multipart upload for attachments. Field name for files: file (multiple supported). The server either uses previously-run upload middleware results or streams files directly to Cloudinary.

Flutter: create job (JSON)

final res = await http.post(Uri.parse('http://localhost:5000/api/jobs'),

	headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},

	body: jsonEncode({

		'title': 'Install kitchen tile',

		'description': 'Details...',

		'trade': ['tiling','flooring'],

		'location': 'Ikeja, Lagos',

		'coordinates': [-3.0, 6.5],

		'budget': 50000,

		'schedule': '2026-01-15T09:00:00.000Z'

	}),

);

Attach file example (Flutter multipart)

final uri = Uri.parse('http://localhost:5000/api/jobs/$jobId/attachments');

final req = http.MultipartRequest('POST', uri)

	..headers['Authorization'] = 'Bearer $token';

req.files.add(await http.MultipartFile.fromPath('file', '/path/to/file.jpg'));

final streamed = await req.send();

final resp = await http.Response.fromStream(streamed);



Artisans

Artisans

Overview: Create and manage artisan profiles. Artisans can showcase their trade skills, experience, portfolio images, service areas, and pricing. The API supports both JSON requests (with pre-uploaded image URLs) and multipart/form-data requests (which upload images directly to Cloudinary).

Category Integration: Artisans can now be organized using hierarchical job categories:

The categories field (array of ObjectId references) links artisans to JobCategory documents
The legacy trade field (array of strings) is kept for backward compatibility
Use categoryId query parameter to filter artisans by category in listing/search endpoints
Categories support unlimited nesting (e.g., Construction → Plumbing → Residential Plumbing)
See Job Categories section for category management endpoints

GET /api/artisans — list artisans

Query params: page, limit, trade, categoryId, sortBy (default: 'rating'), q, location
New:
q — Search/filter by trade/profession name (supports comma-separated values, case-insensitive regex match)
location — Filter by service area address (case-insensitive text match)
categoryId — Filter artisans by job category (MongoDB ObjectId). Artisans can now be associated with hierarchical categories via the categories field.
Response (200): { success: true, data: [{ _id, userId, trade, categories, experience, bio, portfolio, serviceArea, pricing, rating, verified, artisanAuthDetails: { name, profileImage, email, phone, kycVerified, isVerified }, user: {...}, reviewsSummary: { avgRating, count }, kycDetails: { status, idType, verified, submittedAt }, bookingsStats: { total, completed } }] }
New fields:
kycDetails: KYC verification information (null if no KYC submitted)
status: 'pending' | 'approved' | 'rejected'
idType: Type of ID submitted (e.g., 'national_id', 'passport')
verified: boolean (true if status === 'approved')
submittedAt: ISO date when KYC was submitted
bookingsStats: Booking statistics for the artisan
total: Total number of bookings
completed: Number of completed bookings
Examples:
Search by trade: GET /api/artisans?q=electrician&page=1&limit=12
Search by location: GET /api/artisans?location=Bwari,%20Abuja&page=1&limit=12
Combined search: GET /api/artisans?q=plumber&location=Lagos&page=1&limit=12
Filter by category: GET /api/artisans?categoryId=507f1f77bcf86cd799439011&page=1
Note: Returns empty array if no artisans match the search criteria

GET /api/artisans/search — search verified artisans with location/trade filters

Query params: page, limit, trade, categoryId, sortBy, lat, lon, radiusKm, location, q
New: categoryId — Filter artisans by job category ID
Response (200): { success: true, data: [<artisan objects with artisanAuthDetails, reviewsSummary, kycDetails, and bookingsStats>] }
Location search:
Provide lat & lon (+ radiusKm) for geospatial search (uses MongoDB $near)
OR provide location (text) to geocode with Mapbox (if MAPBOX_TOKEN env var is set) or fallback to address regex
Trade filter supports comma-separated values: ?trade=plumber,electrician

GET /api/artisans/:id — get artisan profile by ID

Response (200): { success: true, data: { _id, userId, trade, experience, bio, portfolio, ... } }
Errors: 404 if not found, 500 for server errors

POST /api/artisans — (protected) create artisan profile

PreHandler: verifyJWT
Headers: Authorization: Bearer <TOKEN>
Accepts TWO content types:

💡 Recommendation: Use JSON (Option 1) for better control, easier debugging, and cleaner code. Upload images to Cloudinary separately first, then include the URLs. Use Multipart (Option 2) only if you need to handle file uploads directly from the client without pre-uploading.

Option 1: JSON (application/json) — Portfolio images must be uploaded to Cloudinary beforehand, and URLs included in the request: - Body (JSON): - trade: array of strings (required) — e.g. ["plumber", "electrician"] (legacy field, kept for backward compatibility) - categories: array of ObjectId strings (optional) — e.g. ["507f1f77bcf86cd799439011", "507f191e810c19729de860ea"] — references to JobCategory documents. Use this for hierarchical category organization. - experience: number (required) — years of experience - certifications: array of strings (optional) - bio: string (optional) — artisan bio/description - portfolio: array of portfolio items (optional) — [{ title, description, images: ["https://cloudinary.com/..."], beforeAfter: true/false }] - serviceArea: object (optional) — { address, coordinates: [lon, lat], radius } - pricing: object (optional) — { perHour, perJob } - availability: array of strings (optional) - Example (curl):

curl -X POST 'http://localhost:5000/api/artisans' \

	-H 'Authorization: Bearer <TOKEN>' \

	-H 'Content-Type: application/json' \

	-d '{

		"trade": ["plumber"],

		"categories": ["507f1f77bcf86cd799439011"],

		"experience": 5,

		"bio": "Expert plumber with 5 years experience",

		"portfolio": [{

			"title": "Recent Projects",

			"description": "Bathroom renovations",

			"images": ["https://res.cloudinary.com/.../image1.jpg", "https://res.cloudinary.com/.../image2.jpg"],

			"beforeAfter": true

		}],

		"pricing": { "perHour": 50, "perJob": 300 }

	}'

	- Flutter example (JSON):

import 'dart:convert';

import 'package:http/http.dart' as http;

final response = await http.post(

	Uri.parse('http://localhost:5000/api/artisans'),

	headers: {

		'Authorization': 'Bearer $token',

		'Content-Type': 'application/json',

	},

	body: jsonEncode({

		'trade': ['plumber'],

		'categories': ['507f1f77bcf86cd799439011'], // Array of category IDs

		'experience': 5,

		'bio': 'Expert plumber',

		'portfolio': [{

			'title': 'Recent work',

			'images': ['https://res.cloudinary.com/.../image1.jpg'],

			'beforeAfter': false

		}],

		'pricing': {'perHour': 50}

	}),

);

final data = jsonDecode(response.body);

// data['data'] contains the created artisan profile

**Option 2: Multipart/form-data** — Upload portfolio images directly; server streams them to Cloudinary:

	- **File size limit:** 10MB per file

	- **Supported formats:** JPG, PNG, GIF, WebP

	- Body (multipart/form-data):

		- Form fields: `trade` (JSON array string), `experience` (number), `bio`, `certifications` (JSON array string), etc.

		- File fields: multiple files with any field name (e.g., `portfolioImage1`, `portfolioImage2`) — server uploads all to Cloudinary and adds URLs to portfolio

	- Example (curl):

curl -X POST 'http://localhost:5000/api/artisans' \

	-H 'Authorization: Bearer <TOKEN>' \

	-F 'trade=["plumber"]' \

	-F 'experience=5' \

	-F 'bio=Expert plumber' \

	-F 'portfolioImage1=@/path/to/image1.jpg' \

	-F 'portfolioImage2=@/path/to/image2.jpg'

	- Flutter example (multipart):

import 'package:http/http.dart' as http;

final request = http.MultipartRequest('POST', Uri.parse('http://localhost:5000/api/artisans'));

request.headers['Authorization'] = 'Bearer $token';

request.fields['trade'] = jsonEncode(['plumber']);

request.fields['experience'] = '5';

request.fields['bio'] = 'Expert plumber';

// Add portfolio images

request.files.add(await http.MultipartFile.fromPath('portfolioImage1', '/path/to/image1.jpg'));

request.files.add(await http.MultipartFile.fromPath('portfolioImage2', '/path/to/image2.jpg'));

final streamedResponse = await request.send();

final response = await http.Response.fromStream(streamedResponse);

final data = jsonDecode(response.body);

// data['data'] contains the created artisan profile with Cloudinary URLs

- Response (201): `{ success: true, data: { _id, userId, trade, experience, portfolio: [{ images: ["https://cloudinary.com/..."] }], ... } }`

- Errors: 400 invalid payload/validation error, 401 unauthorized, 413 payload too large (>10MB), 500 server errors

- **Note:** The authenticated user's role is automatically set to `'artisan'` after profile creation.

---

**When to use JSON vs Multipart:**

- **Use JSON** when:

	- You have complex nested data structures

	- Images are already hosted or can be pre-uploaded

	- You want easier debugging (can inspect payloads)

	- Frontend framework prefers JSON APIs

- **Use Multipart** when:

	- Client uploads images directly without pre-processing

	- Mobile apps need to send photos from camera/gallery

	- You want a single-request upload experience

	- File metadata needs to be preserved

---

PUT /api/artisans/me — (protected) update authenticated user's artisan profile

PreHandler: verifyJWT (user must be authenticated and must have an artisan profile).
Headers: Authorization: Bearer <TOKEN>
Accepts TWO content types (same as POST):

Option 1: JSON (application/json): - Body: allowed fields (same as POST) - trade: array of strings - categories: array of ObjectId strings — references to JobCategory documents - experience: number - certifications: array of strings - bio: string - portfolio: array of portfolio items ({ title, description, images[], beforeAfter }) - serviceArea: object { address, coordinates: [lon, lat], radius } - pricing: object { perHour, perJob } - availability: array of strings - verified: boolean (only applied when requester's role is admin) - Example (curl):

curl -X PUT 'http://localhost:5000/api/artisans/me' \

	-H 'Authorization: Bearer <TOKEN>' \

	-H 'Content-Type: application/json' \

	-d '{

		"trade": ["plumber","electrician"],

		"experience": 6,

		"bio": "Updated bio - I fix wiring and pipes",

		"portfolio": [{

			"title": "New projects",

			"images": ["https://res.cloudinary.com/.../new-image.jpg"]

		}]

	}'

**Option 2: Multipart/form-data** — Upload new portfolio images:

	- Body (multipart/form-data): same as POST

	- Example (Flutter):

final request = http.MultipartRequest('PUT', Uri.parse('http://localhost:5000/api/artisans/me'));

request.headers['Authorization'] = 'Bearer $token';

request.fields['bio'] = 'Updated bio';

request.fields['experience'] = '6';

request.files.add(await http.MultipartFile.fromPath('newImage', '/path/to/new-image.jpg'));

final streamedResponse = await request.send();

final response = await http.Response.fromStream(streamedResponse);

- Response (200): `{ success: true, data: <updated artisan document> }`.

- Errors: 400 invalid payload, 401 unauthorized, 404 artisan profile not found, 500 server errors.

PATCH /api/artisans/:id/verify — (protected, admin only) verify an artisan
PreHandler: verifyJWT, requireRole('admin')
Headers: Authorization: Bearer <TOKEN>
Params: id — artisan profile ObjectId
Actions performed:
Sets Artisan.verified to true
Sets User.isVerified and User.kycVerified to true
Sends in-app notification to the artisan
Sends email notification (if SMTP is configured)
Example (curl):

curl -X PATCH 'http://localhost:5000/api/artisans/<artisan_id>/verify' \

	-H 'Authorization: Bearer <ADMIN_TOKEN>'

- Response (200):

{

	"success": true,

	"message": "Artisan verified successfully",

	"data": {

		"artisan": { "_id": "64a1e2f...", "verified": true },

		"user": { "_id": "64a1d3c...", "isVerified": true, "kycVerified": true }

	}

}

- Errors: 400 invalid artisan ID or no associated user, 401 unauthorized, 403 forbidden (not admin), 404 artisan not found, 500 server errors

PATCH /api/artisans/:id/unverify — (protected, admin only) revoke artisan verification
PreHandler: verifyJWT, requireRole('admin')
Headers: Authorization: Bearer <TOKEN>
Params: id — artisan profile ObjectId
Actions performed:
Sets Artisan.verified to false
Sets User.isVerified and User.kycVerified to false
Sends in-app notification to the artisan
Sends email notification (if SMTP is configured)
Example (curl):

curl -X PATCH 'http://localhost:5000/api/artisans/<artisan_id>/unverify' \

	-H 'Authorization: Bearer <ADMIN_TOKEN>'

- Response (200):

{

	"success": true,

	"message": "Artisan verification revoked successfully",

	"data": {

		"artisan": { "_id": "64a1e2f...", "verified": false },

		"user": { "_id": "64a1d3c...", "isVerified": false, "kycVerified": false }

	}

}

- Errors: 400 invalid artisan ID or no associated user, 401 unauthorized, 403 forbidden (not admin), 404 artisan not found, 500 server errors

- **Note:** Unverified artisans will no longer appear in search results (`GET /api/artisans/search`) or public listings (`GET /api/artisans`) for regular users. Only admins can see unverified artisans in listings.





Job Categories

Overview: Manage and list job categories used to group jobs (e.g. Construction, Plumbing, Electrical). Categories support parent-child relationships for subcategories with unlimited nesting levels. Categories are public for listing, but creation, update and deletion are restricted to admins.

Category Structure:

Top-level categories have parentId: null (e.g., "Construction", "Home Services")
Subcategories reference a parent via parentId (e.g., "Plumbing" under "Construction")
Sub-subcategories can be created by setting parentId to a subcategory ID
Each category can have: name, slug, description, icon, order, isActive

GET /api/job-categories — public

Query params:
parentId (string) — Filter by parent category:
?parentId=null — Get only top-level categories
?parentId=<id> — Get subcategories of specific parent
Omit to get all categories
includeSubcategories (boolean, default: false) — Include nested subcategories in response
page (number), limit (number), q (search string), slug (exact slug)
Response (200): { success: true, data: [{ _id, name, slug, description, parentId, icon, order, isActive, createdAt, subcategories?: [] }] }
Examples:

 # Get all top-level categories

 GET /api/job-categories?parentId=null

 

 # Get subcategories of Construction

 GET /api/job-categories?parentId=65abc123...

 

 # Get all categories with nested structure

 GET /api/job-categories?includeSubcategories=true

GET /api/job-categories/:id — public

Params: id — category ObjectId
Response (200): { success: true, data: { _id, name, slug, description, parentId, icon, order, isActive, createdAt, subcategories: [...] } }
Note: Response automatically includes parent details (if exists) and all direct subcategories
Errors: 404 if not found, 400 for invalid id format

POST /api/job-categories — (protected, admin only)

PreHandler: verifyJWT, requireRole('admin')

Headers: Authorization: Bearer <TOKEN>

Body (application/json):

name (string, required) — display name for category (must be unique within same parent)
slug (string, optional) — URL-safe slug
description (string, optional)
parentId (string, optional) — Parent category ID. Omit or set to null for top-level category
icon (string, optional) — Icon name, emoji, or URL for UI display
order (number, optional, default: 0) — Display order (lower numbers first)
isActive (boolean, optional, default: true) — Enable/disable category

Example: Create top-level category

 curl -X POST 'http://localhost:5000/api/job-categories' \

   -H 'Content-Type: application/json' \

   -H 'Authorization: Bearer <ADMIN_TOKEN>' \

   -d '{

     "name": "Construction",

     "slug": "construction",

     "description": "All construction-related services",

     "icon": "🏗️",

     "order": 1

   }'

Example: Create subcategory

 curl -X POST 'http://localhost:5000/api/job-categories' \

   -H 'Content-Type: application/json' \

   -H 'Authorization: Bearer <ADMIN_TOKEN>' \

   -d '{

     "name": "Plumbing",

     "slug": "plumbing",

     "description": "Water pipes, drainage, and fixtures",

     "parentId": "65abc123...",

     "icon": "🚰",

     "order": 1

   }'

PowerShell example:

 $body = @{ 

   name='Plumbing'

   slug='plumbing'

   description='Pipe and waterworks'

   parentId='65abc123...'

   icon='🚰'

   order=1

 } | ConvertTo-Json

 Invoke-RestMethod -Uri 'http://localhost:5000/api/job-categories' -Method Post -Headers @{ Authorization = 'Bearer <ADMIN_TOKEN>' } -Body $body -ContentType 'application/json'

Successful response (201):

 { 

   "success": true, 

   "data": { 

     "_id": "64a1e2f...", 

     "name": "Plumbing", 

     "slug": "plumbing", 

     "description": "Pipe and waterworks",

     "parentId": "65abc123...",

     "icon": "🚰",

     "order": 1,

     "isActive": true,

     "createdAt": "2026-01-21T10:00:00.000Z" 

   } 

 }

Errors:
400 — missing name, invalid parentId, or parent category not found
401 — missing/invalid token
403 — authenticated but not admin
409 — duplicate name within same parent category

PUT /api/job-categories/:id — (protected, admin only)

Body: same fields as POST (all optional)
Special behaviors:
Can change parentId to move category to different parent or make it top-level (parentId: null)
Cannot make category its own parent (returns 400 error)
Validates new parent exists before updating
Response (200): { success: true, data: <updated category> }
Example request (curl):

 curl -X PUT 'http://localhost:5000/api/job-categories/64a1e2f...' \

   -H 'Content-Type: application/json' \

   -H 'Authorization: Bearer <ADMIN_TOKEN>' \

   -d '{

     "name": "Plumbing & Drainage",

     "description": "Updated description",

     "parentId": "65def456...",

     "order": 2,

     "isActive": true

   }'

PowerShell example:

 $body = @{ 

   name='Plumbing & Drainage'

   description='Updated description'

   parentId='65def456...'

   isActive=$true

 } | ConvertTo-Json

 Invoke-RestMethod -Uri 'http://localhost:5000/api/job-categories/64a1e2f...' -Method Put -Headers @{ Authorization = 'Bearer <ADMIN_TOKEN>' } -Body $body -ContentType 'application/json'

Successful response (200):

 { 

   "success": true, 

   "data": { 

     "_id": "64a1e2f...", 

     "name": "Plumbing & Drainage", 

     "slug": "plumbing-drainage", 

     "description": "Updated description",

     "parentId": "65def456...",

     "icon": "🚰",

     "order": 2,

     "isActive": true,

     "createdAt": "2026-01-21T10:00:00.000Z" 

   } 

 }

DELETE /api/job-categories/:id — (protected, admin only)

Protection: Cannot delete categories that have subcategories. Delete all subcategories first.
Response (200): { success: true, message: 'Category removed' }
Errors:
404 if not found
400 if category has subcategories
Example request (curl):

curl -X DELETE 'http://localhost:5000/api/job-categories/64a1e2f...' \

  -H 'Authorization: Bearer <ADMIN_TOKEN>'

PowerShell example:

Invoke-RestMethod -Uri 'http://localhost:5000/api/job-categories/64a1e2f...' -Method Delete -Headers @{ Authorization = 'Bearer <ADMIN_TOKEN>' }



Example Category Hierarchy:

Construction (parentId: null)

├── Plumbing (parentId: Construction._id)

│   ├── Residential Plumbing (parentId: Plumbing._id)

│   └── Commercial Plumbing (parentId: Plumbing._id)

├── Electrical (parentId: Construction._id)

│   ├── Wiring (parentId: Electrical._id)

│   └── Installation (parentId: Electrical._id)

└── Carpentry (parentId: Construction._id)

Home Services (parentId: null)

├── Cleaning (parentId: Home Services._id)

└── Repair (parentId: Home Services._id)

Flutter Example:

// Get all top-level categories

final response = await http.get(

  Uri.parse('http://localhost:5000/api/job-categories?parentId=null')

);

// Get subcategories of Construction

final subResponse = await http.get(

  Uri.parse('http://localhost:5000/api/job-categories?parentId=$constructionId')

);

// Create subcategory

final createResponse = await http.post(

  Uri.parse('http://localhost:5000/api/job-categories'),

  headers: {

    'Content-Type': 'application/json',

    'Authorization': 'Bearer $adminToken'

  },

  body: jsonEncode({

    'name': 'Plumbing',

    'slug': 'plumbing',

    'parentId': constructionId,

    'icon': '🚰',

    'order': 1

  })

);



Invoke-RestMethod -Uri 'http://localhost:5000/api/job-categories/64a1e2f...' -Method Delete -Headers @{ Authorization = 'Bearer <ADMIN_TOKEN>' }

	- Successful response (200):

```json

{ "success": true, "message": "Category removed" }

Notes & validation rules:

name is required on create and should be a readable title. If slug is not provided the server will generate a kebab-case slug from name.
slug should be URL-safe (lowercase, hyphens). The server will attempt to normalize it; however providing a precomputed slug is recommended for deterministic clients.
categoryId used in jobs (see POST /api/jobs) expects a 24-character MongoDB ObjectId string and the server validates the referenced category exists; invalid or non-existing ids will produce a 400 or 404 respectively.
Example: creating a job with categoryId (job create uses the same Authorization header for clients):

curl -X POST 'http://localhost:5000/api/jobs' \

  -H 'Content-Type: application/json' \

  -H 'Authorization: Bearer <CLIENT_TOKEN>' \

  -d '{"title":"Fix kitchen sink","description":"Leaking pipe","categoryId":"64a1e2f..."}'



Bookings & Quotes

GET /api/bookings — (protected) list bookings for authenticated user. Supports page, limit, status.

GET /api/bookings — (protected) list bookings for authenticated user. Supports page, limit, status.

GET /api/bookings/customer/:customerId — (protected) get all bookings for a specific customer and include artisan user details and artisan profile (if available). Use this endpoint when a customer wants a history of their bookings together with artisan information.

GET /api/bookings/artisan/:artisanId — (protected) get all bookings assigned to a specific artisan and include the customer user details.

Authorization: Authorization: Bearer <TOKEN> (must be the same artisanId or an admin token). The route validates that the requesting user is either the artisan referenced by :artisanId or has the admin role.

Path params:

artisanId (string) — MongoDB ObjectId of the artisan whose bookings you want to fetch.

Query params:

page (number, optional) — page number for pagination (default: 1)
limit (number, optional) — items per page (default: 20)
status (string, optional) — filter bookings by status (e.g. pending, paid, completed, cancelled)

Response (200):

 {

 	"success": true,

 	"data": [

 		{

 			"booking": { "_id": "64a1e2f...", "customerId": "64b2c3d...", "artisanId": "64c3d4e...", "service": "Fix sink", "schedule": "...", "price": 50000, "status": "pending", "paymentStatus": "paid" },

 			"customerUser": { "_id": "64b2c3d...", "name": "Alice", "email": "alice@example.com", "profileImage": { "url": "https://..." } }

 		}

 	]

 }

Authorization: Authorization: Bearer <TOKEN> (must be the same customerId or an admin token). The route validates that the requesting user is either the customer referenced by :customerId or has the admin role.

Path params:

customerId (string) — MongoDB ObjectId of the customer whose bookings you want to fetch. The controller will reject the request with 403 if you are not authorized to view another customer's bookings.

Query params:

page (number, optional) — page number for pagination (default: 1)
limit (number, optional) — items per page (default: 20)
status (string, optional) — filter bookings by status (e.g. pending, paid, completed, cancelled)

Behavior / population details:

The endpoint returns an array of booking records. For each booking the server populates two additional objects:
artisanUser: The User document for the booking's artisanId (populated fields: _id, name, email, phone, profileImage).
artisanProfile: The Artisan profile document associated with that user (if available). This comes from the Artisan collection and may include fields such as businessName, trade, experience, rating, location, profileImage, and other artisan-specific metadata. If the artisan profile doesn't exist, artisanProfile will be null.
Implementation note: the server uses Mongoose populate to fetch the artisanUser and performs a lookup for the corresponding Artisan profile by user id. This provides a compact joined view so clients can render booking + artisan details without additional requests.

Response (200):

 {

 	"success": true,

 	"data": [

 		{

 			"booking": {

 				"_id": "64a1e2f...",

 				"customerId": "64b2c3d...",

 				"artisanId": "64c3d4e...",

 				"service": "Fix kitchen sink",

 				"schedule": "2026-01-15T09:00:00.000Z",

 				"price": 50000,

 				"status": "completed",

 				"paymentStatus": "paid",

 				"createdAt": "2026-01-16T10:00:00.000Z"

 			},

 			"artisanUser": {

 				"_id": "64c3d4e...",

 				"name": "John Doe",

 				"email": "john@example.com",

 				"phone": "+2348012345678",

 				"profileImage": "https://res.cloudinary.com/.../john.jpg"

 			},

 			"artisanProfile": {

 				"_id": "64d5e6f...",

 				"userId": "64c3d4e...",

 				"businessName": "John Plumbing",

 				"trade": ["plumbing"],

 				"experience": 5,

 				"rating": 4.8,

 				"location": "Lagos",

 				"profileImage": "https://res.cloudinary.com/.../art_profile.jpg"

 			}

 		}

 	],

 	"meta": { "page": 1, "limit": 20, "total": 42 }

 }

Errors:

400 — invalid customerId format
401 — missing/invalid token
403 — authenticated but not allowed to view the requested customer's bookings
404 — no bookings found (or optional: empty data array is returned)

Examples:

Curl:

 curl -H "Authorization: Bearer <TOKEN>" "http://localhost:5000/api/bookings/customer/64b2c3d...?page=1&limit=10"

PowerShell:

 Invoke-RestMethod -Uri 'http://localhost:5000/api/bookings/customer/64b2c3d...?page=1&limit=10' -Headers @{ Authorization = 'Bearer <TOKEN>' }

Flutter (simple example using http):

 final res = await http.get(

 	Uri.parse('http://localhost:5000/api/bookings/customer/$customerId?page=1&limit=10'),

 	headers: { 'Authorization': 'Bearer $token' },

 );

 final body = jsonDecode(res.body);

 final list = body['data']; // each item contains booking, artisanUser, artisanProfile

Performance & notes:

Population is convenient but can be heavier than returning only booking ids. If you expect very large result sets, prefer paginating tightly (limit) or create a dedicated aggregation endpoint that returns only the fields required by your UI.
If you need additional artisan fields included, the server can be extended to populate more fields from User or Artisan — open a request if you want more fields by default.

POST /api/bookings — create a booking (artisanId, schedule required), protected.

GET /api/bookings/:id — booking details.

DELETE /api/bookings/:id — cancel booking.

POST /api/bookings/:id/complete — mark complete (customer only) - releases payment to artisan.

POST /api/bookings/:id/accept — (NEW) artisan accepts booking (must be called within 24h after payment).

POST /api/bookings/:id/reject — (NEW) artisan rejects booking (auto-refunds customer).

GET /api/bookings/:id/refund — get refund status for booking (returns gateway/refund info).

Cancellation & Refund behavior:

When a booking is cancelled (customer or artisan rejection), the system uses two fields to represent money state:
paymentStatus: allowed values are unpaid or paid. After a refund is processed the server sets paymentStatus to unpaid (it does not use refunded).
refundStatus: tracks refund lifecycle and can be none, requested, or refunded.
Typical flows:
If a holding transaction exists, the API will attempt a gateway refund and set refundStatus accordingly. If gateway confirms refund, transaction.status becomes refunded, transaction.refundStatus = 'refunded', and the booking refundStatus = 'refunded' and paymentStatus = 'unpaid'.
If the gateway refund cannot be completed immediately, the system marks the refund as requested for manual reconciliation.
Use GET /api/bookings/:id/refund to query current refund state (it will call the payment gateway when possible and persist any status changes).
POST /api/bookings/hire — create a booking and initialize payment (protected): body requires artisanId, schedule, price, email.

NEW Direct Hire Flow with Artisan Approval:

Customer books artisan: POST /api/bookings/hire

Booking created with status: 'pending', paymentStatus: 'unpaid'
Paystack payment initialized
Customer completes payment

Payment confirmed: Webhook/admin calls POST /api/bookings/:id/confirm-payment

Transaction status → holding (escrowed)
Booking status → awaiting-acceptance (direct-hire only — artisan must accept)
Booking paymentStatus → paid
Artisan receives notification with 24-hour deadline

Artisan responds (within 24 hours):

Accept: POST /api/bookings/:id/accept
Booking status → accepted
Customer notified
Work can begin
Reject: POST /api/bookings/:id/reject (optional body: { "reason": "..." })
Booking status → cancelled
Auto-refund processed
Customer notified

Auto-rejection (if artisan doesn't respond):

After 24 hours, booking auto-cancelled
Refund processed automatically

Notes on Quote Flow vs Direct-Hire:

Quote-based flow (customer accepts a quote via POST /api/bookings/:id/quotes/:quoteId/accept): the application flow sets the booking to accepted and proceeds to initialize payment for the accepted quote. After successful payment the booking remains accepted and work can begin.
Direct-hire flow (POST /api/bookings/hire): after payment the booking is set to awaiting-acceptance and the assigned artisan must explicitly accept (POST /api/bookings/:id/accept) or reject. This prevents immediate automatic acceptance for direct hires.
Both parties notified
Work completion: Customer calls POST /api/bookings/:id/complete
Booking status → completed
Payment released to artisan (minus platform fee)
Auto-payout to artisan's bank or wallet credit

Booking Status Flow:

pending → awaiting-acceptance → accepted → in-progress → completed

                ↓

            cancelled (if rejected/expired)

Quotes

POST /api/bookings/:id/requirements — (protected, client) post requirement message for a booking.
POST /api/bookings/:id/quotes — (protected, artisan) create a quote; body items array required.
GET /api/bookings/:id/quotes — list quotes.
POST /api/bookings/:id/quotes/:quoteId/accept — accept quote.
POST /api/bookings/:id/pay-with-quote — initialize payment for accepted quote (protected).

Payment Webhook / Confirm Payment

Purpose: When a customer accepts a quote the client initializes a payment with the gateway. The server must verify the gateway callback/webhook and then mark the internal Transaction as held (escrow) and update the Booking paymentStatus to paid. The project exposes an internal endpoint to mark a booking transaction as held:

POST /api/bookings/:id/confirm-payment — (protected)
Behavior: finds the latest pending Transaction for the booking, sets status = 'holding', sets booking.paymentStatus = 'paid', and notifies the artisan that payment is held in escrow. This endpoint is intended to be called by a server-side webhook handler after verifying the payment gateway notification.

Security note: Do NOT expose this endpoint publicly. Use a gateway webhook handler that validates the gateway signature (or use your own server secret) and call this internal endpoint from your trusted server process (or call the internal confirm logic directly).

Paystack webhook verification (example, Node / Fastify): verify the x-paystack-signature header using your webhook secret and call the internal confirm logic once verified.

// Minimal Fastify webhook example (register raw body parser so you can compute HMAC)

import crypto from 'crypto';

fastify.post('/webhooks/paystack', { bodyLimit: 1048576 }, async (request, reply) => {

	const signature = request.headers['x-paystack-signature'];

	const secret = process.env.PAYSTACK_WEBHOOK_SECRET; // set this to your webhook secret in env

	const payload = request.rawBody || JSON.stringify(request.body);

	const expected = crypto.createHmac('sha512', secret).update(payload).digest('hex');

	if (!signature || signature !== expected) {

		return reply.code(400).send({ success: false, message: 'Invalid signature' });

	}

	const event = request.body?.event || request.body?.data?.event;

	const data = request.body?.data || request.body;

	// Example: on successful transaction, find bookingId in metadata and call confirm endpoint

	if (data && (data.status === 'success' || data.event === 'charge.success' || data.event === 'transaction.success')) {

		const bookingId = data.metadata?.bookingId || data.metadata?.referenceBookingId;

		if (bookingId) {

			// Call internal confirm endpoint (server-to-server call using a trusted token)

			// Option A: Call HTTP internal endpoint (recommended when webhook runs on separate process):

			// await fetch(`https://your-api.example.com/api/bookings/${bookingId}/confirm-payment`, { method: 'POST', headers: { Authorization: `Bearer ${process.env.INTERNAL_API_TOKEN}` } });

			// Option B: Import and call application logic directly (if webhook runs inside same codebase):

			const { confirmPayment } = await import('./src/controllers/bookingController.js');

			// Build a synthetic request object to reuse internal handler or refactor confirm logic into a service

			await confirmPayment({ params: { id: bookingId }, server: fastify, user: { id: process.env.SYSTEM_USER_ID } }, reply);

		}

	}

	return reply.send({ success: true });

});

Sample Paystack webhook payload (trimmed):

{

	"event": "charge.success",

	"data": {

		"reference": "tn_1AbCdeFGH",

		"status": "success",

		"amount": 25000,

		"metadata": { "bookingId": "64a1e2f...", "quoteId": "64b2f3a..." }

	}

}

How to call internal confirm endpoint manually (admin/server):

curl -X POST 'http://localhost:5000/api/bookings/<BOOKING_ID>/confirm-payment' \

	-H 'Authorization: Bearer <ADMIN_OR_INTERNAL_TOKEN>'

PowerShell example:

Invoke-RestMethod -Uri 'http://localhost:5000/api/bookings/<BOOKING_ID>/confirm-payment' -Method Post -Headers @{ Authorization = 'Bearer <ADMIN_OR_INTERNAL_TOKEN>' }

Implementation notes:
The codebase currently creates a Transaction with status pending when initializing payment and confirm-payment moves that Transaction to holding. The complete flow then releases funds from holding to released and credits the artisan (or attempts auto-payout).
By default the quote flow initializes payment for the quote serviceCharge. If you want to hold the full quote total (items + serviceCharge), change the amount used when initializing the transaction.
For reliability, prefer using a webhook endpoint that verifies gateway signatures and then calls internal confirm logic using a server-to-server call or by invoking internal service code directly.

Job Quotes

POST /api/jobs/:id/quotes — (protected, artisan) create a quote for a Job (not a Booking).

Body (application/json):
items (array, optional) — list of { name: string, cost: number, qty: integer }
serviceCharge (number, optional)
notes (string, optional)
PreHandler: verifyJWT, requireRole('artisan')
Response (201): { success: true, data: <quote> }
Errors: 400 invalid body, 401 unauthorized, 404 job not found, 409 duplicate active quote

Example (curl):

curl -X POST 'http://localhost:5000/api/jobs/<JOB_ID>/quotes' \

	-H 'Content-Type: application/json' \

	-H 'Authorization: Bearer <ARTISAN_TOKEN>' \

	-d '{"items":[{"name":"Material","cost":1000,"qty":1}],"serviceCharge":250,"notes":"I can start tomorrow"}'

PowerShell example:

$body = @{ items = @( @{ name='Material'; cost=1000; qty=1 } ); serviceCharge = 250; notes = 'I can start tomorrow' } | ConvertTo-Json

Invoke-RestMethod -Uri 'http://localhost:5000/api/jobs/<JOB_ID>/quotes' -Method Post -Headers @{ Authorization = 'Bearer <ARTISAN_TOKEN>' } -Body $body -ContentType 'application/json'

GET /api/jobs/:id/quotes — (protected) list quotes for a Job; returns quotes with artisan user minimal fields and the job data attached.
Example (curl):

curl -H 'Authorization: Bearer <TOKEN>' 'http://localhost:5000/api/jobs/<JOB_ID>/quotes'



Payments

POST /api/payments — (protected) create a payment record (body amount, currency required).
POST /api/payments/verify — verify a payment (protected).
POST /api/payments/webhook — public webhook endpoint used by the payment gateway.
POST /api/payments/initialize — (protected) helper to initialize Paystack transaction server-side.

Wallet

GET /api/wallet — (protected) returns authenticated user's wallet.

POST /api/wallet/credit — (protected) credit wallet (body: amount).

POST /api/wallet/debit — (protected) debit wallet (body: amount).

POST /api/wallet/payout-details — (protected) save artisan payout/bank details for payouts. - Body (application/json): - name (string, required) — account holder name - account_number (string, required) - bank_code (string, required) — numeric or bank code per your country (e.g. 058 for GTBank NG) - bank_name (string, optional) - currency (string, optional, default: NGN) - Response (200): { success: true, data: <wallet> } where wallet.payoutDetails contains the saved fields. - Example (curl):

  ```bash

  curl -X POST 'http://localhost:5000/api/wallet/payout-details' \

  	-H 'Content-Type: application/json' \

  	-H 'Authorization: Bearer <TOKEN>' \

  	-d '{ "name": "Jane Artisan", "account_number": "0123456789", "bank_code": "058", "bank_name": "GTBank", "currency": "NGN" }'

  ```

- Notes:

    - The server persists these details on the authenticated user's `Wallet` (`payoutDetails`). These fields are used by the server to create a Paystack transfer recipient when the platform attempts an auto-payout.

    - When a payout is processed (on job completion), if a `wallet.paystackRecipientCode` is present the server will use it for Paystack transfers. If no recipient code exists but `wallet.payoutDetails` are available, the server will attempt to create a Paystack recipient (`/transferrecipient`) automatically, persist the returned `recipient_code` to `wallet.paystackRecipientCode` (and `Artisan.paystackRecipientCode`) and then perform the transfer.

    - Paystack configuration required: set `PAYSTACK_SECRET_KEY`. To enable automatic transfers set `PAYSTACK_AUTO_PAYOUT=true`.

    - Sensitive bank/account data is stored in your database; consider encrypting these fields at rest and do not expose full account numbers in public API responses.



Transactions

Overview: View transaction history with role-based access control. Transactions track payments between customers and artisans, including escrow holding, releases, and refunds.

GET /api/transactions — (protected) list transactions

PreHandler: verifyJWT (must be authenticated)
Headers: Authorization: Bearer <TOKEN>
Query params:
page (integer, default: 1) — pagination page
limit (integer, default: 20) — items per page
status (string, optional) — filter by status: 'pending', 'holding', 'released', 'paid', 'refunded'
bookingId (string, optional) — filter by specific booking
startDate (string, optional) — ISO date string, filter transactions after this date
endDate (string, optional) — ISO date string, filter transactions before this date
Role-based filtering:
admin — sees ALL transactions across the platform
artisan — sees only transactions where they are the payee (their earnings)
user/customer — sees only transactions where they are the payer (their payments)
Response (200):

{

	"success": true,

	"data": [

		{

			"_id": "tx123...",

			"amount": 5000,

			"companyFee": 500,

			"status": "holding",

			"bookingId": {

				"_id": "booking456...",

				"status": "confirmed",

				"serviceDate": "2026-01-20T00:00:00.000Z",

				"totalPrice": 5000

			},

			"payerId": {

				"_id": "user789...",

				"name": "John Doe",

				"email": "john@example.com",

				"phone": "+2348012345678",

				"role": "user"

			},

			"payeeId": {

				"_id": "artisan101...",

				"name": "Jane Smith",

				"email": "jane@example.com",

				"phone": "+2348087654321",

				"role": "artisan"

			},

			"paymentGatewayRef": "ref_xyz123",

			"createdAt": "2026-01-15T10:30:00.000Z",

			"releasedAt": null

		}

	],

	"meta": {

		"page": 1,

		"limit": 20,

		"total": 45,

		"pages": 3

	}

}

- Example (curl):

# Get all transactions (as admin)

curl 'http://localhost:5000/api/transactions' \

	-H 'Authorization: Bearer <ADMIN_TOKEN>'

# Get transactions with filters

curl 'http://localhost:5000/api/transactions?page=1&limit=10&status=holding&startDate=2026-01-01' \

---

**Get transactions summary (admin)**

- **Overview:** Returns aggregated totals for transactions grouped by status and a platform-level net availability figure. Use this from an admin dashboard to see how much money is currently held, pending, released to artisans, paid out, or refunded. The response also includes `netAvailable = total - refunded - pending` which represents funds not yet available on the platform (e.g., awaiting release or refund).

- **Endpoint:** `GET /api/transactions/admin/summary`

    - **PreHandler:** `verifyJWT`, `requireRole('admin')`

    - **Headers:** `Authorization: Bearer <ADMIN_TOKEN>`

- **Response (200):**

```json

{

  "success": true,

  "data": {

    "byStatus": {

      "holding": 12000.00,

      "pending": 3000.00,

      "released": 9000.00,

      "paid": 15000.00,

      "refunded": 500.00

    },

    "total": 39500.00,

    "netAvailable": 36000.00

  }

}

Notes:

byStatus values are sums of the amount field for transactions in each status.
total is the sum of all statuses (holding + pending + released + paid + refunded).
netAvailable is total - refunded - pending (funds that are effectively available on the platform).

Example (curl):

curl 'http://localhost:5000/api/transactions/admin/summary' \

-H 'Authorization: Bearer <ADMIN_TOKEN>'

-H 'Authorization: Bearer <TOKEN>'
Get transactions for specific booking
curl 'http://localhost:5000/api/transactions?bookingId=<booking_id>'
-H 'Authorization: Bearer '

- Errors: 401 unauthorized, 500 server errors

- `GET /api/transactions/:id` — (protected) get single transaction

- PreHandler: `verifyJWT` (must be authenticated)

- Headers: `Authorization: Bearer <TOKEN>`

- Params: `id` — transaction ObjectId

- **Access control:**

- Admins can view any transaction

- Regular users can only view transactions they're involved in (as payer or payee)

- Returns 403 Forbidden if user tries to access someone else's transaction

- Response (200): `{ success: true, data: <transaction with populated bookingId, payerId, payeeId> }`

- Errors: 401 unauthorized, 403 forbidden, 404 not found, 500 server errors

**Transaction Status Flow:**

- `pending` → Initial state after payment initiated

- `holding` → Funds held in escrow after payment confirmed

- `released` → Funds released to artisan after job completion

- `paid` → Final state after payout/transfer to artisan

- `refunded` → Payment refunded to customer

---

**Reviews**

- `GET /api/reviews` — list reviews (query `artisanId`, `page`, `limit`).

- `POST /api/reviews` — (protected) create review (body: `targetId`, `rating` required).

- `GET /api/reviews/:id` — view a review.

Details: create a rating/review for an artisan

- `POST /api/reviews` — submit a rating for an artisan (protected)

- PreHandler: `verifyJWT` (must be authenticated)

- Body (application/json):

- `targetId` (string, required) — the `User._id` of the artisan being rated

- `rating` (number, required) — 1 through 5

- `comment` (string, optional)

- `bookingId` (string, optional) — optional booking id to mark booking as reviewed

- Important: `customerId` is derived from the authenticated JWT on the server — do NOT rely on or send `customerId` in the request body. The server uses the token to determine who submitted the review.

- Duplicate reviews: The API enforces one review per customer per artisan. If the authenticated user has already reviewed the artisan, the server returns HTTP `409 Conflict` with `{ success: false, message: 'You have already reviewed this artisan' }`.

- Server behavior:

- Creates a `Review` document with `{ customerId, artisanId, rating, comment }` where `customerId` is the authenticated user id.

- If `bookingId` is provided, marks the booking as reviewed.

- Updates the artisan aggregate (`Artisan.rating` and `Artisan.reviewsCount`) using a running average.

- Example request (curl):

```bash

curl -X POST 'http://localhost:5000/api/reviews' \

-H 'Content-Type: application/json' \

-H 'Authorization: Bearer <TOKEN>' \

-d '{"targetId":"64a1e2f...","rating":5,"comment":"Fast and professional"}'

- Example PowerShell:

$body = @{ targetId='64a1e2f...'; rating=5; comment='Fast and professional' } | ConvertTo-Json

Invoke-RestMethod -Uri 'http://localhost:5000/api/reviews' -Method Post -Headers @{ Authorization = 'Bearer <TOKEN>' } -Body $body -ContentType 'application/json'

- Success response (201):

{ "success": true, "data": { "_id": "64a9...", "customerId": "...,", "artisanId": "64a1e2f...", "rating": 5, "comment": "Fast and professional", "createdAt": "2025-12-16T11:00:00.000Z" } }

- Errors:

- `400` — missing/invalid fields (e.g. rating out of range)

- `401` — not authenticated

- `409` — conflict — user has already submitted a review for this artisan

- `404` — referenced booking/target not found (rare)



Chat

GET /api/chat/:threadId — (protected) fetch a chat thread.
POST /api/chat/:threadId — (protected) send a message (body: { text }).



Locations

GET /api/locations/nigeria/states — returns list of Nigerian states.
GET /api/locations/nigeria/lgas?state=<stateName> — returns LGAs for given state (query param state required).

Flutter example (get states)

final res = await http.get(Uri.parse('http://localhost:5000/api/locations/nigeria/states'));

final states = jsonDecode(res.body)['data'];



Admin

POST /api/admin/create — (protected) create a new admin. Requires verifyJWT and requireRole('admin') preHandler. Body: name, email, password, optional permissions.
GET /api/admin/overview — (protected) admin dashboard overview.
GET /api/admin/users — (protected) list users (admin view).
PUT /api/admin/users/:id/role — change user role (protected).

Admin Configs

GET /api/admin/configs — (protected, admin only) list all configuration keys and metadata stored in the platform configs collection.

Headers: Authorization: Bearer <ADMIN_TOKEN>
Response (200): { success: true, data: [ { key, value, type, description, updatedBy, updatedAt }, ... ] }

GET /api/admin/configs/:key — (protected, admin only) read a single config value by key.

Path param: key — config key (e.g. COMPANY_FEE_PCT)
Response (200): { success: true, data: { key, value } } or 404 if not found.

PUT /api/admin/configs/:key — (protected, admin only) create or update a config key/value.

Headers: Authorization: Bearer <ADMIN_TOKEN>

Body (application/json): { "value": <any>, "type": "number"|"string"|"json", "description": "optional text" }

Behavior: upserts the value in the configs collection and updates an in-memory cache used by the server so changes take effect immediately for most code paths.

Special-case: COMPANY_FEE_PCT — validated as a numeric percent between 0 and 100 and stored with type: 'number'. Use this endpoint to change the platform fee without redeploying.

Example (set company fee to 10%):

curl -X PUT 'http://localhost:5000/api/admin/configs/COMPANY_FEE_PCT' \

-H 'Content-Type: application/json' \

-H 'Authorization: Bearer <ADMIN_TOKEN>' \

-d '{ "value": 10, "type": "number", "description": "Platform fee percent" }'

Notes:
On server startup the app will migrate an existing .env value for COMPANY_FEE_PCT into the database only if the DB key does not already exist — it will not overwrite an existing DB value.
At runtime the server reads configuration from the database first (getConfig('COMPANY_FEE_PCT')) and falls back to .env only when no DB value exists. PUT requests update the DB and refresh the in-memory cache so the change is effective immediately (cache TTL ~30s otherwise).

GET /api/admin/jobs — (protected, admin only) list jobs across all users. Query params:

page (number, default 1)

limit (number, default 50)

status (string) — filter by job status (open, filled, closed)

clientId (string) — filter jobs by specific user id

groupBy=user — return aggregation grouped by clientId with counts and last created date

Example: list first 50 jobs

curl -H 'Authorization: Bearer <ADMIN_TOKEN>' 'http://localhost:5000/api/admin/jobs?page=1&limit=50'

Example: aggregate job counts per user

curl -H 'Authorization: Bearer <ADMIN_TOKEN>' 'http://localhost:5000/api/admin/jobs?groupBy=user'

GET /api/admin/bookings — (protected, admin only) list all bookings with filters, quotes, and job details

PreHandler: verifyJWT, requireRole('admin')
Headers: Authorization: Bearer <TOKEN>
Query params:
page (number, default 1)
limit (number, default 50)
status (string) — filter by booking status (pending, accepted, in-progress, completed, cancelled)
customerId (string) — filter by specific customer user id
artisanId (string) — filter by specific artisan user id
sortBy (string, default 'createdAt') — field to sort by
includeDetails (string, default 'true') — include quotes and job information
Response (200):

{

"success": true,

"data": [

{

"_id": "64a1e2f...",

"customerId": {

"_id": "...",

"name": "John Doe",

"email": "john@example.com",

"phone": "+234...",

"profileImage": {...}

},

"artisanId": {

"_id": "...",

"name": "Jane Smith",

"email": "jane@example.com",

"phone": "+234...",

"profileImage": {...}

},

"service": "Plumbing repair",

"schedule": "2026-01-20T10:00:00.000Z",

"price": 5000,

"status": "completed",

"paymentStatus": "paid",

"acceptedQuote": {

"_id": "...",

"serviceCharge": 5000,

"items": [

{ "name": "Pipe replacement", "qty": 1, "cost": 3000 },

{ "name": "Labor", "qty": 1, "cost": 2000 }

],

"total": 5000,

"status": "accepted"

},

"quotes": [

{

"_id": "...",

"artisanId": {

"name": "Jane Smith",

"email": "jane@example.com",

"profileImage": {...}

},

"serviceCharge": 5000,

"items": [...],

"total": 5000,

"status": "accepted",

"createdAt": "2026-01-15T10:30:00.000Z"

},

{

"_id": "...",

"artisanId": {

"name": "Bob Builder",

"email": "bob@example.com",

"profileImage": {...}

},

"serviceCharge": 6000,

"items": [...],

"total": 6000,

"status": "rejected",

"createdAt": "2026-01-15T11:00:00.000Z"

}

],

"job": {

"_id": "...",

"title": "Need plumber urgently",

"description": "Leaking pipe in kitchen, need immediate attention",

"clientId": {

"name": "John Doe",

"email": "john@example.com",

"phone": "+234..."

},

"status": "filled",

"budget": { "min": 3000, "max": 7000 },

"category": "plumbing",

"createdAt": "2026-01-14T08:00:00.000Z"

},

"createdAt": "2026-01-15T10:30:00.000Z"

}

],

"pagination": {

"page": 1,

"limit": 50,

"total": 120,

"pages": 3

}

}

- **Response fields explained:**

- `acceptedQuote`: The quote that was accepted for this booking (populated)

- `quotes`: Array of all quotes submitted for this booking (includes artisan details)

- `job`: The job posting that led to this booking (null if booking was created directly)

- When `includeDetails=false`, only `acceptedQuote` is populated (quotes and job are excluded)

- **Example:**

# Get all bookings with full details (default)

curl -H 'Authorization: Bearer <ADMIN_TOKEN>' \

'http://localhost:5000/api/admin/bookings'

# Get bookings with basic info only (faster query)

curl -H 'Authorization: Bearer <ADMIN_TOKEN>' \

'http://localhost:5000/api/admin/bookings?includeDetails=false'

# Filter by status

curl -H 'Authorization: Bearer <ADMIN_TOKEN>' \

'http://localhost:5000/api/admin/bookings?status=completed&page=1&limit=20'

# Filter by customer and include all details

curl -H 'Authorization: Bearer <ADMIN_TOKEN>' \

'http://localhost:5000/api/admin/bookings?customerId=64a1d3c...'

GET /api/admin/quotes — (protected, admin only) list all quotes with type distinction and filters

PreHandler: verifyJWT, requireRole('admin')

Headers: Authorization: Bearer <TOKEN>

Query params:

page (number, default 1)
limit (number, default 50)
status (string) — filter by quote status (proposed, accepted, rejected)
type (string) — filter by quote type:
booking — quotes for direct hire bookings (artisan negotiating price)
job — quotes for job postings (artisan bidding on open jobs)
omit for all quotes
customerId (string) — filter by specific customer user id
artisanId (string) — filter by specific artisan user id
bookingId (string) — filter by specific booking id
jobId (string) — filter by specific job id
sortBy (string, default 'createdAt') — field to sort by

Response (200):

{

"success": true,

"data": [

{

"_id": "64a1e2f...",

"customerId": {

"_id": "...",

"name": "John Doe",

"email": "john@example.com",

"phone": "+234...",

"profileImage": {...}

},

"artisanId": {

"_id": "...",

"name": "Jane Smith",

"email": "jane@example.com",

"phone": "+234...",

"profileImage": {...}

},

"bookingId": {

"_id": "...",

"service": "Plumbing repair",

"schedule": "2026-01-20T10:00:00.000Z",

"status": "completed",

"price": 5000,

"paymentStatus": "paid"

},

"jobId": null,

"items": [

{ "name": "Pipe replacement", "qty": 1, "cost": 3000, "note": "PVC pipes" },

{ "name": "Labor", "qty": 1, "cost": 2000 }

],

"serviceCharge": 5000,

"total": 5000,

"status": "accepted",

"quoteType": "booking",

"context": "Direct hire - artisan negotiating price for existing booking",

"createdAt": "2026-01-15T10:30:00.000Z"

},

{

"_id": "64a2f3g...",

"customerId": {

"_id": "...",

"name": "Alice Brown",

"email": "alice@example.com",

"phone": "+234...",

"profileImage": {...}

},

"artisanId": {

"_id": "...",

"name": "Bob Builder",

"email": "bob@example.com",

"phone": "+234...",

"profileImage": {...}

},

"bookingId": null,

"jobId": {

"_id": "...",

"title": "Install new bathroom fixtures",

"description": "Need plumber for bathroom renovation",

"status": "open",

"budget": { "min": 10000, "max": 20000 },

"category": "plumbing",

"location": "Lagos"

},

"items": [

{ "name": "Fixture installation", "qty": 1, "cost": 8000 },

{ "name": "Materials", "qty": 1, "cost": 4000 }

],

"serviceCharge": 12000,

"total": 12000,

"status": "proposed",

"quoteType": "job",

"context": "Job posting - artisan bidding on open job",

"createdAt": "2026-01-16T08:00:00.000Z"

}

],

"pagination": {

"page": 1,

"limit": 50,

"total": 85,

"pages": 2

}

}

- **Understanding Quote Types:**

- **Booking Quotes** (`type=booking`):

- Flow: Customer hires artisan directly → artisan creates quote → customer accepts

- Has `bookingId`, no `jobId`

- Context: Price negotiation for existing booking

- Use case: Artisan revising initial estimate, customer requested detailed breakdown



- **Job Quotes** (`type=job`):

- Flow: Customer posts job → artisans bid with quotes → customer picks winner

- Has `jobId`, no `bookingId` (until accepted)

- Context: Competitive bidding on open job posting

- Use case: Multiple artisans competing for the same job

- **Examples:**

# Get all quotes (both types)

curl -H 'Authorization: Bearer <ADMIN_TOKEN>' \

'http://localhost:5000/api/admin/quotes'

# Get only booking quotes (direct hire negotiations)

curl -H 'Authorization: Bearer <ADMIN_TOKEN>' \

'http://localhost:5000/api/admin/quotes?type=booking'

# Get only job quotes (competitive bids)

curl -H 'Authorization: Bearer <ADMIN_TOKEN>' \

'http://localhost:5000/api/admin/quotes?type=job'

# Get pending job quotes (active bids)

curl -H 'Authorization: Bearer <ADMIN_TOKEN>' \

'http://localhost:5000/api/admin/quotes?type=job&status=proposed'

# Get quotes by specific artisan

curl -H 'Authorization: Bearer <ADMIN_TOKEN>' \

'http://localhost:5000/api/admin/quotes?artisanId=64a1d3c...'

# Get quotes for specific booking

curl -H 'Authorization: Bearer <ADMIN_TOKEN>' \

'http://localhost:5000/api/admin/quotes?bookingId=64a1e2f...'

# Get quotes for specific job

curl -H 'Authorization: Bearer <ADMIN_TOKEN>' \

'http://localhost:5000/api/admin/quotes?jobId=64a2f3g...'

GET /api/admin/chats — (protected, admin only) list all chats with filters

PreHandler: verifyJWT, requireRole('admin')

Headers: Authorization: Bearer <TOKEN>

Query params:

page (number, default 1)
limit (number, default 50)
bookingId (string) — filter by specific booking id
userId (string) — filter chats where user is a participant
includeMessages (string, default 'true') — include full message history or just message count
sortBy (string, default 'createdAt') — field to sort by

Response (200):

{

"success": true,

"data": [

{

"_id": "64a1e2f...",

"bookingId": {

"_id": "...",

"service": "Plumbing repair",

"schedule": "2026-01-20T10:00:00.000Z",

"status": "completed",

"price": 5000,

"customerId": "...",

"artisanId": "..."

},

"participants": [

{

"_id": "...",

"name": "John Doe",

"email": "john@example.com",

"phone": "+234...",

"role": "customer",

"profileImage": {...}

},

{

"_id": "...",

"name": "Jane Smith",

"email": "jane@example.com",

"phone": "+234...",

"role": "artisan",

"profileImage": {...}

}

],

"messages": [

{

"_id": "...",

"senderId": "...",

"senderName": "John Doe",

"senderRole": "customer",

"senderImageUrl": "https://...",

"message": "Can you come tomorrow at 10am?",

"timestamp": "2026-01-15T10:30:00.000Z",

"seen": true

},

{

"_id": "...",

"senderId": "...",

"senderName": "Jane Smith",

"senderRole": "artisan",

"senderImageUrl": "https://...",

"message": "Yes, I can make it at 10am",

"timestamp": "2026-01-15T10:35:00.000Z",

"seen": true

}

],

"isClosed": false,

"createdAt": "2026-01-15T10:00:00.000Z"

}

],

"pagination": {

"page": 1,

"limit": 50,

"total": 45,

"pages": 1

}

}

- **When `includeMessages=false`:**

{

"data": [{

"_id": "...",

"bookingId": {...},

"participants": [...],

"messageCount": 12,

"isClosed": false

}]

}

- **Examples:**

# Get all chats with full message history

curl -H 'Authorization: Bearer <ADMIN_TOKEN>' \

'http://localhost:5000/api/admin/chats'

# Get chats for specific booking

curl -H 'Authorization: Bearer <ADMIN_TOKEN>' \

'http://localhost:5000/api/admin/chats?bookingId=64a1e2f...'

# Get all chats where specific user participated

curl -H 'Authorization: Bearer <ADMIN_TOKEN>' \

'http://localhost:5000/api/admin/chats?userId=64a1d3c...'

# Get chat list with message counts only (faster)

curl -H 'Authorization: Bearer <ADMIN_TOKEN>' \

'http://localhost:5000/api/admin/chats?includeMessages=false'

GET /api/admin/chats/:id — (protected, admin only) get specific chat with full details
PreHandler: verifyJWT, requireRole('admin')
Headers: Authorization: Bearer <TOKEN>
Params: id — chat ObjectId
Response (200):

{

"success": true,

"data": {

"_id": "64a1e2f...",

"bookingId": {...},

"participants": [...],

"messages": [

{

"_id": "...",

"senderId": "...",

"senderName": "John Doe",

"senderRole": "customer",

"senderImageUrl": "https://...",

"message": "Can you come tomorrow at 10am?",

"timestamp": "2026-01-15T10:30:00.000Z",

"seen": true

}

],

"bookingDetails": {

"_id": "...",

"service": "Plumbing repair",

"customer": { "_id": "...", "name": "John Doe", "email": "...", "role": "customer" },

"artisan": { "_id": "...", "name": "Jane Smith", "email": "...", "role": "artisan" }

},

"isClosed": false,

"createdAt": "2026-01-15T10:00:00.000Z"

}

}

- **Example:**

curl -H 'Authorization: Bearer <ADMIN_TOKEN>' \

'http://localhost:5000/api/admin/chats/64a1e2f...'


15. Admin Wallet Monitoring
**Purpose:** Admins can view all user wallets, track financial activity, monitor balances, and investigate user financial history. This is essential for financial oversight, fraud detection, and user support.

- `GET /api/admin/wallets` — (admin) list all wallets with filters

- PreHandler: `verifyJWT`, `requireRole('admin')`

- Query params:

- `page` (number, default: 1)

- `limit` (number, default: 50)

- `sortBy` (string, default: 'balance') — `balance`, `totalEarned`, `totalSpent`, `totalJobs`, `lastUpdated`

- `sortOrder` (string, default: 'desc') — `asc` or `desc`

- `minBalance` (number) — filter wallets with balance >= this value

- `role` (string) — filter by user role: `artisan`, `customer`, `admin`

- Response:

```json

{

"success": true,

"data": [

{

"_id": "...",

"userId": {

"_id": "...",

"name": "Jane Smith",

"email": "jane@example.com",

"phone": "+234...",

"role": "artisan",

"profileImage": { "url": "https://..." },

"kycVerified": true,

"isVerified": true

},

"balance": 150000,

"totalEarned": 500000,

"totalSpent": 350000,

"totalJobs": 25,

"lastUpdated": "2026-01-15T10:00:00.000Z",

"payoutDetails": {

"name": "Jane Smith",

"account_number": "0123456789",

"bank_code": "058",

"bank_name": "GTBank",

"currency": "NGN"

},

"paystackRecipientCode": "RCP_...",

"paystackRecipientMeta": { ... }

}

],

"pagination": {

"page": 1,

"limit": 50,

"total": 150,

"pages": 3

}

}

```

- `GET /api/admin/wallets/:userId` — (admin) get specific wallet by user ID with full details

- PreHandler: `verifyJWT`, `requireRole('admin')`

- Params: `userId` (24-char hex user ID)

- Response includes:

- Complete wallet details

- User information (populated)

- Recent 10 transactions

- Computed statistics

```json

{

"success": true,

"data": {

"_id": "...",

"userId": {

"_id": "...",

"name": "Jane Smith",

"email": "jane@example.com",

"role": "artisan",

"kycVerified": true,

"isVerified": true,

"createdAt": "2025-06-01T00:00:00.000Z"

},

"balance": 150000,

"totalEarned": 500000,

"totalSpent": 350000,

"totalJobs": 25,

"lastUpdated": "2026-01-15T10:00:00.000Z",

"payoutDetails": {

"name": "Jane Smith",

"account_number": "0123456789",

"bank_code": "058",

"bank_name": "GTBank",

"currency": "NGN"

},

"paystackRecipientCode": "RCP_...",

"recentTransactions": [

{

"_id": "...",

"userId": "...",

"type": "credit",

"amount": 50000,

"description": "Payment for booking #123",

"status": "completed",

"createdAt": "2026-01-15T10:00:00.000Z"

}

],

"statistics": {

"totalEarnings": 500000,

"totalSpending": 350000,

"currentBalance": 150000,

"netActivity": 150000,

"completedJobs": 25,

"hasPayoutDetails": true,

"paystackRecipientCode": "RCP_..."

}

}

}

```

- **Example: List all wallets sorted by balance**

```bash

curl -H 'Authorization: Bearer <ADMIN_TOKEN>' \

'http://localhost:5000/api/admin/wallets?sortBy=balance&sortOrder=desc&limit=20'

```

- **Example: Find artisan wallets with high balances**

```bash

curl -H 'Authorization: Bearer <ADMIN_TOKEN>' \

	'http://localhost:5000/api/admin/wallets?role=artisan&minBalance=100000'

```

- **Example: Get specific user wallet details**

```bash

curl -H 'Authorization: Bearer <ADMIN_TOKEN>' \

	'http://localhost:5000/api/admin/wallets/64a1e2f3c4b5a6d7e8f90123'

```

**Use Cases:**

- **Financial Monitoring:** Track high-value wallets and unusual activity

- **Artisan Performance:** Sort by `totalEarned` to identify top performers

- **User Support:** View complete financial history when users report issues

- **Fraud Detection:** Monitor for suspicious balance/transaction patterns

- **Payout Management:** Check which users have configured payout details

- **Revenue Analysis:** Aggregate totals across all wallets for business insights


Admin Dashboard Quick Reference
Use this table to build your admin dashboard views for different monitoring scenarios:

Dashboard View
Endpoint
Query Filters
What You See
Use Case
All Bookings Overview
GET /api/admin/bookings
includeDetails=true
Bookings with customer/artisan, all quotes (accepted + rejected), associated jobs
Complete booking history with negotiations
All Quotes Overview
GET /api/admin/quotes
none
Every quote in the system with type indicator
Global marketplace activity
Direct Hire Monitoring
GET /api/admin/quotes
type=booking
Only booking quotes (price negotiations)
Track artisan quote revisions
Job Marketplace Activity
GET /api/admin/quotes
type=job
Only job bid quotes (competitive)
Monitor job posting competition
Active Job Bids
GET /api/admin/quotes
type=job&status=proposed
Pending job quotes awaiting acceptance
Current marketplace activity
Accepted Deals
GET /api/admin/quotes
status=accepted
All accepted quotes (both types)
Revenue tracking, conversion rate
Artisan Performance
GET /api/admin/quotes
artisanId=<id>
All quotes by specific artisan
Win rate, pricing strategy
Customer Activity
GET /api/admin/quotes
customerId=<id>
All quotes received by customer
Customer engagement patterns
Booking Investigation
GET /api/admin/quotes
bookingId=<id>
All quotes for specific booking
Dispute resolution, audit trail
Job Bid Analysis
GET /api/admin/quotes
jobId=<id>
All competing bids on one job
Compare artisan proposals
All Jobs Overview
GET /api/admin/jobs
none or status=open
All job postings with filters
Job marketplace health
Transaction Monitoring
GET /api/admin/transactions
filter by role
All transactions (role-aware)
Payment tracking, revenue
All Chats Overview
GET /api/admin/chats
includeMessages=false
All chats with message counts
Communication monitoring
Chat Investigation
GET /api/admin/chats
bookingId=<id>
Full chat history for booking
Dispute resolution, customer support
User Communication
GET /api/admin/chats
userId=<id>
All chats where user participated
User behavior tracking
Specific Chat Details
GET /api/admin/chats/:id
none
Complete chat with participants & messages
Detailed investigation
All Wallets Overview
GET /api/admin/wallets
sortBy=balance
All user wallets with balances & user details
Financial monitoring
Top Earners
GET /api/admin/wallets
sortBy=totalEarned&sortOrder=desc
Wallets sorted by total earnings
Revenue leaders tracking
Role-Specific Wallets
GET /api/admin/wallets
role=artisan or role=customer
Filter wallets by user role
Artisan vs customer analysis
High Balance Wallets
GET /api/admin/wallets
minBalance=10000
Wallets with minimum balance threshold
Identify high-value users
User Financial Details
GET /api/admin/wallets/:userId
none
Complete wallet + recent transactions + stats
User financial investigation


Dashboard Building Tips:

Combine GET /api/admin/bookings + GET /api/admin/quotes?type=booking for complete direct hire view
Use GET /api/admin/quotes?type=job + GET /api/admin/jobs for job marketplace dashboard
Filter by status=proposed to show "needs attention" items
Use sortBy=createdAt descending for recent activity feed
Pagination defaults to 50 items per page - adjust with limit parameter
Use includeMessages=false for faster chat list loading, then fetch individual chats for details
For customer support, use GET /api/admin/chats?bookingId=<id> to see full conversation context



Bootstrapping the first admin

Option A: Use POST /api/auth/register with body { name, email, password, adminCode }, where adminCode equals the server env var ADMIN_INVITE_CODE (or ADMIN_CODE). This creates an Admin document and returns a token.
Option B: If you already have an admin JWT, call POST /api/admin/create.



Quick debugging & tips

If requests return 401/403, confirm the token is present in Authorization header and not expired.
If you see 409 User already exists on registration, inspect the users and admins collections for that email — a check script was added at scripts/checkUser.js.
KYC field names and file fields are case-sensitive. Use the exact keys shown above.
Role names in routes may use client vs customer. Verify your User.role values (in src/models/User.js) and adjust requireRole(...) usage in routes if needed.



Server-side validation

Fastify uses JSON Schema (Ajv) for request validation. Routes often attach a schema option: e.g. fastify.post('/jobs', { schema: createSchema }, handler) where createSchema describes body, params, and/or querystring.

Example route-level schema (jobs create):

const createSchema = {

	body: {

		type: 'object',

		required: ['title'],

		properties: {

			title: { type: 'string' },

			description: { type: 'string' },

			trade: { type: 'array', items: { type: 'string' } },

			location: { type: 'string' },

			coordinates: { type: 'array', items: { type: 'number' } },

			budget: { type: 'number' },

			schedule: { type: 'string', format: 'date-time' },

		},

	},

};

fastify.post('/jobs', { preHandler: [verifyJWT, requireRole(['client','customer'])], schema: createSchema }, createJob);

Fastify will automatically validate incoming requests against the schema and return a 400 response when validation fails. The default error looks like { statusCode: 400, error: 'Bad Request', message: 'body must be object' } or more specific Ajv messages. You can customize validation error handling using a global error handler or by setting a custom validator/compiler.

Manual validation inside controllers (useful for multipart endpoints):

import Ajv from 'ajv';

const ajv = new Ajv();

const schema = { type: 'object', properties: { title: { type: 'string' } }, required: ['title'] };

const validate = ajv.compile(schema);

export async function submitKyc(request, reply) {

	// parse multipart fields into `request.body` using middleware

	const payload = request.body || {};

	if (!validate(payload)) {

		return reply.code(400).send({ message: 'Validation failed', errors: validate.errors });

	}

	// continue processing (uploads, DB save...)

}

Important: endpoints that accept multipart/form-data cannot use Fastify's JSON body schema (Fastify will reject multipart payloads as "body must be object"). For these endpoints:

Do not attach a body schema on the route. Instead parse parts with your multipart middleware and validate the assembled request.body inside the controller (use Ajv or Joi).
Example: POST /api/kyc/submit uses a preHandler that streams files to Cloudinary and sets request.body — then the controller runs Ajv against required text fields.

Tips for clear validation errors and stable clients:

Keep route schemas small and explicit. Use additionalProperties: false for stricter checks where appropriate.
Use format: 'date-time' for ISO timestamps; Ajv can be configured with format validators.
For nested objects (coordinates), allow either array or object in schema and normalize in controller.
Return a concise error payload for clients, e.g. { message: 'Validation failed', errors: [{ path: '/body/title', message: 'should be string' }] }.

Flutter client guidance:

Match the request body shape to the server schema exactly (field names and types).
Use client-side validation for UX (required fields, simple type checks) but always expect server-side validation errors and show them to the user.
When uploading multipart (KYC, attachments), submit text fields with the exact keys the server expects (case-sensitive) and then attach files.





Useful curl examples

Login

curl -X POST 'http://localhost:5000/api/auth/login' -H 'Content-Type: application/json' -d '{"email":"admin@example.com","password":"secret"}'

Create job (authenticated)

curl -X POST 'http://localhost:5000/api/jobs' -H 'Content-Type: application/json' -H 'Authorization: Bearer <TOKEN>' -d '{"title":"Install tile","description":"..."}'

KYC multipart (using curl)

curl -X POST 'http://localhost:5000/api/kyc/submit' -H 'Authorization: Bearer <TOKEN>' \

	-F 'businessName=Alice Services' \

	-F 'country=Nigeria' \

	-F 'state=Lagos' \

	-F 'lga=Ikeja' \

	-F 'IdType=national_id' \

	-F 'serviceCategory=plumbing' \

	-F 'yearsExperience=5' \

	-F 'profileImage=@/path/to/profile.jpg' \

	-F 'IdUploadFront=@/path/to/id-front.jpg' \

	-F 'IdUploadBack=@/path/to/id-back.jpg'



If you'd like, I can:

Add a small Flutter service class with methods for auth, KYC upload, create job, upload attachment, and apply to job.
Patch jobRoutes.js to require customer instead of client (if your users use customer).
Restrict GET /api/users and GET /api/users/:id to admin-only if you prefer stricter privacy by default.

Tell me which follow-up you'd like and I will implement it.

