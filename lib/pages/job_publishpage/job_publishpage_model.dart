import '/flutter_flow/flutter_flow_util.dart';
import 'job_publishpage_widget.dart' show JobPublishpageWidget;
import 'package:flutter/material.dart';

class JobPublishpageModel extends FlutterFlowModel<JobPublishpageWidget> {
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
