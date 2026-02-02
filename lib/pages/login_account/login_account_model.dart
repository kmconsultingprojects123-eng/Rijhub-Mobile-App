import '/flutter_flow/flutter_flow_model.dart';
import 'login_account_widget.dart' show LoginAccountWidget;
import 'package:flutter/material.dart';

class LoginAccountModel extends FlutterFlowModel<LoginAccountWidget> {
  ///  State fields for stateful widgets in this page.

  // State field(s) for emailAddress widget.
  FocusNode? emailAddressFocusNode;
  TextEditingController? emailAddressTextController;
  String? Function(BuildContext, String?)? emailAddressTextControllerValidator;
  // State field(s) for passWord widget.
  FocusNode? passWordFocusNode;
  TextEditingController? passWordTextController;
  String? Function(BuildContext, String?)? passWordTextControllerValidator;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    emailAddressFocusNode?.dispose();
    emailAddressTextController?.dispose();

    passWordFocusNode?.dispose();
    passWordTextController?.dispose();
  }
}
