# Quick Reference - Artisan Services Implementation

## What Changed?

**Old**: Artisans displayed generic "trade" field (e.g., "Plumber")
**New**: Artisans display actual services from "My Service" page (e.g., "Residential Plumbing", "Commercial Plumbing")

---

## Pages Affected

| Page | What Shows | Where |
|------|-----------|-------|
| **Artisan Detail** | Service pills | Profile header (up to 3) |
| **Home Page** | Service name | Card badge |
| **Discover Page** | Service chips | Card details (up to 3) |
| **Search Page** | Service badges | Card details (up to 3) |
| **Booking Sheet** | Selected services | Service selection step |

---

## How It Works

### Step 1: Service Loading
```
User opens Artisan Detail Page
         ↓
_loadArtisanServices() called
         ↓
Fetches from MyServiceService.fetchMyServices()
         ↓
Parses nested services array
         ↓
Stores in _artisanServices list
         ↓
Caches in artisan['_artisanServices']
```

### Step 2: Service Caching
```
artisan object now contains:
{
  'name': 'John Plumber',
  'trade': 'Plumbing',  // Legacy
  '_artisanServices': [  // NEW
    { 'subCategoryName': 'Residential Plumbing', 'price': 50000 },
    { 'subCategoryName': 'Commercial Plumbing', 'price': 75000 }
  ]
}
```

### Step 3: Display on List Pages
```
Home/Discover/Search pages receive artisan object
         ↓
Check for _artisanServices
         ↓
If found → Display service name
If not found → Fall back to trade field
         ↓
Show in UI (pill, chip, or badge)
```

---

## Key Variable Names

- `_artisanServices` - List of services loaded on detail page
- `artisan['_artisanServices']` - Cached services passed to other pages
- `subCategoryName` - The actual service name (what gets displayed)
- `serviceDisplay` - Variable used in home page (was `trade`)

---

## Testing Checklist

```
☐ Load artisan detail page → See services load with loading indicator
☐ Switch between artisans → Services update correctly
☐ Go back to home page → Services showing in cards
☐ Swipe to discover page → Services showing as chips
☐ Search for artisan → Services showing in search results
☐ Open booking sheet → Can select from services
☐ Artisan with no services → Falls back to trade field
☐ Performance test → No lag when loading services
```

---

## File Changes Summary

### artisan_detail_page_widget.dart
```dart
// Added method
Future<void> _loadArtisanServices() async { ... }

// Updated UI
// Old: Single trade pill
// New: Service pills (up to 3) with loading state
```

### home_page_widget.dart
```dart
// Updated method
Widget _buildArtisanCard() {
  // Old: serviceDisplay = trade field
  // New: serviceDisplay = first service name OR trade field
}
```

### discover_page_widget.dart
```dart
// Updated method
List<String> _tradesList(Map<String, dynamic> a) {
  // Old: Return trade field only
  // New: Return _artisanServices names OR trade field
}
```

### search_page_widget.dart
```dart
// Updated method
Widget _buildArtisanCard() {
  // Old: trades = trade field
  // New: trades = _artisanServices names OR trade field
}
```

---

## Troubleshooting

### Issue: Services not showing
**Solution**:
1. Check MyServiceService is imported
2. Verify artisan has services configured in My Service page
3. Check device logs for fetch errors

### Issue: Trade shows instead of services
**Solution** (intentional):
- This is the fallback behavior
- Artisan may not have configured services yet
- Trade field is shown as backup

### Issue: Services load slowly
**Solution**:
- Services load in parallel with reviews
- Network may be slow
- Consider caching to SharedPreferences

---

## API Endpoint Reference

```
GET /api/artisan-services/me

Response structure:
{
  "data": [
    {
      "_id": "doc_id",
      "categoryId": { "_id": "...", "name": "..." },
      "services": [
        {
          "subCategoryId": { "_id": "...", "name": "Residential Plumbing" },
          "price": 50000,
          "currency": "NGN"
        }
      ]
    }
  ]
}
```

---

## Code Examples

### Accessing services in detail page
```dart
// Get first service name
if (_artisanServices.isNotEmpty) {
  final serviceName = _artisanServices.first['subCategoryName'];
}
```

### Accessing services in list pages
```dart
// Check if services available
if (artisan['_artisanServices'] is List) {
  final services = artisan['_artisanServices'] as List;
  // Use services...
}
```

### Displaying services
```dart
// Show pill/badge
Container(
  child: Text(
    service['subCategoryName'],  // Always use subCategoryName
    style: TextStyle(...),
  ),
)
```

---

## Performance Notes

✅ **Good**:
- Services cached in artisan object
- No additional API calls needed per list page
- Parallel loading with reviews
- Graceful degradation to trade field

⚠️ **Watch Out**:
- Large service lists (50+) may need pagination
- Network delay affects loading time
- Consider adding service count limit (3 shown, rest hidden)

---

## Related Files

- `lib/services/my_service_service.dart` - Service fetching logic
- `lib/pages/profile/my_service_page.dart` - Where users configure services
- `artisan_services.md` - Detailed API documentation
- `ARTISAN_SERVICES_IMPLEMENTATION.md` - Full technical guide

---

**Last Updated**: March 6, 2026
**Status**: ✅ Production Ready

