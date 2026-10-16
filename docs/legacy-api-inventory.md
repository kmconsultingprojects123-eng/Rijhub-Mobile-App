# Old backend API: what the app used

The previous team's backend at rijhub.com is no longer available. This is an inventory of every call the old app made to it, built from the code (not from the old docs), so the new backend can be designed knowing what the app actually needed. The redesigned app does not call any of these; it talks to repository interfaces in `lib/data/repositories/`.

Source: an automated sweep of `lib/` with a completeness check (October 2026). File references point at the old code, which still sits under `lib/pages`, `lib/services` and friends.

## Summary

- **120 distinct endpoints** (method + path), 51 of them on the sign-up, sign-in or home path.
- **19 Socket.IO events** for chat, notifications and presence.
- Roughly half the calls were made straight from page widgets rather than a service layer, and many operations tried several fallback paths for the same thing. The new API should give each operation one path.
- Auth used JWT bearer tokens, issued by POST /api/auth/login, /api/auth/verify-otp, /api/auth/oauth/google, /api/auth/oauth/apple, /api/auth/reset-password and /api/auth/refresh. AuthService._persistTokenAndRole (auth_service.dart:137-196) reads `token` or `data.token`, optional `refreshToken`/`data.refreshTo…

| Domain | Endpoints |
|---|---|
| auth | 14 |
| users | 7 |
| artisans | 12 |
| categories | 2 |
| jobs | 7 |
| quotes | 8 |
| bookings | 12 |
| payments | 6 |
| wallet | 6 |
| kyc | 6 |
| reviews | 2 |
| notifications | 11 |
| chat | 3 |
| special-requests | 8 |
| announcements | 7 |
| uploads | 5 |
| other | 4 |

## Auth

| Method | Path | Purpose | Request fields | Called from |
|---|---|---|---|---|
| POST | `/api/auth/check-email` | Check whether an email is registered, called only after a failed login to suggest sign-up. Not in any old doc; the code comment (auth_service.dart:550-557) adm… | email | lib/services/auth_service.dart:558 AuthService.checkEmailExists |
| POST | `/api/auth/forgot-password` | Request a password-reset token by email. | email | lib/services/auth_service.dart:467 AuthService.forgotPasswordImmediate |
| POST | `/api/auth/guest` | Create a guest session. Defined but has NO callers (the Continue-as-guest button was commented out). | (empty JSON body) | lib/services/auth_service.dart:363 AuthService.guest |
| POST | `/api/auth/login` | Email/password login, returns a JWT. A failed login may trigger check-email. | email (trimmed, lowercased), password | lib/services/auth_service.dart:301 AuthService.login |
| POST | `/api/auth/oauth/apple` | Exchange an Apple identityToken plus the raw nonce for an app JWT (mobile identity-token flow). | identityToken, nonce (raw), name? (first sign-in only), email?, role?, fcmToken? | lib/services/auth_service.dart:931 AuthService.signInWithApple |
| POST | `/api/auth/oauth/google` | Exchange a Google idToken for an app JWT; creates or links the user. | idToken, role? (sign-up screen), fcmToken? (cached FCM token), platform? ('ios'\\|'android') | lib/services/auth_service.dart:777 AuthService.signInWithGoogle |
| GET | `/api/auth/profile` | Profile fallback #4 in UserService.getProfile, reached only if the earlier candidates return non-2xx and non-401/403. Undocumented speculative probe. | Authorization header | lib/services/user_service.dart:24 UserService.getProfile candidate #4 |
| POST | `/api/auth/refresh` | Refresh an expired JWT. Called only at cold start and on resume, and only when the JWT exp has passed; on failure the app logs out. Not in any old doc (the old… | refreshToken | lib/services/auth_service.dart:1113 AuthService.tryRefreshToken |
| POST | `/api/auth/register` | Start email/password sign-up. The backend stores a pending user and sends an OTP (SMS via Sendchamp, or email). No token is issued until verify-otp, and the ca… | name, email (trimmed, lowercased), password, phone?, role? ('artisan'\\|'customer') | lib/services/auth_service.dart:203 AuthService.register |
| POST | `/api/auth/resend-otp` | Resend the registration OTP. 429 means throttled (about 60s window). | email, phone? | lib/services/auth_service.dart:1232 AuthService.resendOtp |
| POST | `/api/auth/reset-password` | Set a new password using the reset token; the backend returns a JWT that signs the user in. Reached from the reset screen or the rijhub:// deep link (main.dart… | resetToken, newPassword | lib/services/auth_service.dart:508 AuthService.resetPassword |
| GET | `/api/auth/verify` | Validate the bearer token. Used (a) as profile fallback #2 in UserService.getProfile and (b) by the cold-start health check when a token exists. | Authorization header only | lib/services/user_service.dart:22 UserService.getProfile candidate #2 |
| POST | `/api/auth/verify-otp` | Finish registration with the OTP; the backend creates the user and returns a JWT. The live path verifies by email. A phone-based variant exists but has no call… | otp, purpose ('registration'), email (verifyOtpByEmail), phone (verifyOtp, unused) | lib/services/auth_service.dart:723 AuthService.verifyOtpByEmail |
| POST | `/api/auth/verify-sendchamp` | Verify an OTP against a Sendchamp provider reference. Defined, NO callers. | reference, otp, phone \\| email | lib/services/auth_service.dart:663 AuthService.verifySendchamp |

## Users

| Method | Path | Purpose | Request fields | Called from |
|---|---|---|---|---|
| GET | `/api/users` | List users. Used as the last-resort artisan-list fallback (only when /api/artisans/search returned 2xx but unparseable data and the legacy list also failed), a… | page, limit (2x the requested limit in the fallback), q? (fetchAllUsers), id \\| userId (job details) | lib/services/artist_service.dart:240 fetchArtisans fallback #2 |
| GET | `/api/users/:id` | Look up another user (reviewer, client, counterparty) for display. | Authorization header (optional) | lib/services/user_service.dart:397 UserService.getUserById |
| GET | `/api/users/me` | Fetch the current user's profile. It is the app's main identity call: run at cold start, on every token change, and from most screens. Side effects: caches rol… | Authorization header | lib/services/user_service.dart:11 UserService.getProfile |
| PUT | `/api/users/me` | Update a customer profile, with an optional avatar. UserService sends to /api/artisans/me instead when the cached role is artisan, unless forceUserPath is set.… | name, email, phone, location, latitude, longitude | lib/services/user_service.dart:193 UserService.updateProfile |
| DELETE | `/api/users/me` | Permanently delete the account and its data, then log out locally. | Authorization header | lib/pages/profile/profile_widget.dart:299 _handleDeleteAccount |
| GET | `/api/users/profile` | Profile fallback #3 in UserService.getProfile. Undocumented. | Authorization header | lib/services/user_service.dart:23 UserService.getProfile candidate #3 |
| GET | `/api/users/user/:id` | User-lookup fallback #2 on the job details page. Undocumented. |  | lib/pages/job_details_page/job_details_page_widget.dart:1577 _fetchUserById |

## Artisans

| Method | Path | Purpose | Request fields | Called from |
|---|---|---|---|---|
| GET | `/api/artisan-services` | Query-style variant of the artisan offerings lookup, used on the artisan detail page (one call site sends no auth header). | artisanId, limit=100 | lib/pages/artisan_detail_page/artisan_detail_page_widget.dart:3228 _loadServicesForArtisan |
| POST | `/api/artisan-services` | Create or replace the artisan's offerings for a category (onboarding step 1 and My Services). Requires that the artisan profile already exists. | categoryId, services[{subCategoryId, price, currency:'NGN'}] | lib/services/my_service_service.dart:45 MyServiceService.createService |
| PUT | `/api/artisan-services/:id` | Update an ArtisanService document, for example to add or remove sub-services and prices. | categoryId?, services[{subCategoryId, price, currency}] | lib/services/my_service_service.dart:54 MyServiceService.updateService |
| DELETE | `/api/artisan-services/:id` | Remove (soft-delete) an ArtisanService. A composite id '<serviceId>_<subId>' is cut down to its first segment (my_service_service.dart:69-73). |  | lib/services/my_service_service.dart:64 MyServiceService.deleteService |
| GET | `/api/artisan-services/artisan/:artisanId` | Public offerings and prices for one artisan (accepts Artisan._id or User._id). Fetched once per artisan card on Home and Search. | Authorization header (optional) | lib/services/artist_service.dart:1676 ArtistService.fetchArtisanServices |
| GET | `/api/artisan-services/me` | List the authenticated artisan's service offerings: categories, sub-services and prices. | Authorization header | lib/services/my_service_service.dart:37 MyServiceService.fetchMyServices |
| GET | `/api/artisans` | Legacy artisan list, used as a fallback inside fetchArtisans: after an unparseable 2xx (15s timeout) or after a non-2xx from /search (10s timeout). | role=artisan, page, limit, q?, categoryId?, subCategoryId? | lib/services/artist_service.dart:209-217 fetchArtisans fallback #1 |
| POST | `/api/artisans` | Create the artisan profile. Sent multipart when files are present, otherwise JSON, after uploading files via attachments or Cloudinary. Also the automatic fall… | trade[], experience, serviceArea{address, coordinates[lng,lat], radius}, portfolio[{title, description?, imag… | lib/services/artist_service.dart:792 ArtistService.createMyProfile |
| GET | `/api/artisans/:id` | Public artisan profile by artisan _id or user _id, for the artisan detail page, the quote sheet and the special-request page. | Authorization header (optional) | lib/pages/artisan_detail_page/artisan_detail_page_widget.dart:230 _fetchArtisanById |
| PUT | `/api/artisans/me` | Update the artisan profile: each onboarding step, the availability preset, portfolio edits, and artisan avatar/profile edits. Tries multipart first when fileMa… | trade[], experience (onboarding step 1), serviceArea{address, radius, coordinates[lng,lat]} + file profileIma… | lib/services/artist_service.dart:968 ArtistService.updateMyProfile |
| GET | `/api/artisans/search` | Artisan discovery and search: home carousel, Discover list/map, and search results. | page, limit, q (falls back to trade or name), categoryId?, subCategoryId?, location? | lib/services/artist_service.dart:51 ArtistService.fetchArtisans |
| GET | `/api/artisans/user/:userId` | Fetch the artisan document by user id. This is how the app reads 'my artisan profile': getMyProfile calls UserService.getProfile, then getByUserId. The result… | Authorization header | lib/services/artist_service.dart:1585 ArtistService.getByUserId |

## Categories

| Method | Path | Purpose | Request fields | Called from |
|---|---|---|---|---|
| GET | `/api/job-categories` | Service categories: the 8 home tiles, onboarding trade picker, All Services, search, and job create/edit. Variants: ?page&limit, ?includeSubcategories=true, ?l… | page, limit, includeSubcategories? | lib/services/job_service.dart:124 JobService.getJobCategories |
| GET | `/api/job-subcategories` | Sub-services for a category. | categoryId, limit=50 (search page) | lib/services/my_service_service.dart:87 MyServiceService.fetchSubcategories |

## Jobs

| Method | Path | Purpose | Request fields | Called from |
|---|---|---|---|---|
| GET | `/api/jobs` | Job board list (JobPost tab) with a 45s in-memory cache. Also used as the cold-start health probe ?limit=1, sent without auth. | page, limit, q?, limit=1 (health probe) | lib/services/job_service.dart:187 getAllJobs |
| POST | `/api/jobs` | Customer posts a job. | title, company, description, trade[]?, location, coordinates? | lib/services/job_service.dart:100 JobService.createJob |
| GET | `/api/jobs/:id` | Job detail (detail page, edit form, notification deep link). |  | lib/services/job_service.dart:538 JobService.getJob |
| PUT | `/api/jobs/:id` | Edit a job. Primary call via ApiClient.put. If that fails it falls back to PATCH, then raw PUT again. | same fields as POST /api/jobs | lib/services/job_service.dart:440 JobService.updateJob |
| PATCH | `/api/jobs/:id` | Fallback for updateJob after ApiClient.put fails. Documented as PATCH in API_DOCS. | same fields as POST /api/jobs | lib/services/job_service.dart:494-496 JobService.updateJob |
| DELETE | `/api/jobs/:id` | Owner deletes a job. Sent without a Content-Type header on purpose. |  | lib/services/job_service.dart:392 JobService.deleteJob |
| GET | `/api/jobs/mine` | The current user's jobs. Tries ?clientId=<me> first, then no params with a client-side filter on clientId. Undocumented. | clientId? | lib/services/job_service.dart:295 getUserJobs |

## Quotes

| Method | Path | Purpose | Request fields | Called from |
|---|---|---|---|---|
| POST | `/api/bookings/:bookingId/quotes` | Booking-scoped quote submission. UNREACHABLE: bookingId is hard-coded to null just before the branch (job_detail_page_widget.dart:1158). | items[], total, notes, availability, contact{name, email, phone} | lib/pages/job_detail_page/job_detail_page_widget.dart:1162 submitQuote |
| GET | `/api/bookings/:bookingId/quotes/details` | Booking-scoped quotes with artisan and booking details populated. |  | lib/pages/applicants_page/applicants_page_widget.dart:71 _fetchQuoteDetailsAndMerge |
| GET | `/api/jobs/:jobId/quotes` | Quotes and applications for a job (owner's applicants list; artisan's 'already applied' check). | Authorization header (required) | lib/pages/job_details_page/job_details_page_widget.dart:537 _fetchJobQuotes |
| POST | `/api/jobs/:jobId/quotes` | Artisan submits a quote on a job (quote-only, no Application record). | items[{name:'Service', cost, qty:1}], serviceCharge (0), notes | lib/pages/submit_quote_page/submit_quote_page_widget.dart:58 _submitQuote |
| GET | `/api/jobs/:jobId/quotes/:quoteId` | Single quote detail, used to enrich applicant rows and resolve a quote before payment. |  | lib/pages/applicants_page/applicants_page_widget.dart:108 _fetchQuoteDetailsAndMerge |
| POST | `/api/jobs/:jobId/quotes/:quoteId/accept` | Job owner accepts a quote. The server initializes Paystack for quote.total and creates the booking after the webhook fires. | email?, paymentMode (.env PAYMENT_MODE, default 'upfront') | lib/services/job_service.dart:564 JobService.acceptJobQuote |
| POST | `/api/quotes` | Generic quote submission from the legacy JobDetailPage (route /jobDetailPage, opened from deposit_success_page_widget.dart:628). Undocumented. | items[], total, notes, availability, contact{name, email, phone} | lib/pages/job_detail_page/job_detail_page_widget.dart:1172 submitQuote |
| GET | `/api/quotes/:id` | Generic quote fetch, a fallback after the job-scoped route. Undocumented; quote_details_page_widget.dart:79-80/103 deliberately avoids it. |  | lib/pages/payment_init/payment_init_page_widget.dart:2356 _fetchQuoteById |

## Bookings

| Method | Path | Purpose | Request fields | Called from |
|---|---|---|---|---|
| GET | `/api/bookings` | Booking list. Used (a) to poll for the booking created from a paid quote and (b) as fallbacks for the artisan's bookings when /bookings/artisan/:id fails. | page, limit, artisanId \\| artisan \\| artisan_id (fallbacks) | lib/pages/payment_init/payment_init_page_widget.dart:1847 _pollForBookingFromQuote |
| GET | `/api/bookings/:id` | Single booking: detail view, state refresh after actions, and payment and completion polling in chat and checkout. |  | lib/pages/booking_page/booking_page_widget.dart:1000 _fetchBookingById, :1953 _showApiErr… |
| DELETE | `/api/bookings/:id` | Customer cancels a booking. Sent first without Content-Type; on a network error, or when the old Fastify backend returns FST_ERR_CTP_EMPTY_JSON_BODY, it retrie… | (optional {} body) | lib/pages/booking_page/booking_page_widget.dart:1590 _cancelBooking |
| POST | `/api/bookings/:id/accept` | Artisan accepts a booking. Afterwards the client re-fetches the booking and POSTs a notification to the customer. | {} (empty JSON) | lib/pages/booking_page/booking_page_widget.dart:1294 _acceptBooking |
| POST | `/api/bookings/:id/complete` | Customer marks a booking completed, which triggers payout and closes the chat. For afterCompletion bookings the backend requires a verified, held payment first. | confirm:true, currentStatus? (booking page), sendEmail:true (chat) | lib/pages/booking_page/booking_page_widget.dart:1815 _completeBooking |
| POST | `/api/bookings/:id/confirm-payment` | Mark the booking payment as received or held. The docs say this is webhook/admin-only, but the client calls it after verify, and chat sends a 'nudge' when paym… | reference?, verifyResponse? (raw verify body), (chat nudge: no body) | lib/pages/payment_init/payment_init_page_widget.dart:1319 _confirmBookingPayment |
| POST | `/api/bookings/:id/pay-after-completion` | Initialize Paystack for an afterCompletion booking, then open the checkout WebView. The app sends hard-coded zero customer coordinates. | email, customerCoords{lat:0.0, lon:0.0} | lib/pages/message_client/message_client_widget.dart:3329 _initializeDeferredPayment |
| POST | `/api/bookings/:id/pay-with-quote` | Initialize payment for a quote-based booking when a bookingId is known; otherwise the app uses /api/payments/initialize. | amount, currency:'NGN', email, artisanId?, quoteId?, bookingSource:'quote' | lib/pages/payment_init/payment_init_page_widget.dart:572 _initPaymentThenStart |
| POST | `/api/bookings/:id/reject` | Artisan rejects a booking; the server refunds paid bookings. | reason ('Rejected by artisan') | lib/pages/booking_page/booking_page_widget.dart:1413 _rejectBooking |
| GET | `/api/bookings/artisan/:artisanId` | The artisan's bookings: dashboard recent 5, Bookings tab and job history. The service returns [] when there is no token. | page, limit (5 dashboard / 100 history / 1000 when searching), status?, q? | lib/services/artist_service.dart:362 ArtistService.fetchArtisanBookings |
| GET | `/api/bookings/customer/:customerId` | The customer's bookings for the Bookings tab. | page, limit, q? | lib/pages/booking_page/booking_page_widget.dart:848 _fetchBookings |
| POST | `/api/bookings/hire` | One-call hire: create a booking and, for upfront mode, initialize Paystack. Used for direct hire from the artisan page, booking creation after quote payment, a… | artisanId (user id), services[{subCategoryId, quantity:1, categoryId?}] (artisan page) \\| services (payment… | lib/pages/artisan_detail_page/artisan_detail_page_widget.dart:2628 _buildActionButtons |

## Payments

| Method | Path | Purpose | Request fields | Called from |
|---|---|---|---|---|
| GET | `/api/payments` | Transactions fallback #3 inside WalletService.fetchTransactions. | page, limit | lib/services/wallet_service.dart:28 WalletService.fetchTransactions |
| GET | `/api/payments/banks` | Bank list for the payout account picker (Paystack banks proxied by the backend). |  | lib/pages/user_walletpage/user_walletpage_widget.dart:231 _loadBanks, :899 _showPayoutDet… |
| GET | `/api/payments/banks/resolve` | Resolve the account holder name for a bank account number. 429 means rate-limited. | account_number, bank_code | lib/pages/user_walletpage/user_walletpage_widget.dart:1358 _resolveAccountName |
| GET | `/api/payments/commission` | Platform-fee preview (percentage) for the artisan booking list; display only. The docs list it as /payment/commission. | amount? (not passed by the caller) | lib/services/payment_service.dart:35 PaymentService.getCommission |
| POST | `/api/payments/initialize` | Generic Paystack transaction initialize: quote payments without a bookingId, and the deferred booking payment before completion in chat. | amount, currency:'NGN', email, artisanId?, quoteId?, bookingSource ('quote'\\|'booking') | lib/pages/payment_init/payment_init_page_widget.dart:581 _initPaymentThenStart |
| POST | `/api/payments/verify` | Server-side Paystack verify by reference after the WebView returns. | reference (taken from response or authorization_url query: reference\\|ref\\|tx_ref\\|trxref...), paymentId?,… | lib/pages/payment_init/payment_init_page_widget.dart:1360 _verifyPayment |

## Wallet

| Method | Path | Purpose | Request fields | Called from |
|---|---|---|---|---|
| GET | `/api/transactions` | The user's transactions (scoped server-side), paginated. Status changes are diffed client-side to detect payouts. | page, limit (50) | lib/services/wallet_service.dart:16 fetchTransactions candidate #1 |
| GET | `/api/wallet` | Wallet summary for the wallet page. |  | lib/pages/user_walletpage/user_walletpage_widget.dart:542 _init |
| GET | `/api/wallet/payout-details` | Saved payout bank account. |  | lib/pages/user_walletpage/user_walletpage_widget.dart:863 _showPayoutDetailsSheet |
| PUT | `/api/wallet/payout-details` | Save the payout account. PUT is tried first even though the docs list only POST. On 404 it falls back to POST. | name, account_number, bank_code, bank_name, currency ('NGN') | lib/pages/user_walletpage/user_walletpage_widget.dart:663 _savePayoutDetails |
| POST | `/api/wallet/payout-details` | Payout save fallback: JSON POST after a PUT 404, then multipart POST with the same fields if still non-2xx. | name, account_number, bank_code, bank_name, currency | lib/pages/user_walletpage/user_walletpage_widget.dart:700-745 _savePayoutDetails |
| GET | `/api/wallet/transactions` | Transactions fallback #2 inside WalletService.fetchTransactions. Undocumented. | page, limit | lib/services/wallet_service.dart:27 WalletService.fetchTransactions |

## Kyc

| Method | Path | Purpose | Request fields | Called from |
|---|---|---|---|---|
| GET | `/api/kyc/artisan/:id/status` | KYC status for any artisan by artisan _id or user _id, with optional auth. The dashboard uses it as a fallback when /api/kyc/status returns 'No KYC record'. | Authorization header (optional) | lib/services/kyc_service.dart:496 KycService.getArtisanKycStatus |
| POST | `/api/kyc/dojah/nin-selfie` | Server-side Dojah NIN plus selfie match (multipart). UNREACHABLE: its only caller, LivenessCheckWidget, is not referenced anywhere. | nin, firstName?, lastName?, file selfie | lib/services/kyc_service.dart:264 KycService.submitDojahNinSelfie |
| POST | `/api/kyc/dojah/start-session` | Seed a pending KYC record and get the canonical referenceId to hand to the Dojah WebView SDK. The onboarding ABORTS the KYC launch if this fails (artisan_onboa… | status:'pending', provider:'dojah_sdk', providerStatus:'started' | lib/services/kyc_service.dart:342 KycService.startDojahSession |
| POST | `/api/kyc/dojah/verify-reference` | After the Dojah SDK finishes, ask the backend to pull Dojah's final result and persist it. The dashboard replays it in a background retry loop while status is… | referenceId | lib/services/kyc_service.dart:413 KycService.verifyDojahReference |
| GET | `/api/kyc/status` | The current user's latest KYC state, used to hydrate onboarding, show the dashboard KYC card and gate quote submission. The code works around a known 404 'No K… | Authorization header | lib/services/kyc_service.dart:560 KycService.getKycStatus |
| POST | `/api/kyc/submit` | Legacy manual KYC upload (multipart). Called only from the legacy ArtisanKycPageWidget (route /artisanKycPage, nav.dart:434-437), which no in-app navigation re… | businessName, country, state, lga, IdType, serviceCategory (category id or text) | lib/services/kyc_service.dart:178 KycService.submitKyc |

## Reviews

| Method | Path | Purpose | Request fields | Called from |
|---|---|---|---|---|
| GET | `/api/reviews` | Reviews for an artisan. Tries ?artisanId, then ?targetId / ?artisan / ?artisan_id, then an unfiltered page, with client-side filtering at every step. | artisanId \\| targetId \\| artisan \\| artisan_id, page, limit | lib/services/artist_service.dart:471 ArtistService.fetchReviewsForArtisan |
| POST | `/api/reviews` | Customer reviews the counterpart after completion. 409 means already reviewed. | targetId (participant user id), rating, comment?, bookingId? | lib/pages/message_client/message_client_widget.dart:4211 _submitReview |

## Notifications

| Method | Path | Purpose | Request fields | Called from |
|---|---|---|---|---|
| POST | `/api/devices/register` | Register or upsert this device's FCM token for push delivery. Runs when the JWT is restored at startup, after the notification permission dialog on login or we… | token (FCM), platform ('flutter') | lib/services/notification_controller.dart:525 registerDevice |
| POST | `/api/devices/unregister` | Remove the device token on logout (fire-and-forget). | token (FCM) | lib/services/notification_controller.dart:564 unregisterDevice |
| GET | `/api/notifications` | Notification list (notifications page) and unread badge. Home polls ?unread=true every 30s. It is also fallbacks #3/#4 of fetchUnreadCount. | unread=true \\| page & limit \\| none | lib/pages/home_page/home_page_widget.dart:679 _fetchUnreadNotifications |
| POST | `/api/notifications` | Two uses: (a) markAllRead candidate #4 with {}; (b) primary target of sendNotification, which has the CLIENT create a notification record for another user (boo… | toUserId, title, body, message, type?, payload{type, bookingId, status, eventType, requestId, requestTitle, q… | lib/services/notification_service.dart:109 markAllRead, :126 sendNotification |
| GET | `/api/notifications/count` | Unread count, fetchUnreadCount candidate #2. Undocumented. |  | lib/services/notification_service.dart:38 fetchUnreadCount |
| POST | `/api/notifications/create` | sendNotification fallback #3. Undocumented. | toUserId, title, body, message, type?, payload? | lib/services/notification_service.dart:138 sendNotification |
| POST | `/api/notifications/mark-all-read` | Mark all notifications read, markAllRead candidate #1. | {} | lib/services/notification_service.dart:106 markAllRead |
| POST | `/api/notifications/mark-read` | markAllRead candidate #3. | {} | lib/services/notification_service.dart:108 markAllRead |
| POST | `/api/notifications/read` | markAllRead candidate #2. Undocumented. | {} | lib/services/notification_service.dart:107 markAllRead |
| POST | `/api/notifications/send` | sendNotification fallback #2. Undocumented. | toUserId, title, body, message, type?, payload? | lib/services/notification_service.dart:137 sendNotification |
| GET | `/api/notifications/unread-count` | Unread badge count, fetchUnreadCount candidate #1. Undocumented. |  | lib/services/notification_service.dart:37 fetchUnreadCount |

## Chat

| Method | Path | Purpose | Request fields | Called from |
|---|---|---|---|---|
| GET | `/api/chat/:threadId` | Chat thread by id. |  | lib/pages/message_client/message_client_widget.dart:1494 _fetchChatByThreadId, :1561 _fet… |
| POST | `/api/chat/:threadId` | Send a chat message over REST. The socket 'message' emit is a separate realtime path. | text | lib/pages/message_client/message_client_widget.dart:1951 _sendMessageHttp |
| GET | `/api/chat/booking/:bookingId` | Chat thread for a booking: messages plus threadId. The chat exists only after payment is confirmed. | Authorization header (required) | lib/pages/message_client/message_client_widget.dart:681 _fetchChat, :1605 _fetchChatInBac… |

## Special-requests

| Method | Path | Purpose | Request fields | Called from |
|---|---|---|---|---|
| GET | `/api/special-service-requests` | List special (custom-quote) requests for a client or an artisan. | clientId \\| artisanId, page?, limit? | lib/services/special_service_request_service.dart:295 fetchForClient |
| POST | `/api/special-service-requests` | Client creates a special request to an artisan: JSON, or multipart with images in files[]. Afterwards the client POSTs a notification to the artisan. | artisanId, title, description, location, budget (0), urgency ('Normal'\\|'Urgent') | lib/services/special_service_request_service.dart:610 create |
| GET | `/api/special-service-requests/:id` | Special request detail with the artisan reply, plus booking and payment once accepted. |  | lib/services/special_service_request_service.dart:387 fetchById |
| PUT | `/api/special-service-requests/:id` | Status changes: accept (may return a Paystack payment), cancel, or confirm after a deferred booking. | status ('accepted'\\|'cancelled'\\|'confirmed'), selectedPrice? (accept), paymentMode (accept; .env PAYMENT_M… | lib/services/special_service_request_service.dart:460 acceptResponse |
| POST | `/api/special-service-requests/:id/pay` | Explicitly initialize payment for an accepted special request. Defined, NO callers (the accept PUT returns the payment). | email? | lib/services/special_service_request_service.dart:709 initializePayment |
| GET | `/api/special-service-requests/:id/response` | Artisan's response to a special request (same payload as GET /:id per the docs). |  | lib/services/special_service_request_service.dart:421 fetchArtisanResponse |
| POST | `/api/special-service-requests/:id/response` | Artisan responds with a fixed or range quote. POST is preferred; on non-2xx the app falls back to PUT on the same path. | status:'responded', note{...}, artisanReply{quoteType ('fixed'\\|'range'), quote \\| min \\| max \\| options,… | lib/services/special_service_request_service.dart:554 submitArtisanResponse |
| PUT | `/api/special-service-requests/:id/response` | Fallback for POST /:id/response (older backends that flatten min/max). | status:'responded', note, artisanReply | lib/services/special_service_request_service.dart:585-589 submitArtisanResponse |

## Announcements

| Method | Path | Purpose | Request fields | Called from |
|---|---|---|---|---|
| GET | `/api/ads` | Home ad carousel images, candidate #1. Falls back to bundled default ads. |  | lib/pages/home_page/home_page_widget.dart:595 _loadAds |
| GET | `/api/ads/carousel` | Home ad carousel, candidate #3. |  | lib/pages/home_page/home_page_widget.dart:597 _loadAds |
| GET | `/api/ads/marquee` | Home marquee, candidate #3 (dart-define only). |  | lib/services/announcement_service.dart:19 getMarqueeText |
| GET | `/api/announcements` | Home marquee, candidate #2 (dart-define only). Undocumented. |  | lib/services/announcement_service.dart:18 getMarqueeText |
| GET | `/api/announcements/ads` | Home ad carousel, candidate #2. Undocumented. |  | lib/pages/home_page/home_page_widget.dart:596 _loadAds |
| GET | `/api/announcements/latest` | Home marquee text, candidate #1. Requested ONLY when built with --dart-define=API_BASE_URL (announcement_service.dart:13); with .env alone, nothing is called. |  | lib/services/announcement_service.dart:17 getMarqueeText <- home_page_widget.dart:670 _lo… |
| GET | `/api/meta/announcements` | Home marquee, candidate #4 (dart-define only). Undocumented. |  | lib/services/announcement_service.dart:20 getMarqueeText |

## Uploads

| Method | Path | Purpose | Request fields | Called from |
|---|---|---|---|---|
| POST | `/api/attachments` | Attachments candidate #3. Undocumented. | files[{name, content}] | lib/services/artist_service.dart:1161 uploadFilesToAttachments |
| POST | `/api/files` | Attachments candidate #4. If all four fail, the app falls back to direct Cloudinary upload via /api/uploads/sign. Undocumented. | files[{name, content}] | lib/services/artist_service.dart:1162 uploadFilesToAttachments |
| POST | `/api/uploads` | Attachments candidate #1: base64 JSON upload, used when the multipart artisan save fails. Undocumented. | files[{name, content (base64; files over 10MB skipped)}] | lib/services/artist_service.dart:1159 uploadFilesToAttachments |
| POST | `/api/uploads/images` | Attachments candidate #2. Undocumented. | files[{name, content}] | lib/services/artist_service.dart:1160 uploadFilesToAttachments |
| POST | `/api/uploads/sign` | Get a Cloudinary signed-upload signature so the app can upload directly to Cloudinary. ArtistService calls it WITHOUT auth; the portfolio page sends the bearer… | folder ('artisans' \\| 'artisans/portfolio'), public_id? | lib/services/upload_service.dart:13 UploadService.requestSignature |

## Other

| Method | Path | Purpose | Request fields | Called from |
|---|---|---|---|---|
| GET | `/api/admin/central` | Role-aware 'central' dashboard aggregate called with the ARTISAN's token. It returns data.mine with wallet, bookings, reviews and transactions. On failure the… | limit=10 | lib/pages/artisan_dashboard_page/artisan_dashboard_page_widget.dart:1548 _loadDashboardDa… |
| POST | `/api/admin/central` | Update the admin central config. Defined, NO callers. | (arbitrary payload) | lib/services/admin_service.dart:32 updateCentral |
| GET | `/api/locations/nigeria/lgas` | LGAs for a state; same legacy-page fallback as /states. | state | lib/pages/artisan_kyc_page/artisan_kyc_page_widget.dart:224 _fetchLgasForState |
| GET | `/api/locations/nigeria/states` | Nigeria states list, called only when the bundled asset or LocationService fails, and only on the legacy KYC page (no in-app navigation). |  | lib/pages/artisan_kyc_page/artisan_kyc_page_widget.dart:163 _fetchStates |

## Realtime (Socket.IO)

| Direction | Event | Purpose |
|---|---|---|
| emit | `join` | Join the per-user room on connect, and the per-thread room when a chat opens |
| emit | `leave` | Leave a chat thread room |
| emit | `message` | Realtime fan-out of a chat message after it is sent; REST POST /api/chat/:threadId persists it |
| emit | `typing` | Typing indicator start/stop |
| emit | `presence` | Presence status |
| emit | `read` | Read receipts. Defined but has NO callers |
| emit | `notification` | Client-originated chat notification {type:'chat_message', threadId, bookingId, from, to, message, title} |
| listen | `connect / connect_error / connect_timeout / error / reconnect_failed / reconnect_error` | Connection lifecycle and logging |
| listen | `disconnect` | On 'io server disconnect': AppStateNotifier.refreshAuth then reconnect after 2s with the stored token. Otherwise reconnect after 5s |
| listen | `notification` | Server push of an in-app notification. Payload keys read: userId \| recipientId \| to, broadcast, title, message \| text, type, bookingId.… |
| listen | `message / thread_message` | Incoming chat message. Fields: threadId, message \| payload (senderId, sender, text, createdAt) |
| listen | `thread_created / chat_ready` | The chat thread became available after payment confirmation |
| listen | `booking_closed / chat_closed` | Booking completed or chat closed |
| listen | `typing` | Show the other party's typing indicator |
| listen | `presence` | Show online/offline |
| listen | `read` | Read receipts |
| listen | `booking_paid / payment_confirmed / payment_success / new_message / chat_message` | Expected by the chat page but NOT registered as socket listeners in realtime_notifications.dart:300-311. They only arrive as the 'event' ke… |
| listen | `FCM push (onMessage / onBackgroundMessage / onMessageOpenedApp / getInitialMessage / onTokenRefresh)` | Push notifications sent by the backend via Firebase. Data keys read: title, body, channelKey \| channel_key. Shown with Awesome Notificatio… |
| emit | `Gemini Live session (setup, realtime text, audio chunks, toolCall escalate_to_human / end_call, turnComplete, goAway)` | AI voice support call. Talks directly to Google, not the old backend. 'escalate_to_human' only sets a local flag. Auto-reconnects every 14… |

## Third-party services the app calls directly

| Service | Used for | Works without the old backend? |
|---|---|---|
| Firebase Core + App Check | Firebase.initializeApp at startup and in the FCM background isolate. App Check is activated with Play Integrity (debug provider in debug builds), App… | Yes |
| Firebase Cloud Messaging (+ Awesome Notifications for local display) | Push token, foreground/background messages, topic subscribe (debug page only), local notification channels. Delivery depends on a server holding the… | No |
| Firebase Auth / Firebase Analytics | Declared in pubspec but unused. The phone-OTP code is commented out (auth_service.dart:1130-1225) and no Analytics calls exist in lib/ | Yes |
| Google Sign-In (google_sign_in v7) | Gets a Google idToken (serverClientId = GOOGLE_WEB_CLIENT_ID). The session is only created by exchanging it at POST /api/auth/oauth/google | No |
| Sign in with Apple | Gets an Apple identityToken with a SHA-256 nonce. Exchanged at POST /api/auth/oauth/apple | No |
| Google Maps Geocoding API (REST) | Reverse-geocode device GPS (geolocator) into a formatted_address on Home, Dashboard, Onboarding and Special Request; forward-geocode typed addresses… | Yes |
| Google Places API (legacy Autocomplete + Place Details REST) | Service-area search in artisan onboarding, restricted to Nigeria and a 60km strictbounds circle around Abuja. Details (geometry, formatted_address) s… | Yes |
| Google Maps SDK (google_maps_flutter) | Discover map with artisan markers. Native API keys are hardcoded in native config, not .env | Yes |
| OpenStreetMap Nominatim | Free geocoding (search) and reverse geocoding for job create/edit, legacy profile update and job/special-request location labels. Sends a placeholder… | Yes |
| Cloudinary (direct signed upload) | Uploads artisan portfolio and profile images straight to https://api.cloudinary.com/v1_1/{cloud_name}/auto/upload (or the server-supplied upload_url)… | No |
| Paystack (hosted checkout) | The checkout page (authorization_url from the backend) is loaded in a webview_flutter WebView. Success or failure is detected from URL patterns: a no… | No |
| Dojah KYC (flutter_dojah_kyc WebView widget) | NIN plus liveness plus selfie verification in a Dojah-hosted widget, using DOJAH_APP_ID, DOJAH_PUBLIC_KEY and DOJAH_WIDGET_ID with referenceId, userD… | No |
| Google Gemini Live API (gemini_live package) | Real-time AI voice support agent ('Rij'). Model gemini-3.1-flash-live-preview, voice Charon, system prompt from SupportKnowledgeBase.systemPrompt. Th… | Yes |
| Sendchamp (SMS OTP) | Registration OTP delivery and verification happen SERVER-side only. The app never calls Sendchamp: /api/auth/verify-sendchamp has no callers, and Tok… | No |
| Google connectivity probe (www.google.com/generate_204) | Home page online/offline detection every 30s, retrying failed sections when the network returns | Yes |
| RijHub website / email / phone (url_launcher) | Terms and Privacy pages on the old domain, support email, phone line. These are static web pages, not the API, but they live on the old domain and ne… | Yes |
| Unsplash (hotlinked placeholder images) | Static placeholder images on the FlutterFlow 'see all images' page | Yes |

## Calls the completeness check added

These were missing from the first pass: inbound events, third-party uploads and webviews, deep links and dormant code.

- **SOCKET.IO emit** `'join' {userId} and 'join' {room}, both sent on every connect`: Joins the per-user room that targeted 'notification' events go to. The inventory lists only 'join' {threadId} (:425-433), so the backend's 'join' handler must…
- **SOCKET.IO on (server to client)** `'notification'`: Realtime in-app notification. Bumps the unread badge when payload userId/recipientId/to matches the user or broadcast==true (:233-251), shows a local banner fr…
- **SOCKET.IO on (server to client)** `'message', 'thread_message', 'thread_created', 'chat_ready', 'booking_closed', 'chat_closed', 'typing', 'read', 'presen…`: Chat events the new backend must emit. 'read' is subscribed but has no UI handler.
- **SOCKET.IO on (expected, never subscribed)** `'new_message', 'chat_message', 'booking_paid', 'payment_confirmed', 'payment_success'`: Pay-after-completion confirmation and alternate chat event names. They reach the UI only if the server puts them in an `event` field inside 'notification' or o…
- **SOCKET.IO on (lifecycle)** `connect_error, connect_timeout, reconnect_failed, reconnect_error, disconnect`: On disconnect reason 'io server disconnect' it calls AppStateNotifier.refreshAuth() (may trigger POST /api/auth/refresh and a profile GET), then reconnects wit…
- **POST (FlutterFlow ApiManager, dead code)** `https://thiago-extraditable-ellis.ngrok-free.dev/api/auth/login`: Leftover FlutterFlow LogInCall pointing at a hardcoded third host (ngrok). Nothing imports lib/backend, so it never runs. Safe to delete.
- **POST (FlutterFlow ApiManager, dead code)** `https://thiago-extraditable-ellis.ngrok-free.dev/api/auth/register`: Leftover FlutterFlow RegisterUserCall (name/email/password serialized as JSON lists). Never referenced.
- **POST (multipart, third-party)** `signData.upload_url, or https://api.cloudinary.com/v1_1/{cloud_name}/auto/upload`: Direct signed Cloudinary upload in the service layer, used as a fallback when /api/uploads, /api/uploads/images, /api/attachments and /api/files all fail. The…
- **GET (third-party)** `https://nominatim.openstreetmap.org/search?q={place}&format=json&limit={n}&addressdetails=1 (User-Agent 'rijhub-app/1.0…`: Forward geocoding of job and profile locations through free OpenStreetMap Nominatim, which is rate-limited and has a placeholder User-Agent. Used in the main j…
- **GET (third-party)** `https://nominatim.openstreetmap.org/reverse?format=json&lat={lat}&lon={lon}&zoom=18&addressdetails=1`: Reverse-geocodes coordinates stored on jobs and special requests into a display address.
- **WEBVIEW (third-party SDK, flutter_dojah_kyc)** `Dojah hosted KYC widget: DojahKYC(appId DOJAH_APP_ID, publicKey DOJAH_PUBLIC_KEY, type 'custom', referenceId, config.wi…`: Live artisan identity verification (NIN, liveness, selfie) on Dojah's servers. The new backend's start-session and verify-reference must match this reference f…
- **WEBSOCKET (third-party, gemini_live package)** `Gemini Live API: GoogleGenAI(apiKey: GEMINI_API_KEY).live.connect(model 'gemini-3.1-flash-live-preview', AUDIO, tools e…`: AI voice support. The Gemini API key ships in the client .env. Tool calls are handled locally (gemini_live_service.dart:359-384) and reach no backend.
- **WEBVIEW (embedded browser GET)** `authorization_url returned by PUT /api/special-service-requests/:id (acceptResponse body {status:'accepted', selectedPr…`: Third Paystack checkout opener, for special requests. The inventory's WEBVIEW entry cites only payment_init :703 and message_client :3412-3429.
- **WEBVIEW source (not listed)** `authorization_url / reference from POST /api/jobs/:jobId/quotes/:quoteId/accept response.payment`: Another backend source of the checkout URL that the inventory's WEBVIEW entry omits (it lists :593, message_client :1331, :3354).
- **LAUNCH URL (external)** `notification.url (from notification data 'url' / 'link' / payload.url)`: Opens any URL the old backend put in a notification. The new backend needs to decide whether notifications carry links.
- **LAUNCH URL (mailto / tel)** `mailto:support@rijhub.com (one variant with subject and quote-id body); tel:08053466666`: Support contact links tied to the old rijhub.com email domain. Not listed, although the www.rijhub.com terms and privacy launches are.
- **LAUNCH URL (external)** `tel:/mailto: links inside checkout; 'Open in browser' relaunch of the authorization_url`: Payment WebView escape hatches. The inventory cites only the payment_init_page_widget.dart:1190-1193 fallback.
- **IMPLICIT URL construction, persisted to backend** `API_BASE_URL + '/relative/path' baked into upload results and portfolio image URLs`: Turns server-relative paths into absolute https://rijhub.com/... URLs and writes them back into stored artisan data, so the old host ends up in the database, n…
- **DEEP LINK (inbound)** `rijhub://.../resetPassword or /reset-password?token={t}&email={e}`: The new backend's password-reset email has to generate this link so the app routes to /resetPassword.
- **POST (commented out)** `/api/auth/registeruserfirebase body {idToken,name,email,password,role}`: Dormant Firebase-phone registration. Missing from the inventory, and code here gets commented out rather than deleted, so it could be re-enabled.
- **POST (commented out)** `/api/auth/verify-registration-reference body {email, reference}`: Dormant registration verification by reference.
- **GET (documented, not called)** `/api/kyc/dojah/config`: Planned endpoint for rotating the Dojah widget id. No code calls it.
- **GET (implicit image load, third-party)** `https://images.unsplash.com/photo-... (placeholder images)`: FlutterFlow placeholder page that loads remote stock images.
- **SDK (third-party map tiles)** `Google Maps SDK GoogleMap widget`: Map rendering. Uses separate native API keys, not GOOGLE_MAPS_API_KEY.

