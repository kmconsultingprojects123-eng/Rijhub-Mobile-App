# Paystack Helpers

Overview
- Utility endpoints and helpers used to integrate with Paystack for bank lists, account resolution and payment verification.

Key endpoints
- `GET /api/paystack/banks?currency=NGN` — returns supported banks for a currency.
- `POST /api/paystack/resolve` — resolve an account number to an account holder (body: `account_number`, `bank_code`, `currency`).
- Webhook handling — server verifies incoming webhook signatures using `PAYSTACK_WEBHOOK_SECRET` and processes events such as `charge.success`.

Environment
- `PAYSTACK_SECRET_KEY` — secret key used for API calls.
- `PAYSTACK_BASE_URL` — optional custom base URL.
- `PAYSTACK_WEBHOOK_SECRET` — used to validate webhook signatures.

Notes
- Use the `GET /api/paystack/banks` endpoint to populate payee bank pickers on clients.
- All calls that trigger payments or sensitive operations must be performed server-side.

Example (resolve account)
```bash
curl -X POST https://your-api.example.com/api/paystack/resolve \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"account_number":"0123456789","bank_code":"058","currency":"NGN"}'
```
