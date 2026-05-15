import '/flutter_flow/flutter_flow_util.dart';
import 'artisan_onboarding_widget.dart' show ArtisanOnboardingWidget;
import 'package:flutter/material.dart';

class ArtisanOnboardingModel
    extends FlutterFlowModel<ArtisanOnboardingWidget> {
  TextEditingController? ninController;
  FocusNode? ninFocus;

  TextEditingController? experienceController;
  FocusNode? experienceFocus;

  TextEditingController? businessNameController;
  FocusNode? businessNameFocus;

  // Free-form artisan bio shown in the Showcase section. Mirrors the
  // legacy ArtisanCompleteProfileWidget's "Bio / About You" field —
  // backend accepts a top-level `bio` string on PUT /api/artisans/me.
  TextEditingController? bioController;
  FocusNode? bioFocus;

  @override
  void initState(BuildContext context) {
    ninController = TextEditingController();
    ninFocus = FocusNode();
    experienceController = TextEditingController();
    experienceFocus = FocusNode();
    businessNameController = TextEditingController();
    businessNameFocus = FocusNode();
    bioController = TextEditingController();
    bioFocus = FocusNode();
  }

  @override
  void dispose() {
    ninController?.dispose();
    ninFocus?.dispose();
    experienceController?.dispose();
    experienceFocus?.dispose();
    businessNameController?.dispose();
    businessNameFocus?.dispose();
    bioController?.dispose();
    bioFocus?.dispose();
  }
}
