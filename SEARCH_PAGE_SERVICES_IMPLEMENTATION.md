# Search Page Artisan Services Implementation

## Overview

The Search Page now displays artisan services as interactive pills/badges on each artisan card. Services are dynamically fetched from the backend API and displayed in a clean, responsive format.

## Implementation Details

### 1. **Service Display on Search Cards**

Each artisan card in the search results now includes a "Services" section that displays up to 3 services offered by that artisan as styled pills/badges.

**Location in UI:**
- Position: Below the artisan location information
- Layout: Horizontal wrap layout with spacing
- Visual: Pill-shaped badges with primary color styling
- Responsive: Adapts to dark/light theme

**Code Implementation:**
```dart
// Services - from API
if (services.isNotEmpty) ...[
  const SizedBox(height: 16),
  Wrap(
    spacing: 8,
    runSpacing: 8,
    children: services.take(3).map((service) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: tradeBadgeColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _primaryColor.withAlpha((0.2 * 255).round()),
            width: 1,
          ),
        ),
        child: Text(
          service,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: tradeTextColor,
            letterSpacing: -0.1,
          ),
        ),
      );
    }).toList(),
  ),
],
```

### 2. **Service Fetching Method**

**Method:** `_fetchArtisanServicesForCard(String? artisanId)`

**Purpose:** Fetches the services offered by a specific artisan from the backend API.

**Endpoint:** `GET /api/artisan-services?artisanId=<artisanId>&limit=100`

**Response Handling:**

The method properly parses the nested response structure from the artisan-services endpoint:

1. **Handles wrapped and unwrapped responses:**
   ```dart
   // Handle both wrapped and unwrapped responses
   if (body is Map && body['data'] is List) {
     items = body['data'] as List<dynamic>;
   } else if (body is List) {
     items = body;
   }
   ```

2. **Extracts services from nested structure:**
   - Each item in the response is an `ArtisanService` document
   - Documents contain a `services` array
   - Each service object may have a nested `subCategoryId` (which can be an object or ID)
   - Service names are extracted from the subcategory object or direct fields

3. **Extracts service names from multiple possible keys:**
   ```dart
   // Try to get from subCategoryId (may be nested object)
   final subRaw = sub['subCategoryId'] ?? sub['subCategory'] ?? sub['sub'];
   if (subRaw is Map) {
     serviceName = (subRaw['name'] ?? subRaw['title'] ?? subRaw['label'])?.toString();
   }
   
   // Fallback to direct name fields
   serviceName ??= (sub['name'] ?? sub['title'] ?? sub['label'])?.toString();
   ```

### 3. **Integration with FutureBuilder**

The services are loaded asynchronously using `FutureBuilder`:

```dart
return FutureBuilder<List<String>>(
  future: _fetchArtisanServicesForCard(artisanId),
  builder: (context, snapshot) {
    List<String> services = <String>[];
    if (snapshot.hasData) {
      services = snapshot.data ?? <String>[];
    }
    // Build card with services
  },
);
```

**Benefits:**
- Non-blocking service loading
- Card renders immediately while services load
- Error handling with graceful fallback to empty list
- Timeout protection (8 seconds)

### 4. **Color Scheme (Dark/Light Mode Aware)**

The service pills adapt to the current theme:

**Light Mode:**
- Background: Primary color with 10% opacity
- Text: Primary color darkened by 10%
- Border: Primary color with 20% opacity

**Dark Mode:**
- Background: Primary color with 20% opacity
- Text: Primary color lightened by 20%
- Border: Primary color with 20% opacity

### 5. **Responsive Design**

- Maximum 3 services displayed (truncated with `.take(3)`)
- Horizontal wrap layout allows natural flow on different screen sizes
- Consistent spacing (8px between services, 8px between rows)
- Font size: 12px (optimized for small badges)
- Padding: 12px horizontal, 6px vertical

## API Response Structure

The endpoint returns an array of ArtisanService documents:

```json
[
  {
    "_id": "artisan-service-id",
    "artisanId": "artisan-id",
    "categoryId": "category-id",
    "services": [
      {
        "_id": "service-entry-id",
        "subCategoryId": {
          "_id": "subcategory-id",
          "name": "Service Name",
          "title": "Service Title"
        },
        "price": 50000,
        "currency": "NGN"
      },
      {
        "_id": "service-entry-id-2",
        "subCategoryId": {
          "_id": "subcategory-id-2",
          "name": "Another Service"
        },
        "price": 75000,
        "currency": "NGN"
      }
    ]
  }
]
```

## Error Handling

The method includes comprehensive error handling:

1. **Null/empty artisan ID check:**
   - Returns empty list if artisan ID is missing
   - Prevents unnecessary API calls

2. **Network timeout protection:**
   - 8-second timeout per request
   - Graceful fallback to empty services list

3. **Parsing error handling:**
   - Try-catch blocks protect against JSON parsing errors
   - Invalid responses are silently ignored
   - Debug logging available with `kDebugMode`

4. **Type safety:**
   - Explicit type checking for Map/List
   - Safe casting with `.cast<String, dynamic>()`
   - Null-coalescing operators for fallback values

## Testing Recommendations

1. **Test with multiple artisans:**
   - Artisan with many services (>3)
   - Artisan with few services (1-2)
   - Artisan with no services

2. **Test network scenarios:**
   - Slow connection (services load slowly)
   - Network timeout (services don't load)
   - Invalid responses (error handling)

3. **Test UI rendering:**
   - Service pills wrap correctly on small screens
   - Spacing and sizing look good
   - Dark mode colors are readable

4. **Test data consistency:**
   - Services from API match artisan's actual offerings
   - Service names display correctly
   - Maximum 3 services are shown

## Files Modified

- `/lib/pages/search_page/search_page_widget.dart`
  - Updated `_buildArtisanCard()` method
  - Updated `_buildArtisanCardWithServices()` method
  - Improved `_fetchArtisanServicesForCard()` method with proper response parsing

## Related Documentation

- [Artisan Services API Documentation](./artisan_services.md)
- [My Service Page Implementation](./lib/pages/profile/my_service_page.dart)
- [Artisan Detail Page Implementation](./lib/pages/artisan_detail_page/artisan_detail_page_widget.dart)

## Future Enhancements

1. **Service pricing display:** Show prices alongside service names
2. **Service filtering:** Filter search results by specific services
3. **Service details:** Click on service pill to view details
4. **Service ratings:** Show ratings for each service
5. **Service booking:** Direct booking from service pill

