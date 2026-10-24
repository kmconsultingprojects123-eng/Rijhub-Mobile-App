import '../repositories/repositories.dart';

/// Texts sign-in codes when the API leaves that to the app (Firebase phone
/// sign-in), then turns the code that was typed into proof of the number
/// for the API. Sending and checking errors arrive as [AuthException]s with
/// messages fit to show.
abstract interface class PhoneVerifier {
  /// Texts a code to [phone] (E.164).
  Future<PhoneVerification> send(String phone);

  /// The proof of the number (an ID token) for [code], typed for the text
  /// that [verificationId] names.
  Future<String> confirm(String verificationId, String code);
}

/// What sending did: a text is on its way ([verificationId]), or the phone
/// confirmed the number by itself and [proof] is ready, with nothing to type.
class PhoneVerification {
  const PhoneVerification.codeSent(String this.verificationId,
      {this.readByPhone})
      : proof = null;
  const PhoneVerification.verified(String this.proof)
      : verificationId = null,
        readByPhone = null;

  final String? verificationId;
  final String? proof;

  /// With a text on its way: the proof, once the phone reads the code in
  /// the text by itself (Android does), so nothing needs typing. Never
  /// completes where the phone can't.
  final Future<String>? readByPhone;
}

/// For builds without Firebase: says texts can't be sent.
class NoPhoneVerifier implements PhoneVerifier {
  const NoPhoneVerifier();

  static const _message =
      "We can't send texts right now. Get the code on WhatsApp instead.";

  @override
  Future<PhoneVerification> send(String phone) async =>
      throw const AuthException(_message);

  @override
  Future<String> confirm(String verificationId, String code) async =>
      throw const AuthException(_message);
}
