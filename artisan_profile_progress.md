# Artisan Profile Progress

Overview

Artisan objects now expose a `profileProgress` score representing completion of critical verification steps.

Rules (base progress)
- KYC completed: 40%
- Profile fields (name, phone, bio, avatar, categories): 40%
- Both KYC and profile complete: 100% (verified)

Implementation
- A Mongoose virtual `profileBaseProgress` is used to compute the base score; controllers attach `profileProgress` to responses for individual artisans and lists.

Usage
- Clients can display progress bars and prompt artisans to complete missing fields or KYC steps.

API Endpoints
- Get artisan by linked user id: `GET /api/artisans/user/:userId` (use this when you have the user's id)
