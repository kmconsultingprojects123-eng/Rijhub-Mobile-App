# Visual Architecture - Search Page Services

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         SEARCH PAGE                              │
│                                                                  │
│  User enters search term or selects trade filter                │
│              ↓                                                    │
│  _startSearch() called                                          │
│              ↓                                                    │
│  ArtistService.fetchArtisans() → List<Map<String, dynamic>>   │
│              ↓                                                    │
│  For each artisan: _buildArtisanCard(artisan)                 │
│              ↓                                                    │
│  Extract: name, location, rating, imageUrl, artisanId          │
│              ↓                                                    │
│  Call: _buildArtisanCardWithServices(...)                       │
│              ↓                                                    │
│  FutureBuilder<List<String>>                                    │
│              ↓                                                    │
│  _fetchArtisanServicesForCard(artisanId)                        │
│              ↓                                                    │
│  HTTP GET /api/artisan-services?artisanId=<id>                 │
│              ↓                                                    │
│  Parse JSON response                                             │
│              ↓                                                    │
│  Extract service names from nested structure                     │
│              ↓                                                    │
│  Return List<String> of service names                            │
│              ↓                                                    │
│  Display service pills in Wrap layout                            │
└─────────────────────────────────────────────────────────────────┘
```

## Component Hierarchy

```
SearchPageWidget (StatefulWidget)
│
├── AppBar
│   └── Search TextField
│
├── Filter Chips Row (Horizontal ScrollView)
│   └── _buildEnhancedFilterChip()
│
└── Results ListView
    └── For each artisan
        └── _buildArtisanCard(artisan)
            │
            ├── Extract artisan data
            │   ├── Name
            │   ├── Location
            │   ├── Rating
            │   ├── Image URL
            │   └── Artisan ID
            │
            └── _buildArtisanCardWithServices()
                │
                ├── Container (Card wrapper)
                │   ├── Row (Header)
                │   │   ├── Avatar
                │   │   ├── Name & Rating
                │   │   └── View Button
                │   │
                │   ├── Location Row (if not empty)
                │   │   ├── Location Icon
                │   │   └── Location Text
                │   │
                │   └── FutureBuilder<List<String>>
                │       │
                │       ├── future: _fetchArtisanServicesForCard(artisanId)
                │       │
                │       └── builder: (context, snapshot)
                │           │
                │           └── if (services.isNotEmpty)
                │               └── Wrap Layout
                │                   └── For each service (max 3)
                │                       └── Service Pill
                │                           └── Container
                │                               ├── Decoration (color, border)
                │                               └── Text (service name)
```

## Service Pill Structure

```
┌────────────────────────────────────┐
│        SERVICE PILL WIDGET          │
├────────────────────────────────────┤
│ Container                           │
│ ├── padding: 12px × 6px            │
│ ├── decoration:                     │
│ │   ├── color: tradeBadgeColor     │
│ │   ├── borderRadius: 12px         │
│ │   └── border: 1px solid          │
│ └── child:                          │
│     └── Text("Service Name")        │
│         ├── fontSize: 12px         │
│         ├── fontWeight: 500        │
│         ├── color: tradeTextColor  │
│         └── letterSpacing: -0.1    │
└────────────────────────────────────┘
```

## API Response Parsing Tree

```
HTTP Response (JSON)
│
├── [Option 1] Direct Array
│   └── [ArtisanService, ArtisanService, ...]
│
└── [Option 2] Wrapped Object
    └── { data: [ArtisanService, ...] }
        
        For each ArtisanService:
        └── {
            _id: "service-doc-id",
            artisanId: "artisan-id",
            categoryId: "category-id",
            services: [
                {
                    _id: "entry-id",
                    subCategoryId: {
                        _id: "subcat-id",
                        name: "Electrical Repairs"  ← EXTRACT
                    },
                    price: 50000,
                    currency: "NGN"
                },
                {
                    _id: "entry-id-2",
                    subCategoryId: {
                        _id: "subcat-id-2",
                        name: "Wiring Installation"  ← EXTRACT
                    },
                    price: 75000,
                    currency: "NGN"
                }
            ]
        }
            
        Extract all service names:
        └── ["Electrical Repairs", "Wiring Installation"]
            └── Display as pills (max 3)
