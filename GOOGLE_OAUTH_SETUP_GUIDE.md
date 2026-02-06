# Google OAuth Setup Guide for Backend

This guide helps set up Google OAuth credentials in the **company's Google Cloud project** (project ID: `174728322654`) for the RijHub platform.

---

## Quick Summary

The mobile app needs credentials from the **same Google Cloud project** as the backend. Currently:
- ✅ Android client created in company project
- ❌ Backend using credentials from a different project

---

## Step 1: Create Web Client ID (for Backend)

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Select the **company project** (same one where Android client was created)
3. Navigate to **APIs & Services** → **Credentials**
4. Click **+ CREATE CREDENTIALS** → **OAuth client ID**
5. Select **Web application**
6. Fill in:
   - **Name**: `RijHub Backend`
   - **Authorized JavaScript origins**: (leave blank or add your domains)
   - **Authorized redirect URIs**: (leave blank for ID token flow)
7. Click **Create**
8. Copy the **Client ID** and **Client Secret**

---

## Step 2: Update Backend Environment

Update the server's `.env` file with the new credentials:

```env
GOOGLE_CLIENT_ID=<new-web-client-id>.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=<new-client-secret>
```

**Important**: The `GOOGLE_CLIENT_ID` is used to verify ID tokens from mobile apps. It must match the `serverClientId` used in the mobile app.

---

## Step 3: Update Mobile App (I will do this)

Once you provide the new **Web Client ID**, I will update `api_config.dart` with:
```dart
const _defaultGoogleWebClientId = '<new-web-client-id>.apps.googleusercontent.com';
```

---

## Step 4: Verify OAuth Consent Screen

In the same project, ensure the OAuth consent screen is configured:

1. Go to **APIs & Services** → **OAuth consent screen**
2. Set app name, user support email, developer contact
3. Add scopes: `email`, `profile`, `openid`
4. If in "Testing" mode, add test users' emails

---

## Existing Android Client (Already Created)

| Field | Value |
|-------|-------|
| Package name | `com.rijhub.app` |
| SHA-1 (Debug) | `86:CC:F2:A9:95:65:25:F6:E7:69:E8:7D:D6:03:4C:F2:4E:A7:B6:A9` |

For production release, a second Android client with the **release keystore SHA-1** will be needed.

---

## How It Works

```
┌─────────────┐     ID Token      ┌─────────────┐
│  Mobile App │ ─────────────────▶│   Backend   │
│             │                   │             │
│ Uses:       │                   │ Verifies:   │
│ - Android   │                   │ - Web       │
│   Client    │                   │   Client ID │
│ - Web       │                   │             │
│   Client ID │                   └─────────────┘
│   (server)  │                   
└─────────────┘                   
```

Both clients must be in the **same Google Cloud project**.

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `Invalid Google token` | Mismatched Client IDs | Ensure backend uses Web Client ID from same project |
| `canceled` on mobile | Missing/wrong Android client | Verify package name and SHA-1 |
| No email in payload | Missing scopes | Add `email` scope to OAuth consent screen |

---

## Contact

After creating the Web Client ID, share:
1. **Web Client ID**: `xxxxx.apps.googleusercontent.com`
2. Confirmation that `.env` was updated

I will then update the mobile app to complete the integration.
