# Artisan Services - Visual Architecture

## System Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         RIJHUB MOBILE APP                                │
└──────────────────────────────────────────────────────────────────────────┘

                              MY SERVICE PAGE
                            (User configures)
                                  │
                                  ↓
                          Backend API Server
                      GET /api/artisan-services/me
                                  │
                    ┌─────────────┴──────────────┐
                    │                            │
                    ↓                            ↓
            ┌───────────────┐        ┌────────────────────┐
            │ ArtisanService│        │ Nested services[]  │
            │    Document   │        │ - subCategoryId    │
            │ _id: xxxxx    │        │ - name             │
            │ categoryId:   │        │ - price            │
            │ services: []  │        │ - currency         │
            └───────────────┘        └────────────────────┘
                    │
                    ↓
        ┌──────────────────────────┐
        │   MyServiceService       │
        │  fetchMyServices()       │
        │  - Makes API call        │
        │  - Parses response       │
        │  - Returns flattened     │
        └──────────────────────────┘
                    │
                    ↓
┌────────────────────────────────────────────────────────┐
│        ARTISAN DETAIL PAGE                             │
│                                                        │
│  _loadArtisanServices()                               │
│  ├─ Fetch services via MyServiceService               │
│  ├─ Parse nested structure                            │
│  ├─ Store in _artisanServices                         │
│  └─ Cache in artisan['_artisanServices']              │
│                                                        │
│  Display:                                              │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐  │
│  │ Residential  │ │ Commercial   │ │ Industrial   │  │
│  │  Plumbing    │ │  Plumbing    │ │  Plumbing    │  │
│  └──────────────┘ └──────────────┘ └──────────────┘  │
│        (Service Pills)                                 │
└────────────────────────────────────────────────────────┘
                    │
        ┌───────────┼───────────┬─────────────┐
        │           │           │             │
        ↓           ↓           ↓             ↓
   ┌────────┐ ┌─────────┐ ┌──────────┐ ┌──────────┐
   │ Home   │ │ Search  │ │ Discover │ │ Booking  │
   │ Page   │ │  Page   │ │  Page    │ │  Sheet   │
   │        │ │         │ │          │ │          │
   │SERVICE │ │SERVICE  │ │SERVICES  │ │SERVICES  │
   │ BADGE  │ │BADGE    │ │ CHIPS    │ │ SELECTED │
   └────────┘ └─────────┘ └──────────┘ └──────────┘
```

---

## Data Flow - Sequence Diagram

```
User              App              Backend         Services
─────────────────────────────────────────────────────────────

1. Tap artisan
  │
  ├─→ Navigate to DetailPage
      │
      └─→ initState()
          ├─→ _loadArtisanServices()
          │   │
          │   ├─→ MyServiceService.fetchMyServices()
          │   │   │
          │   │   └─→ GET /api/artisan-services/me
          │   │       │
          │   │       ← Returns: [{ _id, categoryId, services: [...] }]
          │   │
          │   ├─→ Parse nested services array
          │   │   ├─ Extract subCategoryId
          │   │   ├─ Extract subCategoryName ← DISPLAYED
          │   │   ├─ Extract price
          │   │   └─ Extract currency
          │   │
          │   ├─→ setState(_artisanServices = [...])
          │   │
          │   └─→ artisan['_artisanServices'] = [...] ← CACHE
          │
          └─→ UI Updates with services
              ├─ Service pill 1
              ├─ Service pill 2
              └─ Service pill 3

2. Navigate to home/discover/search
  │
  ├─→ ListPage._buildCard(artisan)
  │   │
  │   ├─→ Check artisan['_artisanServices']
  │   │   ├─ If exists → Extract service names
  │   │   └─ If null → Fall back to trade field
  │   │
  │   ├─→ setState() with service names
  │   │
  │   └─→ UI Updates with service badge/chip

3. User books service
  │
  ├─→ Show hire sheet
  │   │
  │   └─→ Display selected services from booking