```

## Service Name Extraction Logic

```
For each service in services array:
│
├── Try: service.subCategoryId.name
│   └── If exists and not empty → USE IT
│
├── Else try: service.subCategory.name
│   └── If exists and not empty → USE IT
│
├── Else try: service.sub.name
│   └── If exists and not empty → USE IT
│
├── Else try: service.name
│   └── If exists and not empty → USE IT
│
├── Else try: service.title
│   └── If exists and not empty → USE IT
│
├── Else try: service.label
│   └── If exists and not empty → USE IT
│
└── Else: SKIP this service (no name found)
```

## State Management Flow

```
┌─────────────────────────────────────┐
│    _SearchPageWidgetState           │
│                                     │
│ Properties:                         │
│  ├── _artisans: []                 │
│  ├── _isLoading: false             │
│  ├── _hasSearched: false           │
│  ├── _selectedTrade: null          │
│  └── _topServices: []              │
│                                     │
└─────────────────────────────────────┘
         ↓
    setState() when:
         │
    ┌────┴────┬─────────┬──────────┐
    │          │         │          │
  Search   Trade     Services   Error
  starts   selected  loaded     occurs
    │          │         │          │
    ↓          ↓         ↓          ↓
_artisans                         Cards
updated   _startSearch()          rebuild
             → _fetchArtisans()
```

## Responsive Breakpoints

```
┌─────────────────────────────────────────────────────────┐
│                    SCREEN SIZES                         │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Extra Small        Small         Medium       Large    │
│   < 360px         360-420px      420-768px    > 768px   │
│                                                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐ │
│  │[S1] [S2]│  │[S1] [S2] │  │[S1] [S2] │  │[S1][S2]│ │
│  │[S3]     │  │[S3]      │  │[S3]      │  │[S3][S4]│ │
│  │         │  │          │  │          │  │        │ │
│  │Spacing: │  │Spacing:  │  │Spacing:  │  │Spacing:│ │
│  │  6px    │  │  8px     │  │  8px     │  │  8px   │ │
│  └──────────┘  └──────────┘  └──────────┘  └────────┘ │
│                                                         │
└─────────────────────────────────────────────────────────┘

