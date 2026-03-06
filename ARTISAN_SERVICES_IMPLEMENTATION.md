# Artisan Services Implementation Guide

## Overview
This document explains the changes made to display **artisan services from the "My Service" page** instead of the generic "trade" field across the Rijhub app.

## Problem Statement
Previously, artisan profiles displayed a single "trade" field (e.g., "Plumber", "Electrician") regardless of which specific services the artisan had configured in their "My Service" page. This did not accurately reflect the artisan's actual service offerings.

## Solution
Artisans now display their actual configured services (from the My Service page) as service pills/badges on their profile and in list views throughout the app.

---

## Technical Implementation

### 1. **Data Flow Architecture**

```
My Service Page (Backend)
        ↓
ArtisanService Documents
  - _id (document ID)
  - categoryId
  - services: [
      { subCategoryId, name, price, currency }
    ]
        ↓
MyServiceService.fetchMyServices()
        ↓
Artisan Detail Page
  - Fetches services via _loadArtisanServices()
  - Stores in _artisanServices list
  - Caches in artisan object as '_artisanServices'
        ↓
List Pages (Home, Discover, Search)
  - Receive artisan with cached '_artisanServices'
  - Display as service pills/badges
```

### 2. **Key Changes by File**

#### **lib/pages/artisan_detail_page/artisan_detail_page_widget.dart**

**New Method: `_loadArtisanServices()`**
- Fetches artisan services using `MyServiceService.fetchMyServices()`
- Parses nested service data structure
- Extracts service names, prices, and IDs
- Stores locally in `_artisanServices` state
- **Important**: Caches services in artisan data as `_artisanServices` for passing to other pages

**Updated UI**:
- Replaced single "trade" pill with up to 3 service pills
- Shows `Loading services...` while fetching
- Falls back to trade if no services available
- Each service displays: `subCategoryName` (the actual service name)

**Data Structure**:
```dart
_artisanServices = [
  {
    'id': '${docId}_${subId}',
    'artisanServiceId': docId,
    'categoryId': categoryId,
    'subCategoryId': subId,
    'serviceEntryId': entryId,
    'price': amount,
    'currency': 'NGN',
    'categoryName': categoryName,
    'subCategoryName': 'Service Name'  // ← Displayed in pill
  },
  ...
]
```

#### **lib/pages/home_page/home_page_widget.dart**

**Updated: `_buildArtisanCard()` method**
- Replaced `trade` extraction with service extraction
- First checks for `_artisanServices` in artisan object
- Falls back to legacy "trade" field if no services
- Displays first service in the pill
- Variable renamed from `trade` to `serviceDisplay`

```dart
// New logic
if (artisan['_artisanServices'] is List) {
  // Use cached services
  serviceDisplay = artisanServices.first['subCategoryName'];
} else {
  // Fallback to trade
  serviceDisplay = extractTradeField(artisan);
}
```

#### **lib/pages/discover_page/discover_page_widget.dart**

**Updated: `_tradesList()` method**
- Checks for `_artisanServices` first
- Extracts `subCategoryName` from each service
- Falls back to trade field logic if no services
- Returns up to 3 service names as list

```dart
if (a['_artisanServices'] is List) {
  return (a['_artisanServices'] as List)
      .map((e) => e is Map ? e['subCategoryName'] : '')
      .where((s) => s.isNotEmpty)
      .toList();
}
```

#### **lib/pages/search_page/search_page_widget.dart**

**Updated: `_buildArtisanCard()` method**
- Same pattern as home_page
- Checks for cached `_artisanServices`
- Falls back to trade extraction
- Displays services as styled badges

---

## Service Data Flow Explained

### API Endpoint: `/api/artisan-services/me`

Returns structure like:
```json
{
  "data": [
    {
      "_id": "artisan-service-doc-id",
      "categoryId": { "_id": "category-id", "name": "Plumbing" },
      "services": [
        {
          "subCategoryId": { "_id": "sub-id", "name": "Residential Plumbing" },
          "name": "Residential Plumbing",
          "price": 50000,
          "currency": "NGN"
        },
        {
          "subCategoryId": { "_id": "sub-id-2", "name": "Commercial Plumbing" },
          "name": "Commercial Plumbing",
          "price": 75000,
          "currency": "NGN"
        }
      ]
    }
  ]
}
```

### Processing Steps

1. **Fetch**: `MyServiceService.fetchMyServices()` retrieves the above
2. **Flatten**: Loop through documents → loop through nested services
3. **Extract**: For each service:
   ```dart
   {
     'subCategoryId': service.subCategoryId._id,
     'subCategoryName': service.subCategoryId.name,  // ← Used for display
     'price': service.price,
     'currency': service.currency
   }
   ```
4. **Store**: In `_artisanServices` list
5. **Cache**: Attach to artisan object as `_artisanServices`
6. **Pass**: When navigating to detail page or other views

---

## Fallback Strategy

The implementation includes a robust fallback system:

```
Priority Order:
1. _artisanServices (cached from My Service page)  ← NEW
2. trade field (legacy, from artisan document)      ← FALLBACK
3. "Service" (hardcoded default)                    ← LAST RESORT
```

This ensures:
- **New artisans** with configured services see accurate data
- **Legacy artisans** without services still see their trade
- **No blank states** - always displays something

---

## Pages Updated

| Page | File | Change |
|------|------|--------|
| Artisan Detail | `artisan_detail_page_widget.dart` | Added service fetching and display |
| Home | `home_page_widget.dart` | Updated card to show services |
| Discover | `discover_page_widget.dart` | Updated trade list method |
| Search | `search_page_widget.dart` | Updated card to show services |

---

## Testing Checklist

- [ ] Load artisan detail page → services display in pills
- [ ] Services load in parallel with reviews
- [ ] Fallback to trade if services unavailable
- [ ] Home page shows services in card
- [ ] Discover page shows up to 3 services
- [ ] Search results show services
- [ ] Booking sheet uses correct services
- [ ] Performance not impacted by parallel service loading

---

## Future Enhancements

1. **Caching**: Could cache services in SharedPreferences for offline access
2. **Pagination**: If artisan has >10 services, add "View All" link
3. **Sorting**: Sort services by popularity or recent bookings
4. **Filtering**: Filter available services by location or rating
5. **Analytics**: Track which services are most viewed/booked

---

## Notes for Developers

- **Key Variable**: `_artisanServices` - don't rename without updating all references
- **Cache Key**: `_artisanServices` on artisan map - reserved for this feature
- **Service Names**: Always use `subCategoryName` for display (not raw object)
- **Price**: Already available in service data, can be used for feature comparisons
- **Loading State**: Service loading happens in parallel with review loading for better UX

---

## References

- **My Service Page**: `/lib/pages/profile/my_service_page.dart`
- **MyServiceService**: `/lib/services/my_service_service.dart`
- **ArtisanDetailPage**: `/lib/pages/artisan_detail_page/artisan_detail_page_widget.dart`
- **API Docs**: See `/API_DOCS (2).md` for endpoint details