## Entries that are dead or misleading

- `GET (dart:io HttpClient) https://rijhub.com @ lib/main.dart:1071 in testCustomHttpClient()`: Dead code. Neither testCustomHttpClient() (main.dart:1068-1079) nor createCustomHttpClient() (:1056-1066) is called anywhere in lib/, so this request never happens.
- `GET (implicit image load) ... home_page_widget.dart:983-1001 _resolveAdSource()`: The URL is wrong. _resolveAdSource builds its base with _normalizeBaseUrl (home_page_widget.dart:975-981), and :980 ends with .replaceAll(RegExp(r'/+'), ''), which removes every '/'. For API_BASE_URL…
- `GET /api/announcements/latest, GET /api/announcements, GET /api/ads/marquee, GET /api/met…`: Never requested in practice. announcement_service.dart:13 takes its base from const String.fromEnvironment('API_BASE_URL') (a compile-time --dart-define), not dotenv. No dart-define exists anywhere i…
- `POST /api/auth/guest`: Dead. AuthService.guest() (auth_service.dart:363-364) has no callers. The only entry point is a /* */-commented button (splash2_widget.dart:271-300) whose handler _continueAsGuest doesn't exist.
- `POST /api/auth/verify-sendchamp`: Dead. AuthService.verifySendchamp (auth_service.dart:663-670) has no callers. OTP goes through /api/auth/verify-otp (verifyOtpByEmail :723) instead.
- `POST /api/admin/central`: Dead. Its only sender is AdminService.updateCentral (admin_service.dart:32-34), and AdminService is never referenced. GET /api/admin/central is live only through the direct call at artisan_dashboard_…
- `POST /api/special-service-requests/:id/pay`: Dead. SpecialServiceRequestService.initializePayment (special_service_request_service.dart:709-725) has no callers. Special-request payment is started server-side by PUT /api/special-service-requests…
- `POST /api/kyc/dojah/nin-selfie`: Dead. Its only caller is LivenessCheckWidget (liveness_check_widget.dart:68), which is never instantiated anywhere; the file header (:10-24) marks it 'LEGACY — kept for rollback'.
- `POST /api/kyc/submit; GET /api/locations/nigeria/states; GET /api/locations/nigeria/lgas…`: Unreachable legacy screen. These are called only from ArtisanKycPageWidget (submit at :1598). Its route /artisanKycPage is registered (nav.dart:434-437) but nothing navigates to it; the imports are c…
- `SOCKET.IO emit 'read' {threadId,messageIds} / 'presence' {userId,status}`: 'read' is never emitted: emitRead (realtime_notifications.dart:436-447) has no callers. 'presence' is only ever sent with status 'offline', from dispose (message_client_widget.dart:435); 'online' is…
- `SOCKET.IO emit 'message' {threadId,text}`: Misleading as a send path. The message is first saved by HTTP POST /api/chat/:threadId; the socket 'message' is emitted only afterwards as a notify (message_client_widget.dart:2019-2020 and :2033, th…
- `Header: 'Endpoints already listed from the service layer (120)'`: Mislabelled. 29 of the 120 have no code in lib/services and are called only from page widgets: GET /api/users/user/:id, DELETE /api/users/me, GET /api/artisans/:id, GET/POST /api/jobs/:jobId/quotes,…

