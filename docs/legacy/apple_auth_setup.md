# Apple Sign-In Backend Implementation Guide (Node.js)

This guide is for the backend developer to implement Apple Sign-In authentication, similar to the existing Google OAuth endpoint.

---

## What You'll Receive from Mobile Dev

| Item | Description | Example |
|------|-------------|---------|
| **Team ID** | Apple Developer Team ID (10 chars) | `YUDLHJDZDC` |
| **Key ID** | ID of the Sign in with Apple key | `4GPW9GAZQR` |
| **Private Key** | `.p8` file contents | `-----BEGIN PRIVATE KEY-----\nMIGT...` |
| **Bundle ID** | iOS app bundle identifier | `com.rijhub.app` |

---

## Required NPM Packages

```bash
npm install jose jsonwebtoken
```

- `jose` - For fetching and using Apple's public keys (recommended)
- `jsonwebtoken` - Alternative if you prefer manual verification

---

## Environment Variables

Add these to your `.env`:

```env
APPLE_TEAM_ID=YUDLHJDZDC
APPLE_KEY_ID=4GPW9GAZQR
APPLE_BUNDLE_ID=com.rijhub.app
APPLE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIGT...contents of .p8 file...\n-----END PRIVATE KEY-----"
```

> **Note**: For the private key, either paste the entire `.p8` contents with `\n` for newlines, or read from a file path.

---

## Database Schema Update

Add this column to your users table:

```sql
-- For new users
ALTER TABLE users ADD COLUMN apple_user_id VARCHAR(255) UNIQUE;

-- Create index for faster lookups
CREATE INDEX idx_users_apple_user_id ON users(apple_user_id);
```

---

## Complete Endpoint Implementation

### File: `routes/auth.js` or `controllers/authController.js`

```javascript
const { createRemoteJWKSet, jwtVerify } = require('jose');
const crypto = require('crypto');

// Cache Apple's JWKS to avoid fetching on every request
const APPLE_JWKS = createRemoteJWKSet(
  new URL('https://appleid.apple.com/auth/keys')
);

/**
 * POST /api/auth/oauth/apple
 * 
 * Request body:
 * {
 *   identityToken: string,    // JWT from Apple (required)
 *   authorizationCode: string, // Auth code from Apple (optional, for server-to-server)
 *   nonce: string,            // Raw nonce used by the app (required for verification)
 *   name: string,             // User's name (only on first sign-in)
 *   email: string,            // User's email (only on first sign-in)
 *   role: string              // Optional: 'customer' or 'artisan'
 * }
 */
async function appleOAuthHandler(req, res) {
  try {
    const { identityToken, nonce, name, email, role } = req.body;

    // 1. Validate required fields
    if (!identityToken) {
      return res.status(400).json({ 
        message: 'Missing identityToken' 
      });
    }

    if (!nonce) {
      return res.status(400).json({ 
        message: 'Missing nonce for verification' 
      });
    }

    // 2. Verify the identity token
    let payload;
    try {
      const result = await jwtVerify(identityToken, APPLE_JWKS, {
        issuer: 'https://appleid.apple.com',
        audience: process.env.APPLE_BUNDLE_ID, // 'com.rijhub.app'
      });
      payload = result.payload;
    } catch (verifyError) {
      console.error('Apple token verification failed:', verifyError.message);
      return res.status(401).json({ 
        message: 'Invalid Apple identity token',
        error: verifyError.message 
      });
    }

    // 3. Verify nonce matches (prevents replay attacks)
    const expectedHashedNonce = crypto
      .createHash('sha256')
      .update(nonce)
      .digest('hex');

    if (payload.nonce !== expectedHashedNonce) {
      console.error('Nonce mismatch:', { 
        expected: expectedHashedNonce, 
        received: payload.nonce 
      });
      return res.status(401).json({ 
        message: 'Nonce verification failed' 
      });
    }

    // 4. Extract user info from token
    const appleUserId = payload.sub; // Unique, stable user ID from Apple
    const tokenEmail = payload.email;
    const emailVerified = payload.email_verified === 'true' || payload.email_verified === true;

    // 5. Find or create user
    // Use email from request body if provided (first sign-in only)
    // Fall back to email from token
    const userEmail = email || tokenEmail;
    const userName = name || null;

    let user = await User.findOne({ 
      where: { apple_user_id: appleUserId } 
    });

    if (!user && userEmail) {
      // Check if user exists with this email (might have registered differently)
      user = await User.findOne({ 
        where: { email: userEmail } 
      });
      
      if (user) {
        // Link existing account to Apple
        user.apple_user_id = appleUserId;
        await user.save();
      }
    }

    if (!user) {
      // Create new user
      if (!userEmail) {
        return res.status(400).json({
          message: 'Email required for new user registration. This may be a subsequent sign-in - user not found.'
        });
      }

      user = await User.create({
        email: userEmail,
        name: userName || userEmail.split('@')[0], // Fallback name
        apple_user_id: appleUserId,
        email_verified: emailVerified,
        role: role || 'customer',
        // No password for OAuth users
      });
    }

    // 6. Generate your app's JWT token
    const token = generateJWT(user); // Your existing JWT generation function
    const refreshToken = generateRefreshToken(user); // If you use refresh tokens

    // 7. Return response (same structure as Google OAuth)
    return res.status(200).json({
      message: 'Apple sign-in successful',
      token,
      refreshToken,
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        role: user.role,
      }
    });

  } catch (error) {
    console.error('Apple OAuth error:', error);
    return res.status(500).json({ 
      message: 'Internal server error during Apple sign-in',
      error: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
}

module.exports = { appleOAuthHandler };
```

