import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'session.dart';

/// Why someone is being asked to sign in. It titles the sign-in sheet so
/// the request always makes sense in context ("Post your job", not a
/// generic login wall).
@immutable
class AuthPrompt {
  const AuthPrompt({required this.title, required this.message});

  /// Book a specific artisan.
  factory AuthPrompt.book(String artisanName) => AuthPrompt(
        title: 'Book $artisanName',
        message: "Add your phone number and we'll confirm your booking.",
      );

  final String title;
  final String message;

  /// A general way in, used by new and returning people alike, such as a
  /// header's "Sign in" or the Profile tab's "Sign in or sign up".
  static const join = AuthPrompt(
    title: 'Welcome to RijHub',
    message: "Enter your phone number and we'll text you a code.",
  );

  /// Only where the person has said they have an account, such as "Already
  /// have an account? Sign in", or where new people have a way of their own
  /// beside it (the artisan home's "Create your free profile").
  static const signIn = AuthPrompt(
    title: 'Welcome back',
    message: "Enter your phone number and we'll text you a code.",
  );

  static const postJob = AuthPrompt(
    title: 'Post your job',
    message: 'Add your phone number so artisans can send you quotes.',
  );

  static const joinAsArtisan = AuthPrompt(
    title: 'Create your free profile',
    message: 'Start getting jobs near you. It takes about a minute.',
  );

  static const sendQuote = AuthPrompt(
    title: 'Send your quote',
    message: 'Create your free artisan profile to quote on jobs.',
  );

  static const bookings = AuthPrompt(
    title: 'See your bookings',
    message: 'Add your phone number to see and follow your bookings.',
  );

  static const messages = AuthPrompt(
    title: 'Message artisans',
    message: 'Add your phone number to chat with artisans about your jobs.',
  );

  /// Prompts by name, for QA launches (`lib/app/dev_launch.dart`).
  static const byName = {
    'join': join,
    'signIn': signIn,
    'postJob': postJob,
    'joinAsArtisan': joinAsArtisan,
    'sendQuote': sendQuote,
    'bookings': bookings,
    'messages': messages,
  };
}

/// Shows the sign-in sheet. Returns true once the person is signed in.
typedef AuthPresenter = Future<bool> Function(
  BuildContext context,
  AuthPrompt prompt,
);

/// The one way screens ask for an account. Provided at the root; the real
/// presenter is the sign-in sheet, and tests can pass their own.
class AuthGate {
  AuthGate(this._present);

  final AuthPresenter _present;

  /// The sign-in that is showing, so a second tap joins it instead of
  /// stacking another sheet.
  Future<bool>? _pending;

  /// Resolves to true when the person is signed in, asking first if needed.
  Future<bool> ensureSignedIn(BuildContext context, AuthPrompt prompt) {
    if (context.read<SessionController>().isSignedIn) {
      return Future.value(true);
    }
    return _pending ??=
        _present(context, prompt).whenComplete(() => _pending = null);
  }
}
