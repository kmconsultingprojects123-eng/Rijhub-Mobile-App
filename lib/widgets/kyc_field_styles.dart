import 'package:flutter/material.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import 'package:google_fonts/google_fonts.dart';

InputDecoration kycInputDecoration(BuildContext context, {
  String? labelText,
  String? hintText,
  Widget? suffixIcon,
  EdgeInsetsGeometry? contentPadding,
}) {
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    hintStyle: FlutterFlowTheme.of(context).bodyMedium.override(
      font: GoogleFonts.inter(
        fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
        fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
      ),
      color: FlutterFlowTheme.of(context).secondaryText,
    ),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(
        color: FlutterFlowTheme.of(context).alternate,
        width: 2.0,
      ),
      borderRadius: BorderRadius.circular(12.0),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(
        // use faint primary highlight for focus
        color: FlutterFlowTheme.of(context).highlight,
        width: 2.0,
      ),
      borderRadius: BorderRadius.circular(12.0),
    ),
    errorBorder: OutlineInputBorder(
      borderSide: BorderSide(
        color: FlutterFlowTheme.of(context).error,
        width: 2.0,
      ),
      borderRadius: BorderRadius.circular(12.0),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderSide: BorderSide(
        color: FlutterFlowTheme.of(context).error,
        width: 2.0,
      ),
      borderRadius: BorderRadius.circular(12.0),
    ),
    filled: true,
    // keep background same but inputs will show faint highlight on focus via focusedBorder
    fillColor: FlutterFlowTheme.of(context).secondaryBackground,
    contentPadding: contentPadding ?? EdgeInsetsDirectional.fromSTEB(16.0, 16.0, 16.0, 16.0),
    suffixIcon: suffixIcon,
  );
}
