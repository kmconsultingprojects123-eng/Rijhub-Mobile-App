import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'edit_job_page_widget.dart' show EditJobPageWidget;

class EditJobPageModel extends FlutterFlowModel<EditJobPageWidget> {
  /// State fields for stateful widgets in this page.

  final formKey = GlobalKey<FormState>();

  // State field(s) for TextField widget.
  FocusNode? textFieldFocusNode1;
  TextEditingController? textController1;
  String? Function(BuildContext, String?)? textController1Validator;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    textFieldFocusNode1?.dispose();
    textController1?.dispose();
  }
}

