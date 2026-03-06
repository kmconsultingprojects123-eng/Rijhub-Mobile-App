# Account Deletion

Overview

Two deletion flows are supported:

- Self-deletion: `DELETE /api/users/me` — authenticated users may request deletion of their own account.
- Admin deletion: `DELETE /api/admin/users/:id` — admins may delete any user account.

Behavior
- Deletion removes or anonymizes personal data and revokes active sessions and device tokens. The implementation may also cascade or mark related resources (jobs, bookings, chats) depending on business rules.

Notes
- This is a destructive operation. Clients should show a confirmation step and explain consequences.
