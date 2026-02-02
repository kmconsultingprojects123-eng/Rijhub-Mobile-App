import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/form_field_controller.dart';
import 'artisan_profileupdate_widget.dart' show ArtisanProfileupdateWidget;
import 'package:flutter/material.dart';

class ArtisanProfileupdateModel
    extends FlutterFlowModel<ArtisanProfileupdateWidget> {
  ///  State fields for stateful widgets in this page.

  // Controllers & focus nodes for profile fields
  TextEditingController? fullNameController;
  FocusNode? fullNameFocusNode;

  TextEditingController? emailController;
  FocusNode? emailFocusNode;

  TextEditingController? phoneController;
  FocusNode? phoneFocusNode;

  TextEditingController? passwordController;
  FocusNode? passwordFocusNode;

  // Artisan-specific fields
  TextEditingController? tradeController; // comma-separated trades
  FocusNode? tradeFocusNode;

  TextEditingController? experienceController; // numeric
  FocusNode? experienceFocusNode;

  TextEditingController? certificationsController; // comma-separated
  FocusNode? certificationsFocusNode;

  TextEditingController? bioController;
  FocusNode? bioFocusNode;

  TextEditingController? pricingPerHourController;
  FocusNode? pricingPerHourFocusNode;

  TextEditingController? pricingPerJobController;
  FocusNode? pricingPerJobFocusNode;

  TextEditingController? availabilityController; // comma-separated availability strings
  FocusNode? availabilityFocusNode;

  TextEditingController? serviceAreaAddressController;
  FocusNode? serviceAreaAddressFocusNode;

  TextEditingController? serviceAreaRadiusController; // numeric kms
  FocusNode? serviceAreaRadiusFocusNode;

  // Portfolio files will be stored in the widget state; model doesn't store file bytes

  // Note: model only keeps controllers for fields the API accepts:
  // name, email, phone, password. Profile image is handled separately in widget state.

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    fullNameFocusNode?.dispose();
    fullNameController?.dispose();

    emailFocusNode?.dispose();
    emailController?.dispose();

    phoneFocusNode?.dispose();
    phoneController?.dispose();

    passwordFocusNode?.dispose();
    passwordController?.dispose();

    // dispose artisan-specific controllers
    tradeFocusNode?.dispose();
    tradeController?.dispose();

    experienceFocusNode?.dispose();
    experienceController?.dispose();

    certificationsFocusNode?.dispose();
    certificationsController?.dispose();

    bioFocusNode?.dispose();
    bioController?.dispose();

    pricingPerHourFocusNode?.dispose();
    pricingPerHourController?.dispose();

    pricingPerJobFocusNode?.dispose();
    pricingPerJobController?.dispose();

    availabilityFocusNode?.dispose();
    availabilityController?.dispose();

    serviceAreaAddressFocusNode?.dispose();
    serviceAreaAddressController?.dispose();

    serviceAreaRadiusFocusNode?.dispose();
    serviceAreaRadiusController?.dispose();

    // No additional controllers to dispose.
  }
}
