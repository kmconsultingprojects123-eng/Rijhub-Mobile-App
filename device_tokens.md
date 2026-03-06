# Device Token Endpoints

These endpoints manage device registration used for push notifications (FCM).

Endpoints
- `POST /api/device/register` — register a device token. Body: `{ token, platform, meta? }`. Protected (JWT).
- `POST /api/device/unregister` — remove a device token. Body: `{ token }`. Protected (JWT).
- `GET /api/device` — list registered device tokens for the authenticated user. Protected (JWT).

Behavior
- Tokens are stored in `DeviceToken` documents and may be audited in `DeviceTokenAudit`.
- Registering the same token again is idempotent.

Example
```bash
curl -X POST https://your-api.example.com/api/device/register \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"token":"fcm_token_here","platform":"android"}'
```