S1, S2, S3 = Service pills
```

## Theme Adaptation

```
┌──────────────────────────────────────────────────────┐
│                  LIGHT MODE                          │
├──────────────────────────────────────────────────────┤
│                                                      │
│  Card Background: White (#FFFFFF)                   │
│  Card Border: Light gray (#E5E7EB)                  │
│  Text Primary: Dark gray (#111827)                  │
│  Text Secondary: Medium gray (#6B7280)              │
│                                                      │
│  Service Pill:                                      │
│    ┌────────────────────┐                           │
│    │  Electrical        │  Background: #A20025@10%  │
│    │                    │  Border: #A20025@20%      │
│    │                    │  Text: #A20025 -10%      │
│    └────────────────────┘                           │
│                                                      │
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│                  DARK MODE                           │
├──────────────────────────────────────────────────────┤
│                                                      │
│  Card Background: Dark gray (#1F2937)               │
│  Card Border: Darker gray (#374151)                 │
│  Text Primary: White (#FFFFFF)                      │
│  Text Secondary: Light gray (#9CA3AF)               │
│                                                      │
│  Service Pill:                                      │
│    ┌────────────────────┐                           │
│    │  Electrical        │  Background: #A20025@20%  │
│    │                    │  Border: #A20025@20%      │
│    │                    │  Text: #A20025 +20%      │
│    └────────────────────┘                           │
│                                                      │
└──────────────────────────────────────────────────────┘
```

## Error Handling Flow

```
_fetchArtisanServicesForCard(artisanId)
│
├─ Input validation
│  └─ if (artisanId == null || isEmpty)
│     └─ return <String>[]  ✓
│
├─ API Request
│  ├─ timeout(8 seconds)
│  └─ catch(e)
│     └─ debugPrint() + return <String>[]  ✓
│
├─ Response Check
│  ├─ if (statusCode != 200)
│  │  └─ return <String>[]  ✓
│  └─ if (statusCode == 200)
│     └─ Continue parsing
│
├─ JSON Parsing
│  └─ try
│     ├─ jsonDecode(response.body)
│     └─ catch(e)
│        └─ return <String>[]  ✓
│
├─ Response Structure Check
│  ├─ if (body is Map && body['data'] is List)
│  │  └─ items = body['data']
│  ├─ else if (body is List)
│  │  └─ items = body
│  └─ else
│     └─ return <String>[]  ✓
│
├─ Service Extraction
│  └─ for each item
│     ├─ Type check: if (item is! Map)
│     │  └─ continue  ✓
│     ├─ Get services array
│     │  ├─ if (servicesArr is! List)
│     │  │  └─ continue  ✓
│     │  └─ if (servicesArr.isEmpty)
│     │     └─ continue  ✓
│     └─ Extract service names
│        ├─ if (serviceName == null || isEmpty)
│        │  └─ skip this service  ✓
│        └─ else
│           └─ add to flattened list  ✓
│
└─ Return results
   └─ return flattened  (may be empty)  ✓
```

## Performance Timeline

```
Time (ms)    Event
─────────────────────────────────────────────────────────
0            User performs search action
0-50         _startSearch() called
0-100        _buildArtisanCard() executes
100-150      _buildArtisanCardWithServices() executes
150-200      FutureBuilder widget created
200-300      HTTP request sent to /api/artisan-services
300-1000     Waiting for network response (typical)
1000-1500    JSON parsing
1500-2000    Service extraction
2000+        UI updates with services
             (Services displayed in pills)

Max timeout:  8000ms (if no response)
Typical:      1000-2000ms per artisan
Parallel:     All artisans load simultaneously
```

## Memory Layout (Single Card)

```
┌──────────────────────────────────────┐
│       Artisan Card Object            │
├──────────────────────────────────────┤
│ Base Card:           ~2 KB           │
│  ├── Widget tree     ~1 KB           │
│  └── Decorations     ~1 KB           │
│                                      │
│ Artisan Data:        ~1 KB           │
│  ├── Name            ~50 B           │
│  ├── Location        ~100 B          │
│  ├── Rating          ~16 B           │
│  └── Image Cache     ~500 B          │
│                                      │
│ Services Data:       ~200 B × N      │
│  └── Per service:    ~100-300 B      │
│      (3 services max)                │
│                                      │
│ Total per card:      ~5-10 KB        │
│                                      │
│ × 10 cards:          ~50-100 KB      │
└──────────────────────────────────────┘
```

---

## Integration Points

```
SearchPageWidget
├── Uses: ArtistService.fetchArtisans()
│   └── Returns List<Map<String, dynamic>>
│
├── Uses: _buildArtisanCard()
│   └── Returns Widget
│
├── Uses: _buildArtisanCardWithServices()
│   └── Returns Widget with FutureBuilder
│
└── Uses: _fetchArtisanServicesForCard()
    └── Returns Future<List<String>>
        └── Calls: GET /api/artisan-services?artisanId=<id>


Related Components:
├── ArtisanDetailPageWidget
│   └── Similar service fetching pattern
│
└── MyServicePageWidget
    └── Uses MyServiceService for authenticated artisan
```

---

**Last Updated:** March 6, 2026
**Status:** Complete & Documented ✅

