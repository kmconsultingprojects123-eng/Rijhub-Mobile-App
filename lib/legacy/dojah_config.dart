import 'package:flutter_dotenv/flutter_dotenv.dart';

// Dojah Custom Widget ID used by the native Dojah Flutter SDK
// (`dojah_kyc_sdk_flutter`) when launching the KYC flow.
//
// The widget itself is configured in the Dojah dashboard (EasyOnboard →
// Custom Widget) with the steps: NIN entry → Liveness → Selfie match.
// Read at runtime from the `.env` file at the project root, with the
// current value as a fallback so dev builds work without env config.
//
// In production the value should come from `GET /api/kyc/dojah/config`
// (per KYC_DOJAH_SDK_BACKEND_SPEC.md) so the team can rotate the widget
// without releasing a new app version.
final String DOJAH_WIDGET_ID =
    dotenv.env['DOJAH_WIDGET_ID'] ?? '69fa3d5ee00bdfad4bbc48f5';

// Dojah App ID and (public) Client Key used by the WebView SDK
// (`flutter_dojah_kyc`). These are public-by-design Dojah identifiers — safe
// to ship in mobile code, though .env override is preferred for production.
//
// The secret key (paired with the public key) is **never** in mobile code;
// it stays on the backend per KYC_DOJAH_SDK_BACKEND_SPEC.md.
final String DOJAH_APP_ID =
    dotenv.env['DOJAH_APP_ID'] ?? '69d4e7ad91cf0ce4039b9a6d';

final String DOJAH_PUBLIC_KEY =
    dotenv.env['DOJAH_PUBLIC_KEY'] ?? 'prod_pk_68xrPt1lNbflgGBRDKfBbH29B';
