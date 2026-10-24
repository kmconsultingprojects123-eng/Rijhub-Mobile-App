import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../data/api/phone_verifier.dart';
import '../data/repositories/repositories.dart';

/// Sign-in codes texted through Firebase phone sign-in, for when the RijHub
/// API leaves texting to the app. Firebase only proves the number: the app
/// signs straight back out of it and keeps RijHub's own session.
class FirebasePhoneVerifier implements PhoneVerifier {
  /// Lets "Resend code" text the same number again without Firebase asking
  /// the person to prove they're human a second time.
  int? _resendToken;
  String? _resendFor;

  static const _cantSend =
      "We couldn't send your code. Try again, or get it on WhatsApp.";
  static const _cantCheck =
      "We couldn't check your code. Try again in a moment.";

  @override
  Future<PhoneVerification> send(String phone) async {
    if (Firebase.apps.isEmpty) throw const AuthException(_cantSend);
    final sent = Completer<PhoneVerification>();
    final readByPhone = Completer<String>();
    void fail(Object e) {
      if (!sent.isCompleted) sent.completeError(_failure(e, _cantSend));
    }

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        forceResendingToken: _resendFor == phone ? _resendToken : null,
        codeSent: (verificationId, resendToken) {
          _resendToken = resendToken;
          _resendFor = phone;
          if (!sent.isCompleted) {
            sent.complete(PhoneVerification.codeSent(verificationId,
                readByPhone: readByPhone.future));
          }
        },
        // Android can confirm the number by itself: before any text goes
        // out, or by reading the code in the text when it lands. Either way
        // there's nothing to type.
        verificationCompleted: (credential) async {
          if (sent.isCompleted && readByPhone.isCompleted) return;
          try {
            final proof = await _proof(credential);
            if (!sent.isCompleted) {
              sent.complete(PhoneVerification.verified(proof));
            } else if (!readByPhone.isCompleted) {
              readByPhone.complete(proof);
            }
          } on Object catch (e) {
            // A late read that fails changes nothing: the code can still
            // be typed.
            fail(e);
          }
        },
        verificationFailed: fail,
        codeAutoRetrievalTimeout: (_) {},
      );
    } on Object catch (e) {
      fail(e);
    }
    // iOS may first show a check that the person is human.
    return sent.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => throw const AuthException(_cantSend),
    );
  }

  @override
  Future<String> confirm(String verificationId, String code) async {
    try {
      return await _proof(PhoneAuthProvider.credential(
          verificationId: verificationId, smsCode: code));
    } on Object catch (e) {
      throw _failure(e, _cantCheck);
    }
  }

  Future<String> _proof(PhoneAuthCredential credential) async {
    final auth = FirebaseAuth.instance;
    final signedIn = await auth.signInWithCredential(credential);
    final token = await signedIn.user?.getIdToken();
    // RijHub keeps its own session; Firebase was only the proof.
    await auth.signOut();
    if (token == null) throw const AuthException(_cantCheck);
    return token;
  }

  static AuthException _failure(Object e, String fallback) {
    if (e is AuthException) return e;
    final code = e is FirebaseAuthException ? e.code : '';
    return AuthException(switch (code) {
      'invalid-verification-code' =>
        "That code isn't right. Check the text and try again.",
      'session-expired' ||
      'code-expired' =>
        'That code has expired. Ask for a new one.',
      'invalid-phone-number' =>
        "That number doesn't look right. Check it and try again.",
      'too-many-requests' =>
        'Too many codes for this phone. Wait a while, or get it on WhatsApp.',
      'quota-exceeded' ||
      'billing-not-enabled' ||
      'operation-not-allowed' =>
        "We can't send texts right now. Get the code on WhatsApp instead.",
      'network-request-failed' =>
        "You're offline. Check your connection and try again.",
      _ => fallback,
    });
  }
}