```

---

## State Management - Detail Page

```
┌─────────────────────────────────────────┐
│  ArtisanDetailPageState                 │
├─────────────────────────────────────────┤
│                                         │
│  Map<String, dynamic>? _artisanData     │
│  ├─ name                               │
│  ├─ bio                                │
│  ├─ location                           │
│  └─ _artisanServices ← NEW             │
│      └─ [                              │
│          {                             │
│            subCategoryName: String,    │
│            price: num,                 │
│            currency: String            │
│          },                            │
│          ...                           │
│        ]                               │
│                                         │
│  List<Map> _artisanServices            │
│  └─ Local state for UI display         │
│                                         │
│  bool _loadingServices                 │
│  └─ Loading indicator state            │
│                                         │
└─────────────────────────────────────────┘
```

---

## UI Display Hierarchy

```
ARTISAN DETAIL PAGE
├─ Profile Header
│  ├─ Avatar
│  ├─ Name + Verified Badge
│  ├─ Services Pills ← NEW
│  │  ├─ Service 1 (name in pill)
│  │  ├─ Service 2 (name in pill)
│  │  └─ Service 3 (name in pill)
│  ├─ Rating Stars
│  └─ Reviews Count
│
├─ Book Now Button
│
├─ About Section
│
├─ Information Section
│  ├─ Location
│  ├─ Experience
│  └─ Service Charge
│
└─ Reviews Section


HOME PAGE - ARTISAN CARD
├─ Avatar
├─ Info Column
│  ├─ Name + Verified
│  ├─ Rating Stars
│  └─ Service Pill ← FIRST SERVICE
└─ Book Now Button


DISCOVER PAGE - ARTISAN CARD
├─ Avatar with Rating
├─ Info Column
│  ├─ Name + Rating
│  ├─ Location
│  └─ Service Chips ← UP TO 3
└─ View Button


SEARCH PAGE - ARTISAN CARD
├─ Avatar
├─ Info Column
│  ├─ Name + Rating + Reviews
│  ├─ Location
│  └─ Service Badges ← UP TO 3
└─ View Button
```

---

## Class Relationships

```
┌────────────────────────────────┐
│   MyServiceService             │
├────────────────────────────────┤
│ + fetchMyServices()            │
│   → List<Map<String, dynamic>> │
└────────────────────────────────┘
          ↑
          │ uses
          │
┌────────────────────────────────┐
│ ArtisanDetailPageWidget        │
├────────────────────────────────┤
│ - _artisanServices: List       │
│ - _loadingServices: bool       │
├────────────────────────────────┤
│ + _loadArtisanServices()       │
│ + _buildServicePill()          │
│ + build()                      │
└────────────────────────────────┘
          ↓
    passes artisan object to:
          ↓