### Route Registration

```javascript
// routes/auth.js
const express = require('express');
const router = express.Router();
const { appleOAuthHandler } = require('../controllers/authController');

// Existing routes
router.post('/oauth/google', googleOAuthHandler);

// Add Apple OAuth route
router.post('/oauth/apple', appleOAuthHandler);

module.exports = router;
```

---

## Token Payload Reference

The decoded `identityToken` from Apple contains:

```json
{
  "iss": "https://appleid.apple.com",
  "aud": "com.rijhub.app",
  "exp": 1699999999,
  "iat": 1699996399,
  "sub": "001234.abc123def456.7890",  // Unique Apple User ID
  "nonce": "hashed_nonce_value",
  "c_hash": "abc123",
  "email": "user@example.com",         // May be privaterelay email
  "email_verified": "true",
  "auth_time": 1699996399,
  "nonce_supported": true
}
```

### Important Notes on User Data

| Field | Behavior |
|-------|----------|
| `sub` | **Always present**. Unique user identifier. Use this as primary key. |
| `email` | May be real email or Apple's private relay (e.g., `abc123@privaterelay.appleid.com`) |
| `name` | **Only sent on FIRST sign-in**. Must be captured from request body and stored immediately. |

---

## Error Handling Reference

| Error | Cause | Response |
|-------|-------|----------|
| `JWTExpired` | Token expired | 401 - Ask user to re-authenticate |
| `JWSSignatureVerificationFailed` | Invalid/tampered token | 401 - Reject |
| `JWTClaimValidationFailed` | Wrong audience/issuer | 401 - Check APPLE_BUNDLE_ID |
| Nonce mismatch | Replay attack or sync issue | 401 - Reject |

---

## Testing the Endpoint

### Using curl (with a test token from the app):

```bash
curl -X POST https://rijhub.com/api/auth/oauth/apple \
  -H "Content-Type: application/json" \
  -d '{
    "identityToken": "eyJraWQiOi...",
    "nonce": "abc123rawnoncevalue",
    "name": "John Doe",
    "email": "john@example.com",
    "role": "customer"
  }'
```

### Expected Success Response:

```json
{
  "message": "Apple sign-in successful",
  "token": "eyJhbGciOiJIUzI1NiIs...",
  "refreshToken": "...",
  "user": {
    "id": "uuid-here",
    "email": "john@example.com",
    "name": "John Doe",
    "role": "customer"
  }
}
```

---

## Comparison: Google vs Apple OAuth

| Aspect | Google | Apple |
|--------|--------|-------|
| Token field | `idToken` | `identityToken` |
| User ID field | `sub` in token | `sub` in token |
| Verification URL | `https://oauth2.googleapis.com/tokeninfo` | `https://appleid.apple.com/auth/keys` |
| Name availability | Always in token | Only first sign-in (request body) |
| Email | Always in token | In token, may be private relay |
| Nonce required | No (optional) | Yes (for mobile apps) |

---

## Security Checklist

- [ ] Store `.p8` private key securely (env var or secrets manager)
- [ ] Verify nonce to prevent replay attacks
- [ ] Validate `iss` is exactly `https://appleid.apple.com`
- [ ] Validate `aud` matches your Bundle ID
- [ ] Check token expiration (`exp`)
- [ ] Store `apple_user_id` to identify returning users
- [ ] Capture name/email on first sign-in (not available later)

---

## Quick Summary

1. Add `apple_user_id` column to users table
2. Create `POST /api/auth/oauth/apple` endpoint
3. Use `jose` library to verify token with Apple's public keys
4. Verify nonce hash matches
5. Find or create user using `sub` as unique identifier
6. Return JWT same as Google OAuth flow
