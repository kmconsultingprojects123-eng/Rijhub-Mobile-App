import '/flutter_flow/flutter_flow_util.dart';
import 'job_post_page_widget.dart' show JobPostPageWidget;
import 'package:flutter/material.dart';

class JobPostPageModel extends FlutterFlowModel<JobPostPageWidget> {
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
