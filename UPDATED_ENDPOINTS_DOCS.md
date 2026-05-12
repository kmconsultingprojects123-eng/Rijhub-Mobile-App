# Updated Booking & Payment API Endpoints Documentation

## Overview
This document outlines the updated booking and payment endpoints with consistent `paymentMode` support across all booking types (direct hires, job quotes, special requests). Key improvements include duplicate prevention, flexible payment validation, and deferred payment workflows.

## Authentication
All endpoints require JWT authentication via `Authorization: Bearer <token>` header.

---

## Core Booking Endpoints

### 1. Hire & Initialize Booking (One-Call Hire)
**Endpoint:** `POST /booking/hire`  
**Purpose:** Create booking and initialize payment in one request

**Request Body:**
```json
{
  "artisanId": "string (24-char MongoDB ID)",
  "schedule": "string (ISO date string)",
  "email": "string (customer email - required)",
  "price": "number (optional - auto-calculated from services)",
  "notes": "string (optional)",
  "services": [
    {
      "subCategoryId": "string (24-char MongoDB ID)",
      "quantity": "number (default: 1)"
    }
  ],
  "categoryId": "string (optional)",
  "subCategoryId": "string (optional)",
  "artisanServiceId": "string (optional)",
  "paymentMode": "string (enum: 'upfront', 'afterCompletion')",
  "customerCoords": {
    "lat": "number",
    "lon": "number"
  }
}
```

**Why customerCoords is needed:**
The `customerCoords` field captures the customer's location coordinates during booking creation. This enables:

1. **Distance Calculation**: Automatic calculation of distance between customer and artisan locations
2. **Service Area Validation**: Verification that the artisan operates in the customer's area
3. **Analytics**: Geographic data for business insights and service optimization
4. **Location-based Features**: Future enhancements for location-aware services

**Note:** Coordinates are stored in Paystack metadata and used to populate `booking.distanceKm` for analytics.

**Response:**
- **upfront paymentMode:** Returns booking + Paystack payment initialization data
- **afterCompletion paymentMode:** Returns booking with deferred payment status

**Features:**
- ✅ Duplicate booking prevention (customer/artisan/schedule/price matching)
- ✅ Server-side price calculation from artisan services
- ✅ Chat thread creation for all bookings
- ✅ Artisan SMS/email notifications

---

### 2. Create Booking (Manual Creation)
**Endpoint:** `POST /booking`  
**Purpose:** Create booking without immediate payment initialization

**Request Body:** Same as hire endpoint (without email/customerCoords)

**Features:**
- ✅ Duplicate booking prevention
- ✅ Chat thread creation
- ✅ Artisan notifications

---

### 3. Pay After Completion (Deferred Payment)
**Endpoint:** `POST /booking/:id/pay-after-completion`  
**Purpose:** Initialize payment for `afterCompletion` bookings after service is done but before booking completion

**Request Body:**
```json
{
  "email": "string (optional - uses booking customer email)",
  "customerCoords": {
    "lat": "number",
    "lon": "number"
  }
}
```

**Why customerCoords is needed:**
The `customerCoords` field captures the customer's location coordinates when payment is initiated. This data serves several important purposes:

1. **Distance Calculation**: When payment succeeds, the system calculates the distance between the customer and artisan using the Haversine formula
2. **Analytics**: Distance data is stored on the booking for business analytics and service area analysis
3. **Service Area Validation**: Helps verify if the artisan is operating within their defined service area
4. **Geographic Insights**: Enables location-based reporting and optimization of service delivery

**Note:** Coordinates are stored in Paystack metadata and retrieved during webhook processing to calculate `booking.distanceKm`.

**Response Structure (Paystack Configured):**
```json
{
  "success": true,
  "data": {
    "booking": {
      "_id": "string (24-char MongoDB ID)",
      "customerId": "string (User ID)",
      "artisanId": "string (User ID)",
      "service": "string",
      "price": "number",
      "schedule": "string (ISO date)",
      "status": "string (accepted, in-progress, or completed)",
      "paymentMode": "string (afterCompletion)",
      "paymentStatus": "string (unpaid)",
      "createdAt": "string (ISO date)",
      "updatedAt": "string (ISO date)"
    },
    "payment": {
      "authorization_url": "string (Paystack payment URL)",
      "access_code": "string",
      "reference": "string (unique transaction reference)",
      "amount": "number (amount in kobo)",
      "currency": "string (NGN)",
      "status": "string (pending)",
      "paid_at": null,
      "created_at": "string (ISO date)",
      "expires_at": "string (ISO date)",
      "metadata": {
        "bookingId": "string",
        "customerCoords": {
          "lat": "number",
          "lon": "number"
        }
      }
    }
  }
}
```

