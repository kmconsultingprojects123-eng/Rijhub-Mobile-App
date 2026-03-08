import 'package:flutter/material.dart';
import 'api_error_handler.dart';
import '../api_config.dart';
import 'artist_service.dart';

class MyServiceService {
  // Use JobCategory and JobSubCategory endpoints as documented in API docs
  static final String _base = API_BASE_URL; // e.g. https://api.example.com

  // Note: service CRUD endpoints are not present in API docs. Keep these disabled
  // by default. Set `MyServiceService.endpointsEnabled = true` if you have a
  // backend endpoint and update the URLs below accordingly.
  // Enable endpoints so that service creations/updates/deletes are sent to the server.
  // If you need to test offline/local-only behavior, set this to false or override
  // via runtime configuration before using the service.
  static bool endpointsEnabled = true;

  // Updated to match artisan_services.md
  // GET /api/artisan-services/me — list authenticated artisan's current offerings
  static final String listEndpoint = '$_base/api/artisan-services/me';
  // POST /api/artisan-services — create or update artisan offerings for a category
  static final String createEndpoint = '$_base/api/artisan-services';
  // PUT /api/artisan-services/:id — update an ArtisanService entry
  static final String updateEndpoint = '$_base/api/artisan-services'; // PUT to /:id
  // DELETE /api/artisan-services/:id — remove (soft-delete)
  static final String deleteEndpoint = '$_base/api/artisan-services'; // DELETE to /:id

  // Official category endpoints per docs
  static final String categoriesEndpoint = '$_base/api/job-categories';
  static final String jobSubcategoriesEndpoint = '$_base/api/job-subcategories';

  final ApiClient _client = ApiClient();

  Future<ApiResponse> fetchMyServices({BuildContext? context}) async {
    if (!endpointsEnabled) {
      return ApiResponse(ok: false, message: 'Service endpoints not configured', data: null);
    }
    return await _client.safeGet(listEndpoint, context: context);
  }

  Future<ApiResponse> createService(Map<String, dynamic> body, {BuildContext? context}) async {
    if (!endpointsEnabled) {
      return ApiResponse(ok: false, message: 'Service endpoints not configured', data: null);
    }
    return await _client.safePost(createEndpoint, body: body, context: context);
  }

  Future<ApiResponse> updateService(String id, Map<String, dynamic> body, {BuildContext? context}) async {
    if (!endpointsEnabled) {
      return ApiResponse(ok: false, message: 'Service endpoints not configured', data: null);
    }
    final url = '$updateEndpoint/$id';
    return await _client.safePut(url, body: body, context: context);
  }

  Future<ApiResponse> deleteService(String id, {BuildContext? context}) async {
    if (!endpointsEnabled) {
      return ApiResponse(ok: false, message: 'Service endpoints not configured', data: null);
    }
    // Backend expects the ArtisanService document id; callers sometimes pass a
    // composite id like '<artisanServiceId>_<subCategoryId>'. Normalize by
    // using the first segment when an underscore is present.
    final sanitizedId = (id.contains('_') ? id.split('_').first : id);
    final url = '$deleteEndpoint/$sanitizedId';
    return await _client.safeDelete(url, context: context);
  }

  /// Fetch job categories. Pass includeSubcategories=true to receive nested children.
  Future<ApiResponse> fetchCategories({BuildContext? context, bool includeSubcategories = true}) async {
    final url = includeSubcategories ? '$categoriesEndpoint?includeSubcategories=true' : categoriesEndpoint;
    return await _client.safeGet(url, context: context);
  }

  /// Fetch job subcategories directly (optionally filter by categoryId)
  Future<ApiResponse> fetchSubcategories({BuildContext? context, String? categoryId}) async {
    var url = jobSubcategoriesEndpoint;
    if (categoryId != null && categoryId.isNotEmpty) {
      url = '$jobSubcategoriesEndpoint?categoryId=$categoryId';
    }
    return await _client.safeGet(url, context: context);
  }

