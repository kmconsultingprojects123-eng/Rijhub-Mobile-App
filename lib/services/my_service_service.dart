import 'package:flutter/material.dart';
import 'api_error_handler.dart';
import '../api_config.dart';

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
}