**Response Structure (Paystack Not Configured):**
```json
{
  "success": true,
  "message": "Deferred payment recorded; Paystack is not configured.",
  "data": {
    "booking": { /* booking object */ },
    "transaction": {
      "_id": "string (24-char MongoDB ID)",
      "bookingId": "string",
      "payerId": "string (User ID)",
      "amount": "number",
      "status": "string (pending)",
      "paymentGatewayRef": null,
      "createdAt": "string (ISO date)",
      "updatedAt": "string (ISO date)"
    }
  }
}
```

**Response Structure (Existing Transaction):**
```json
{
  "success": true,
  "message": "Deferred payment already initialized and waiting for completion release.",
  "data": {
    "booking": { /* booking object */ },
    "transaction": {
      "_id": "string (24-char MongoDB ID)",
      "bookingId": "string",
      "payerId": "string (User ID)",
      "amount": "number",
      "status": "string (holding or pending)",
      "paymentGatewayRef": "string (Paystack reference)",
      "createdAt": "string (ISO date)",
      "updatedAt": "string (ISO date)"
    }
  }
}
```

**Validation:**
- Booking must be `afterCompletion` mode
- Booking status must be `accepted`, `in-progress`, or `completed`
- No existing pending/holding transaction
- Email required (customer email used as fallback)

**Payment Initialization Process:**
1. ✅ Validates booking state and payment mode
2. ✅ Checks for existing transactions to prevent duplicates
3. ✅ Calls Paystack `/transaction/initialize` API
4. ✅ Creates local transaction record with `status: 'pending'`
5. ✅ Returns authorization URL for customer payment
6. ✅ Customer completes payment via Paystack
7. ✅ Webhook processes payment and updates transaction to `holding`
8. ✅ Funds released when booking completion triggers payout

---

### 4. Complete Booking
**Endpoint:** `POST /booking/:id/complete`  
**Purpose:** Mark booking as completed by customer

**Validation:**
- For `afterCompletion` bookings: payment must already be verified and the transaction must be `holding`
- Booking status must be `in-progress` or `accepted`

**Features:**
- ✅ Automatic payment verification for pending transactions
- ✅ Payout processing (wallet credit or Paystack transfer)
- ✅ Company commission calculation and crediting
- ✅ Artisan/customer notifications
- ✅ Chat closure
- ✅ Review prompting

---

### 5. Accept Booking (Artisan Acceptance)
**Endpoint:** `POST /booking/:id/accept`  
**Purpose:** Artisan accepts a booking

**Validation:**
- Only assigned artisan can accept
- Booking status must be `awaiting-acceptance`
- For upfront bookings: Payment must be confirmed

---

### 6. Reject Booking (Artisan Rejection)
**Endpoint:** `POST /booking/:id/reject`  
**Purpose:** Artisan rejects a booking with reason

**Request Body:**
```json
{
  "reason": "string (optional rejection reason)"
}
```

**Features:**
- ✅ Automatic refund processing for paid bookings
- ✅ Customer notification with rejection reason

---

### 7. Cancel Booking (Customer Cancellation)
**Endpoint:** `DELETE /booking/:id`  
**Purpose:** Customer cancels booking

**Features:**
- ✅ Refund processing for paid bookings
- ✅ Paystack refund API integration
- ✅ Fallback to internal refund marking

---

### 8. Artisan Cancel Booking
**Endpoint:** `POST /booking/:id/artisan-cancel`  
**Purpose:** Artisan cancels `afterCompletion` booking with reason

**Request Body:**
```json
{
  "reason": "string (required cancellation reason)"
}
```

**Validation:**
- Only for `afterCompletion` bookings
- Booking not completed or paid

---

### 9. Confirm Payment (Webhook/Admin)
**Endpoint:** `POST /booking/:id/confirm-payment`  
**Purpose:** Mark transaction as received and held in escrow

**Features:**
- ✅ Updates booking status to `awaiting-acceptance`
- ✅ Sets payment status to `paid`
- ✅ Artisan notification for acceptance

---

## Listing & Retrieval Endpoints

### 10. List Bookings
**Endpoint:** `GET /booking`  
**Query Parameters:**
- `page`: integer (default: 1)
- `limit`: integer (default: 20, max: 100)
- `status`: string (filter by booking status)

---

### 11. Get Customer Bookings
**Endpoint:** `GET /booking/customer/:customerId`  
**Purpose:** Get bookings for specific customer with artisan details

**Features:**
- ✅ Includes artisan user and profile data
- ✅ Authorization: Customer themselves or admin

---

### 12. Get Artisan Bookings
**Endpoint:** `GET /booking/artisan/:artisanId`  
**Purpose:** Get bookings for specific artisan with customer details

