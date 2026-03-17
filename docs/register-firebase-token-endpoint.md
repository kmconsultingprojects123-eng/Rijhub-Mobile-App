# POST `/api/register-user-with-firebase-token`

Registers a new user after Firebase Phone OTP verification. The mobile app verifies the user's phone number via Firebase, then sends the resulting ID token to this endpoint to complete registration on the Rijhub backend.

---

## Prerequisites

Since the backend already uses **Firebase Admin SDK** for push notifications, no additional Firebase setup is required. The same Admin SDK instance is used to verify ID tokens.

---

## Request

**Method:** `POST`
**URL:** `/api/register-user-with-firebase-token`
**Content-Type:** `application/json`

### Headers

| Header | Value |
|--------|-------|
| `Content-Type` | `application/json` |
| `Accept` | `application/json` |

### Body

```json
{
  "idToken":  "<Firebase ID Token — signed JWT from firebase_auth>",
  "name":     "Adedayo Niyi",
  "email":    "dayoniyi88@gmail.com",
  "password": "Test1234!",
  "phone":    "2349060690604",
  "role":     "customer"
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `idToken` | string | ✅ | Firebase ID token obtained after OTP verification — **must be verified server-side** |
| `name` | string | ✅ | User's full name |
| `email` | string | ✅ | User's email address |
| `password` | string | ✅ | Plain text — hash with bcrypt before storing |
| `phone` | string | ✅ | Phone without `+` prefix (e.g. `2349060690604`) — but always use the phone from the verified token, not this field, as the source of truth |
| `role` | string | ✅ | `"customer"` or `"artisan"` |

---

## Server-Side Implementation

### 1. Verify the Firebase ID Token

This is the only Firebase-specific step. Use the existing Admin SDK instance:

```javascript
const admin = require('firebase-admin'); // already initialized for push notifications

const decodedToken = await admin.auth().verifyIdToken(idToken);
// decodedToken.uid            → Firebase UID (e.g. "qywbm7195kVU3oYhUMcEY3mKUOX2")
// decodedToken.phone_number   → Verified phone (e.g. "+2349060690604")
```

> ⚠️ **Important:** Always use `decodedToken.phone_number` as the stored phone number — not the `phone` field from the request body. The token phone is cryptographically verified by Firebase; the body field is not.

### 2. Check for Existing User

```javascript
const existing = await User.findOne({
  $or: [{ email }, { phone: decodedToken.phone_number }]
});
if (existing) {
  return res.status(409).json({ message: 'User already exists' });
}
```

### 3. Create the User

```javascript
const hashedPassword = await bcrypt.hash(password, 10);

const user = await User.create({
  name,
  email: email.trim().toLowerCase(),
  password: hashedPassword,
  phone: decodedToken.phone_number,   // from verified token
  role,
  firebaseUid: decodedToken.uid,
  phoneVerified: true,
});
```

### 4. Issue a JWT and Respond

```javascript
const token = jwt.sign(
  { id: user._id, role: user.role },
  process.env.JWT_SECRET,
  { expiresIn: '7d' }
);

return res.status(201).json({
  token: token,
  user: {
    _id: user._id,
    name: user.name,
    email: user.email,
    phone: user.phone,
    role: user.role,
    firebaseUid: user.firebaseUid,
    phoneVerified: true,
    createdAt: user.createdAt,
  }
});
```

---

## Response Shape (201 Created)

```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "_id": "64abc123def456...",
    "name": "Adedayo Niyi",
    "email": "dayoniyi88@gmail.com",
    "phone": "+2349060690604",
    "role": "customer",
    "firebaseUid": "qywbm7195kVU3oYhUMcEY3mKUOX2",
    "phoneVerified": true,
    "createdAt": "2025-01-01T00:00:00.000Z"
  }
}
```

### Why this shape matters — how the Flutter app parses it

The app reads the response in this priority order:

| What the app needs | Where it looks (in order) |
|--------------------|--------------------------|
| Auth token | `body.token` → `body.data.token` |
| Role | `body.user.role` → `body.data.role` → `body.role` |
| User profile | `body.user` (must contain `_id` or `id`) → `body.data` |

The recommended shape above (`token` at the root, `user` object with `_id`) satisfies **all three** in the first lookup — no ambiguity.

After a successful response:
1. The token is saved to secure storage
2. The role is stored and used for navigation
3. The user profile is cached locally
4. The app shows a welcome bottom sheet, then navigates to `HomePageWidget` (customer) or `ArtisanDashboardPageWidget` (artisan)

---

## Error Responses

| Status | When | Body |
|--------|------|------|
| `400` | Missing required fields | `{ "message": "..." }` |
| `401` | Invalid or expired Firebase ID token | `{ "message": "Invalid or expired Firebase token" }` |
| `409` | Email or phone already registered | `{ "message": "User already exists" }` |
| `500` | Internal server error | `{ "message": "..." }` |

---

## Full Example (NestJS / Express)

```javascript
router.post('/api/register-user-with-firebase-token', async (req, res) => {
  const { idToken, name, email, password, phone, role } = req.body;

  if (!idToken || !name || !email || !password || !role) {
    return res.status(400).json({ message: 'All fields are required' });
  }

  // 1. Verify Firebase token
  let decodedToken;
  try {
    decodedToken = await admin.auth().verifyIdToken(idToken);
  } catch (err) {
    return res.status(401).json({ message: 'Invalid or expired Firebase token' });
  }

  const verifiedPhone = decodedToken.phone_number;

  // 2. Check for duplicate
  const existing = await User.findOne({
    $or: [{ email: email.trim().toLowerCase() }, { phone: verifiedPhone }]
  });
  if (existing) {
    return res.status(409).json({ message: 'User already exists' });
  }

  // 3. Create user
  const user = await User.create({
    name,
    email: email.trim().toLowerCase(),
    password: await bcrypt.hash(password, 10),
    phone: verifiedPhone,
    role,
    firebaseUid: decodedToken.uid,
    phoneVerified: true,
  });

  // 4. Return token + user
  const token = jwt.sign(
    { id: user._id, role: user.role },
    process.env.JWT_SECRET,
    { expiresIn: '7d' }
  );

  return res.status(201).json({
    token,
    user: {
      _id: user._id,
      name: user.name,
      email: user.email,
      phone: user.phone,
      role: user.role,
      firebaseUid: user.firebaseUid,
      phoneVerified: true,
      createdAt: user.createdAt,
    }
  });
});
```
