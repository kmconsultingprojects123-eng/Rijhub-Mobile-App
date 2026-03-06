import '/flutter_flow/flutter_flow_util.dart';
import 'all_servicepage_widget.dart' show AllServicepageWidget;
import 'package:flutter/material.dart';

class AllServicepageModel extends FlutterFlowModel<AllServicepageWidget> {
  ///  State fields for stateful widgets in this page.

  // State field(s) for TextField widget.
  FocusNode? textFieldFocusNode;
  TextEditingController? textController;
  String? Function(BuildContext, String?)? textControllerValidator;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    textFieldFocusNode?.dispose();
    textController?.dispose();
  }
}
