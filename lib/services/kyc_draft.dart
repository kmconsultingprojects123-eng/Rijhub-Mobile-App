import 'user_service.dart';

// Simple in-memory draft storage for the multi-step KYC flow.
// This keeps selected file paths and form values across pages before final submit.

class KycDraft {
  // Fields kept for the streamlined 3-step KYC
  // Step 1: Business / Location
  String? businessName;
  String? country;
  String? state;
  String? lga;

  // Step 2: Identity / Photo (paths stored locally until submit)
  String? profilePhotoPath;
  String? idFrontPath;
  String? idBackPath;
  String? idType;

  // Helper aliases and kept lists
  // profileImage maps to profilePhotoPath
  String? get profileImage => profilePhotoPath;
  set profileImage(String? v) => profilePhotoPath = v;

  // Id uploads map to idFrontPath / idBackPath
  String? get idUploadFront => idFrontPath;
  set idUploadFront(String? v) => idFrontPath = v;

  String? get idUploadBack => idBackPath;
  set idUploadBack(String? v) => idBackPath = v;

  // serviceCategory (singular) maps to serviceCategories
  List<String>? serviceCategories;
  List<String>? get serviceCategory => serviceCategories;
  set serviceCategory(List<String>? v) => serviceCategories = v;

  String? yearsExperience;

  // Agreement checkbox
  bool agreementAccepted = false;

  // If true, the KYC flow should attempt to auto-submit when the user returns
  // after signing in. This is used to resume a pending KYC submission.
  bool resumeSubmission = false;

  /// Populate any empty draft fields using the authenticated user's profile
  /// fetched from the backend. Only populates business/location fields.
  Future<void> populateFromProfile() async {
    try {
      final profile = await UserService.getProfile();
      if (profile == null) return;
      country ??= (profile['country'] ?? 'Nigeria')?.toString();
      state ??= (profile['state'] ?? profile['region'])?.toString();
      lga ??= (profile['lga'] ?? profile['localGovernment'] ?? '')?.toString();
      // try to populate businessName if available
      businessName ??= (profile['businessName'] ?? profile['company'] ?? profile['organisation'])?.toString();
    } catch (_) {
      // ignore errors — best-effort population
    }
  }

  // Singleton
  static final KycDraft _instance = KycDraft._internal();
  factory KycDraft() => _instance;
  KycDraft._internal();

  void clear() {
    // Clear only the streamlined KYC fields
    profilePhotoPath = null;
    idFrontPath = null;
    idBackPath = null;
    idType = null;
    businessName = null;
    serviceCategories = null;
    yearsExperience = null;
    country = null;
    state = null;
    lga = null;
    // reset new aliases/flags
    agreementAccepted = false;
  }

  /// Build a submission-ready map of textual fields (keys match the
  /// streamlined field names you provided). Values are strings; lists are
  /// joined where appropriate (comma separated). This map can be passed to
  /// the KYC submit helpers as the form fields.
  Map<String, String> toSubmissionFields() {
    return {
      // textual fields expected by backend
      'businessName': businessName ?? '',
      'country': country ?? 'Nigeria',
      'state': state ?? '',
      'lga': lga ?? '',
      // serviceCategory stored as a single string; if multiple categories
      // were selected we join them with commas so backend still receives a
      // readable value (you can change to pick the first item if needed).
      'serviceCategory': (serviceCategories ?? []).join(','),
      // yearsExperience should be a number on the backend; send as numeric
      // string and default to '0' when absent or invalid.
      'yearsExperience': (() {
        if (yearsExperience == null) return '0';
        final parsed = int.tryParse(yearsExperience!.trim());
        return parsed?.toString() ?? '0';
      })(),
      'IdType': idType ?? '',
    };
  }

  /// Build a submission-ready map of file paths keyed by the field names
  /// your backend expects. Values are lists of paths (may be empty).
  Map<String, List<String>> toSubmissionFilePaths() {
    final Map<String, List<String>> out = {};
    if (profilePhotoPath != null && profilePhotoPath!.isNotEmpty) out['profileImage'] = [profilePhotoPath!];
    if (idFrontPath != null && idFrontPath!.isNotEmpty) out['IdUploadFront'] = [idFrontPath!];
    if (idBackPath != null && idBackPath!.isNotEmpty) out['IdUploadBack'] = [idBackPath!];
    return out;
  }
}
