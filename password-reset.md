Client (mobile app) integration notes
1. Request reset: POST /api/auth/forgot-password with user's email.
2. The user receives the email containing the reset token (plaintext). The token expires in 1 hour.
3. In the app, prompt the user to enter/paste the token from the email and the new password.
4. Submit new password to `POST /api/auth/reset-password` with `resetToken` and `newPassword`.
5. On success the server returns a JWT — sign the user in and navigate appropriately.

Server implementation pointers
- Email template: `src/utils/notifier.js` (function `sendPasswordResetEmail`).
- Token generation and reset endpoints: `src/controllers/authController.js` — look for `forgot-password` and `reset-password` handlers.
- Expiry: the email warns the link expires; check authController or token storage code for configured expiry (typically 1 hour).

Testing
- CLI / curl example to request reset:
  curl -X POST -H "Content-Type: application/json" -d '{"email":"user@example.com"}' http://localhost:5000/api/auth/forgot-password
-- The email contains only the token by default; optionally include a web link via `MOBILE_RESET_URL_WEB`.

Security notes
- The server returns a non‑revealing response to the forgot-password request to avoid leaking account existence.
-- If you include a web reset link, ensure `MOBILE_RESET_URL_WEB` points to your legitimate web reset page and the client validates tokens server-side before changing passwords.

Where to change the email content
- `src/utils/notifier.js` contains the HTML/text used in the password reset email.

Support
- If email delivery fails, verify SMTP envs in your `.env` and check server logs for `sendMail failed` entries.
