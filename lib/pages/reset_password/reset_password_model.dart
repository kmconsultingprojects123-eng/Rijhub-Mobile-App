import '/flutter_flow/flutter_flow_util.dart';
import 'reset_password_widget.dart' show ResetPasswordWidget;
import 'package:flutter/material.dart';

class ResetPasswordModel extends FlutterFlowModel<ResetPasswordWidget> {
  ///  State fields for stateful widgets in this page.

  final formKey = GlobalKey<FormState>();
  // State field(s) for Password TextField widget.
  FocusNode? passwordFocusNode;
  TextEditingController? passwordController;
  String? Function(BuildContext, String?)? passwordControllerValidator;
  // State field(s) for Confirm Password TextField widget.
  FocusNode? confirmPasswordFocusNode;
  TextEditingController? confirmPasswordController;
  String? Function(BuildContext, String?)? confirmPasswordControllerValidator;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    passwordFocusNode?.dispose();
    passwordController?.dispose();
    confirmPasswordFocusNode?.dispose();
    confirmPasswordController?.dispose();
  }
}
