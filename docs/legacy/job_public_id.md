# Job Public ID (short identifier)

Overview

Jobs now include a short, human-friendly `publicId` alongside the MongoDB `_id`. This is suitable for sharing in URLs or short references.

Behavior
- `publicId` is generated server-side on creation and is unique.
- Controllers accept either a MongoDB ObjectId or the `publicId` — use helper `Job.findByIdOrPublic()` when querying.

Backfill
- New and updated jobs will have `publicId`; existing jobs can be backfilled using a small script (see docs/job_publicid_backfill.md).

Usage example
- Clients may link to `/jobs/{publicId}` instead of exposing the raw ObjectId.