  /// Fetch artisan services for a specific artisan. Returns ApiResponse with data as a List or null on failure.
  Future<ApiResponse> fetchArtisanServices(String artisanId) async {
    try {
      // Delegate to ArtistService which already contains a robust fetch implementation
      final list = await ArtistService.fetchArtisanServices(artisanId);
      return ApiResponse(ok: true, statusCode: 200, data: list, message: 'OK');
    } catch (e) {
      return ApiErrorHandler.fromException(e);
    }
  }

  /// Normalize various API shapes into a flat List<Map<String,dynamic>> where each
  /// entry represents a single sub-service (with price, currency, category/subcategory ids).
  static List<Map<String, dynamic>> flattenArtisanServices(dynamic data) {
    final List<Map<String, dynamic>> flattened = [];

    try {
      List<dynamic> docs = [];
      if (data is List) {
        docs = data;
      } else if (data is Map && data['data'] is List) {
        docs = List<dynamic>.from(data['data']);
      } else if (data is Map && data['items'] is List) {
        docs = List<dynamic>.from(data['items']);
      } else if (data is Map) {
        // Single document
        docs = [data];
      }

      for (final docRaw in docs) {
        if (docRaw == null || docRaw is! Map) continue;
        final doc = Map<String, dynamic>.from(docRaw.cast<String, dynamic>());
        final artisanServiceId = (doc['_id'] ?? doc['id'])?.toString();

        // Normalize category which may be an id or an object
        final dynamic categoryRaw = doc['categoryId'] ?? doc['mainCategory'] ?? doc['category'];
        String? categoryId;
        String? categoryName = doc['categoryName'] ?? doc['name'];
        if (categoryRaw is Map) {
          categoryId = (categoryRaw['_id'] ?? categoryRaw['id'])?.toString();
          categoryName = categoryName ?? (categoryRaw['name'] ?? categoryRaw['title'])?.toString();
        } else {
          categoryId = categoryRaw?.toString();
        }

        final servicesArr = doc['services'] ?? doc['serviceList'] ?? doc['items'];
        if (servicesArr is List && servicesArr.isNotEmpty) {
          for (final s in servicesArr) {
            if (s == null || s is! Map) continue;
            final sub = Map<String, dynamic>.from(s.cast<String, dynamic>());

            final dynamic subRaw = sub['subCategoryId'] ?? sub['sub_category_id'] ?? sub['_id'] ?? sub['id'];
            String? subId;
            String? subName = (sub['name'] ?? sub['title'] ?? sub['label'])?.toString();
            if (subRaw is Map) {
              subId = (subRaw['_id'] ?? subRaw['id'])?.toString();
              subName = subName ?? (subRaw['name'] ?? subRaw['title'])?.toString();
            } else {
              subId = subRaw?.toString();
            }

            // Parse price
            num price = 0;
            final priceValue = sub['price'] ?? sub['amount'] ?? sub['unitPrice'] ?? sub['rate'] ?? 0;
            if (priceValue is num) price = priceValue;
            else if (priceValue is String) price = num.tryParse(priceValue) ?? 0;

            flattened.add({
              'id': '${artisanServiceId ?? ''}_${subId ?? ''}',
              'artisanServiceId': artisanServiceId,
              'categoryId': categoryId,
              'subCategoryId': subId,
              'serviceEntryId': (sub['_id'] ?? sub['id'])?.toString(),
              'price': price,
              'currency': sub['currency'] ?? 'NGN',
              'categoryName': categoryName,
              'subCategoryName': subName,
              'raw': sub,
            });
          }
        } else {
          // No nested services — maybe already a flat list entry
          flattened.add(Map<String, dynamic>.from(doc));
        }
      }
    } catch (_) {
      // ignore and return whatever we could parse
    }

    return flattened;
  }
}
