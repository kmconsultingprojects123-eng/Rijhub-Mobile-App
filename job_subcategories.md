# Job Subcategories

Overview

Each `JobCategory` may have zero or more `JobSubCategory` entries. Subcategories allow finer-grained classification of jobs.

Model
- `name` (string)
- `slug` (string)
- `description` (string)
- `categoryId` (reference to `JobCategory`)
- `isActive`, `order`, `createdAt`

Endpoints
- `GET /api/job-subcategories` — list subcategories (public)
- `GET /api/job-subcategories/:id` — get a single subcategory (public)
- `POST /api/job-subcategories` — create (admin)
- `PUT /api/job-subcategories/:id` — update (admin)
- `DELETE /api/job-subcategories/:id` — delete (admin)

Notes
- When creating or updating a job, you may optionally include a `subCategoryId` to link a job to a subcategory (not enforced automatically).