**Features:**
- ✅ Includes customer user data
- ✅ Authorization: Artisan themselves or admin

---

### 13. Get Single Booking
**Endpoint:** `GET /booking/:id`  
**Purpose:** Retrieve detailed booking information

---

### 14. Get Refund Status
**Endpoint:** `GET /booking/:id/refund`  
**Purpose:** Check refund status for a booking

**Response:**
```json
{
  "success": true,
  "data": {
    "refundId": "string (Paystack refund ID)",
    "refundStatus": "string (none, requested, refunded)"
  }
}
```

---

## Quote System Endpoints

### 15. Post Requirements
**Endpoint:** `POST /booking/:id/requirements`  
**Purpose:** Customer posts requirements for a booking

**Authorization:** Customer/Client role required

---

### 16. Create Quote
**Endpoint:** `POST /booking/:id/quotes`  
**Purpose:** Artisan creates quote for booking requirements

**Request Body:**
```json
{
  "items": [
    {
      "name": "string",
      "qty": "number",
      "note": "string (optional)",
      "cost": "number"
    }
  ],
  "serviceCharge": "number (optional)",
  "notes": "string (optional)"
}
```

**Authorization:** Artisan role required

---

### 17. List Quotes
**Endpoint:** `GET /booking/:id/quotes`  
**Purpose:** List quotes for a booking

---

### 18. List Quotes Detailed
**Endpoint:** `GET /booking/:id/quotes/details`  
**Purpose:** List quotes with artisan user/profile and booking details

---

### 19. Accept Quote
**Endpoint:** `POST /booking/:id/quotes/:quoteId/accept`  
**Purpose:** Customer accepts a quote

**Features:**
- ✅ Creates new booking from accepted quote
- ✅ Duplicate booking prevention
- ✅ Supports both payment modes

---

### 20. Pay with Quote
**Endpoint:** `POST /booking/:id/pay-with-quote`  
**Purpose:** Initialize payment for quote-based booking

**Request Body:**
```json
{
  "email": "string (customer email)"
}
```

---

## Payment Flow Summary

### Upfront Payment Flow:
1. `POST /booking/hire` → Paystack initialization
2. Customer completes payment → Webhook calls `POST /booking/:id/confirm-payment`
3. Artisan receives notification → `POST /booking/:id/accept` or `POST /booking/:id/reject`
4. Work completion → `POST /booking/:id/complete` → Payout processing

### After-Completion Payment Flow (Current):
1. `POST /booking/hire` with `paymentMode: "afterCompletion"` -> booking is created with no upfront payment
2. Artisan accepts the booking -> `POST /booking/:id/accept`
3. Service is done while booking is `accepted` or `in-progress`
4. Customer initiates payment -> `POST /booking/:id/pay-after-completion`
5. Customer completes Paystack checkout
6. Backend webhook or `POST /payment/verify` confirms payment and sets the transaction to `holding`
7. Customer completes booking -> `POST /booking/:id/complete`
8. Completion deducts company commission, records company earning, and releases artisan payout

### Legacy After-Completion Notes (Superseded):
1. `POST /booking/hire` with `paymentMode: "afterCompletion"` → Booking created (no payment)
2. Artisan acceptance → `POST /booking/:id/accept`
3. Work completion → `POST /booking/:id/complete` (fails without payment)
4. Customer initiates payment → `POST /booking/:id/pay-after-completion`
5. Customer completes payment → Webhook processes → Funds released to artisan

## Key Features Implemented

### ✅ Payment Mode Consistency
- All booking creation endpoints support `paymentMode` parameter
- Consistent validation and flow handling across direct hires, quotes, and special requests

### ✅ Duplicate Prevention
- Exact matching on customer/artisan/schedule/price for active bookings
- Prevents accidental double bookings from retries

### ✅ Flexible Payment Validation
- `skipPayment=true` query parameter for testing/admin bypass
- Automatic verification of pending Paystack transactions
- Graceful handling of payment gateway failures

### ✅ Comprehensive Notifications
- SMS and email notifications for artisans on booking creation
- Real-time notifications for status changes
- Customer notifications for completions and rejections

### ✅ Robust Error Handling
- Detailed error messages with actionable guidance
- Fallback mechanisms for payment gateway failures
- Transaction state validation to prevent double processing

## Environment Variables
- `PAYSTACK_SECRET_KEY`: Required for payment processing
- `PAYSTACK_AUTO_PAYOUT`: Enable automatic transfers to artisan accounts
- `COMPANY_FEE_PCT`: Platform commission percentage
- `COMPANY_USER_ID`: User ID for company earnings wallet
