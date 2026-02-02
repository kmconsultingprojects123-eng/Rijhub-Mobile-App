import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '../../utils/app_notification.dart';
import '../../utils/error_messages.dart';
import '/services/auth_service.dart';
import 'package:easy_debounce/easy_debounce.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../login_account/login_account_widget.dart';
import 'forget_password_model.dart';
export 'forget_password_model.dart';

/// Create a page to input emaill for forgot password
class ForgetPasswordWidget extends StatefulWidget {
  const ForgetPasswordWidget({super.key});

  static String routeName = 'forgetPassword';
  // Use the exact path required by the client: '/forgotPassword' (case-sensitive)
  static String routePath = '/forgotPassword';

  @override
  State<ForgetPasswordWidget> createState() => _ForgetPasswordWidgetState();
}

class _ForgetPasswordWidgetState extends State<ForgetPasswordWidget> {
  late ForgetPasswordModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => ForgetPasswordModel());

    _model.textController ??= TextEditingController();
    _model.textFieldFocusNode ??= FocusNode();
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        appBar: AppBar(
          // Use theme colors so AppBar adapts to light/dark mode and
          // matches other screens in the app.
          backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
          automaticallyImplyLeading: false,
          leading: FlutterFlowIconButton(
            buttonSize: 40.0,
            icon: Icon(
              Icons.arrow_back_ios,
              color: FlutterFlowTheme.of(context).primaryText,
              size: 20.0,
            ),
            onPressed: () {
              // Use declarative router navigation (no Navigator stacking)
              context.go(LoginAccountWidget.routePath);
            },
          ),
          title: Text(
            'Reset Password',
            style: FlutterFlowTheme.of(context).titleLarge.override(
                  font: GoogleFonts.interTight(
                    fontWeight:
                        FlutterFlowTheme.of(context).titleLarge.fontWeight,
                    fontStyle:
                        FlutterFlowTheme.of(context).titleLarge.fontStyle,
                  ),
                  letterSpacing: 0.0,
                  fontWeight:
                      FlutterFlowTheme.of(context).titleLarge.fontWeight,
                  fontStyle: FlutterFlowTheme.of(context).titleLarge.fontStyle,
                ),
          ),
          actions: [],
          centerTitle: true,
          // Remove elevation/shadow so AppBar has no box shadow
          elevation: 0.0,
          shadowColor: Colors.transparent,
        ),
        body: SafeArea(
          top: true,
          child: SingleChildScrollView(
            padding: EdgeInsetsDirectional.fromSTEB(24.0, 16.0, 24.0, 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top icon and explanatory texts
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(0.0, 8.0, 0.0, 8.0),
                  child: Center(
                    child: Icon(
                      Icons.lock_reset,
                      color: FlutterFlowTheme.of(context).primary,
                      size: 80.0,
                    ),
                  ),
                ),

                const SizedBox(height: 8.0),

                Text(
                  'Forgot Password?',
                  textAlign: TextAlign.center,
                  style: FlutterFlowTheme.of(context).headlineMedium.override(
                        font: GoogleFonts.interTight(
                          fontWeight: FontWeight.w600,
                          fontStyle: FlutterFlowTheme.of(context).headlineMedium.fontStyle,
                        ),
                        fontSize: 28.0,
                        letterSpacing: 0.0,
                        fontWeight: FontWeight.w600,
                      ),
                ),

                const SizedBox(height: 12.0),

                Text(
                  'Don\'t worry! Enter your email address and we\'ll send you a link to reset your password.',
                  textAlign: TextAlign.center,
                  style: FlutterFlowTheme.of(context).bodyMedium.override(
                        font: GoogleFonts.inter(
                          fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                          fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                        ),
                        color: FlutterFlowTheme.of(context).secondaryText,
                        lineHeight: 1.4,
                      ),
                ),

                const SizedBox(height: 20.0),

                // Email input + button
                Form(
                  key: _model.formKey,
                  autovalidateMode: AutovalidateMode.disabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _model.textController,
                        focusNode: _model.textFieldFocusNode,
                        onChanged: (_) => EasyDebounce.debounce(
                          '_model.textController',
                          Duration(milliseconds: 2000),
                          () => safeSetState(() {}),
                        ),
                        autofocus: false,
                        obscureText: false,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          hintText: 'Enter your email address',
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: FlutterFlowTheme.of(context).alternate,
                              width: 1.0,
                            ),
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: FlutterFlowTheme.of(context).primary,
                              width: 1.0,
                            ),
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                          filled: true,
                          fillColor: FlutterFlowTheme.of(context).secondaryBackground,
                          contentPadding: EdgeInsetsDirectional.fromSTEB(16.0, 16.0, 16.0, 16.0),
                          prefixIcon: Icon(
                            Icons.email_outlined,
                            color: FlutterFlowTheme.of(context).secondaryText,
                            size: 20.0,
                          ),
                        ),
                        style: FlutterFlowTheme.of(context).bodyMedium.override(
                              font: GoogleFonts.inter(
                                fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                                fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                              ),
                              fontSize: 16.0,
                            ),
                        keyboardType: TextInputType.emailAddress,
                        validator: _model.textControllerValidator.asValidator(context),
                      ),

                      const SizedBox(height: 20.0),

                      FFButtonWidget(
                        onPressed: _isSubmitting ? null : () async {
                          // Validate email
                          final email = _model.textController?.text.trim() ?? '';
                          final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                          if (email.isEmpty || !emailRegex.hasMatch(email)) {
                            AppNotification.showError(context, 'Please enter a valid email');
                            return;
                          }

                          setState(() { _isSubmitting = true; });
                          AppNotification.showInfo(context, 'Checking email...');

                          try {
                            // Send the reset link immediately (no pre-check). Use the fast
                            // immediate helper so UI is responsive and there's no extra round-trip.
                            AppNotification.showInfo(context, 'Requesting password reset...');

                            final resp = await AuthService.forgotPasswordImmediate(email: email, timeoutSeconds: 12);

                            if (resp['success'] == true) {
                              final message = (resp['data'] is Map && resp['data']['message'] != null)
                                  ? resp['data']['message'].toString()
                                  : 'If an account with that email exists, a password reset link has been sent.';
                              AppNotification.showSuccess(context, message);
                              await Future.delayed(const Duration(milliseconds: 400));
                              // After success, go to login page (use context.go to avoid stacking)
                              if (mounted) context.go(LoginAccountWidget.routePath);
                            } else {
                              String msg = 'Could not request password reset.';
                              if (resp['error'] is Map && resp['error']['message'] != null) msg = resp['error']['message'].toString();
                              // Sanitize technical error messages into a friendly line
                              final lower = msg.toLowerCase();
                              if (lower.contains('timed out') || lower.contains('timeout')) {
                                msg = 'Request timed out. Please check your connection and try again.';
                              } else if (lower.contains('network error') || lower.contains('socket') || lower.contains('failed host lookup')) {
                                msg = 'Network error. Please check your connection and try again.';
                              }
                              AppNotification.showError(context, msg);
                            }
                         } catch (e) {
                           AppNotification.showError(context, ErrorMessages.humanize(e));
                         } finally {
                           if (mounted) setState(() { _isSubmitting = false; });
                         }
                        },
                        text: 'Send Reset Link',
                        options: FFButtonOptions(
                          width: double.infinity,
                          height: 48.0,
                          padding: EdgeInsets.all(8.0),
                          color: FlutterFlowTheme.of(context).primary,
                          textStyle: FlutterFlowTheme.of(context).titleMedium.override(
                                font: GoogleFonts.interTight(),
                                color: Colors.white,
                                fontSize: 16.0,
                              ),
                          elevation: 0.0,
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                      ),
                    ],
                  ),
                ),

                // Footer: Sign in link (use context.go to navigate to exact route)
                const SizedBox(height: 18.0),
                Center(
                  child: TextButton(
                    onPressed: () => context.go(LoginAccountWidget.routePath),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: RichText(
                      textScaler: MediaQuery.of(context).textScaler,
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'Remember your password? ',
                            style: FlutterFlowTheme.of(context).bodyMedium.override(
                              font: GoogleFonts.inter(),
                              letterSpacing: 0.0,
                            ),
                          ),
                          TextSpan(
                            text: 'Sign in',
                            style: FlutterFlowTheme.of(context).bodyMedium.override(
                              font: GoogleFonts.inter(),
                              color: FlutterFlowTheme.of(context).primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                        style: FlutterFlowTheme.of(context).bodyMedium,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8.0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
