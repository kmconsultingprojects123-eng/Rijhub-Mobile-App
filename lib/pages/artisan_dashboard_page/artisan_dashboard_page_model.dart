import '/flutter_flow/flutter_flow_util.dart';
import 'artisan_dashboard_page_widget.dart' show ArtisanDashboardPageWidget;
import 'package:flutter/material.dart';

class ArtisanDashboardPageModel
    extends FlutterFlowModel<ArtisanDashboardPageWidget> {
  ///  State fields for stateful widgets in this page.

  // State field(s) for Switch widget.
  bool? switchValue;
  // State field(s) for RatingBar widget.
  double? ratingBarValue;
  // Fetched user display name
  String? displayName;
  // profile image url or local path
  dynamic profileImageUrl;
  // KYC verified flag
  bool isVerified = false;
  // Raw profile map fetched from backend
  Map<String, dynamic>? profileData;
  // Analytics placeholder (jobsCompleted, reviews, earnings)
  Map<String, dynamic> analytics = {'jobsCompleted': 0, 'reviews': 0, 'earnings': 0};

  // Average rating (0.0 - 5.0) and pending jobs count
  double averageRating = 0.0;
  int pendingJobs = 0;

  // New: user's location string (city / area) to display under name
  String? userLocation;

  // New: registration/contact details to display on dashboard
  String? email;
  String? phone;

  // Dashboard live data
  bool loadingDashboard = false;
  List<Map<String, dynamic>>? recentBookings;
  List<Map<String, dynamic>>? recentReviews;
  // Raw admin central payload (for debug / dashboard merging)
  Map<String, dynamic>? centralRaw;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
