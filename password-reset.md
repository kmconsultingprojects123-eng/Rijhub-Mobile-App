Client (mobile app) integration notes
1. Request reset: POST /api/auth/forgot-password with user's email.
2. The user receives the email. If the app is installed and the deep-link is opened, the app receives a URI like:
   - myapp://reset-password?token=abc123&email=user%40example.com
3. Extract `token` (and `email` if present) and show a Reset Password screen pre-filled as needed.
4. Submit new password to POST /api/auth/reset-password with `resetToken` and `newPassword`.
5. On success the server returns a JWT — sign the user in and navigate appropriately.

Server implementation pointers
- Email template and deep-link handling: `src/utils/notifier.js` (function `sendPasswordResetEmail`).
- Token generation and reset endpoints: `src/controllers/authController.js` — look for `forgot-password` and `reset-password` handlers.
- Expiry: the email warns the link expires; check authController or token storage code for configured expiry (typically 1 hour).

Testing
- CLI / curl example to request reset:
  curl -X POST -H "Content-Type: application/json" -d '{"email":"user@example.com"}' http://localhost:5000/api/auth/forgot-password
- Simulate deep-link handling in dev by constructing a URL with `token` and passing it to your app's deep-link handler.

Security notes
- The server returns a non‑revealing response to the forgot-password request to avoid leaking account existence.
- Ensure `MOBILE_RESET_URL` is a safe, intended scheme for your app and that the client validates tokens server-side before changing passwords.

Where to change the email content
- `src/utils/notifier.js` contains the HTML/text used in the password reset email.

Support
- If email delivery fails, verify SMTP envs in your `.env` and check server logs for `sendMail failed` entries.