┌─────────────────────────────────┐
│ HomePageWidget._buildArtisanCard│
├─────────────────────────────────┤
│ uses artisan['_artisanServices] │
│ displays service in badge       │
└─────────────────────────────────┘

┌─────────────────────────────────┐
│ DiscoverPageWidget._tradesList()│
├─────────────────────────────────┤
│ extracts from _artisanServices  │
│ returns List<String> of names   │
└─────────────────────────────────┘

┌─────────────────────────────────┐
│ SearchPageWidget._buildArtisanC │
├─────────────────────────────────┤
│ uses artisan['_artisanServices] │
│ displays services as badges     │
└─────────────────────────────────┘
```

---

## Fallback Logic Flow

```
Display Service Name?
│
├─ Check: artisan['_artisanServices'] exists?
│  │
│  ├─ YES → Extract subCategoryName from first service
│  │         ↓
│  │    "Residential Plumbing" ✓
│  │
│  └─ NO → Check: artisan['trade'] exists?
│      │
│      ├─ YES → Use trade field
│      │         ↓
│      │    "Plumber" ✓
│      │
│      └─ NO → Default string
│              ↓
│         "Service" ✓
```

---

## Loading States

```
                    Start
                      ↓
    ┌─────────────────────────────┐
    │ _loadingServices = true      │
    │ Show: "Loading services..." │
    └──────────┬──────────────────┘
               ↓
    ┌─────────────────────────────┐
    │ Fetch from API              │
    │ (async operation)           │
    └──────────┬──────────────────┘
               │
        ┌──────┴──────┐
        │             │
    ✓ Success    ✗ Failed
        │             │
        ↓             ↓
    ┌──────────┐  ┌─────────────┐
    │ Parse    │  │ Fallback:   │
    │ Data     │  │ Show trade  │
    └────┬─────┘  └─────────────┘
         │
         ↓
    ┌──────────────────────────┐
    │ setState()               │
    │ _artisanServices = [...]│
    │ _loadingServices = false│
    └────┬─────────────────────┘
         │
         ↓
    ┌──────────────────────────┐
    │ UI Updates               │
    │ Show service pills       │
    └──────────────────────────┘
```

---

## Cache Propagation

```
Detail Page               List Pages
     │                        │
     ├─ Load services         │
     │  from API              │
     │                        │
     ├─ Parse data            │
     │                        │
     ├─ Store in              │
     │  _artisanServices      │
     │                        │
     ├─ Cache in              │
     │  artisan object ───────┼──→ Received in
     │  ['_artisanServices']  │    home/discover/
     │                        │    search pages
     │                        │
     │                        ├─ Check for cache
     │                        │
     │                        ├─ If found: Use
     │                        │  service names
     │                        │
     │                        └─ If not: Fall
     │                           back to trade
```

---

## Module Dependencies

```
┌─────────────────────────────────────┐
│ lib/services/my_service_service.dart│
│                                     │
│ MyServiceService                    │
│ └─ fetchMyServices(context)         │
│    └─ Calls backend API             │
│       Returns parsed services       │
└──────────────────┬──────────────────┘
                   │
                   ↓
┌─────────────────────────────────────┐
│ lib/pages/artisan_detail_page/      │
│ artisan_detail_page_widget.dart     │
│                                     │
│ _loadArtisanServices()              │
│ └─ Uses MyServiceService            │
│    └─ Stores in state               │
│       └─ Caches in artisan object   │
└──────────────────┬──────────────────┘
                   │
        ┌──────────┼──────────┬────────────┐
        │          │          │            │
        ↓          ↓          ↓            ↓
   ┌────────┐ ┌──────────┐ ┌────────┐ ┌─────────┐
   │ Home   │ │Discover  │ │Search  │ │Booking  │
   │Page    │ │Page      │ │Page    │ │Sheet    │
   └────────┘ └──────────┘ └────────┘ └─────────┘
```

---

## Performance Considerations

```
Parallel Loading
───────────────
Time: 0ms
  │
  ├─→ Fetch Artisan Data
  │   └─ 500-1000ms
  │
  ├─→ Fetch Reviews (parallel)
  │   └─ 500-1000ms
  │
  └─→ Fetch Services (parallel) ← NEW
      └─ 500-1000ms

Total: ~1000ms (parallel)
       instead of 1500-3000ms (sequential)

List Pages
──────────
- No additional API calls needed
- Services already in artisan object
- ~0-10ms additional processing
```

---

## API Response Structure

```json
GET /api/artisan-services/me

{
  "success": true,
  "data": [
    {
      "_id": "643e8a9f5c1234567890abcd",
      "categoryId": {
        "_id": "643e8a9f5c1234567890abcd",
        "name": "Plumbing"
      },
      "services": [
        {
          "subCategoryId": {
            "_id": "643e8a9f5c1234567890abce",
            "name": "Residential Plumbing"
          },
          "name": "Residential Plumbing",
          "price": 50000,
          "currency": "NGN"
        },
        {
          "subCategoryId": {
            "_id": "643e8a9f5c1234567890abcf",
            "name": "Commercial Plumbing"
          },
          "name": "Commercial Plumbing",
          "price": 75000,
          "currency": "NGN"
        }
      ]
    }
  ]
}
```

---

**Last Updated**: March 6, 2026
**Version**: 1.0
**Status**: Production Ready ✅

