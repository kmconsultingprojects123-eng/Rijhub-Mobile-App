import 'package:flutter/foundation.dart';

/// What RijHub is told about a problem: words, a voice note and photos.
/// Any of them can be missing, but not all.

/// A recorded voice note.
@immutable
class VoiceNote {
  const VoiceNote({required this.path, required this.duration, this.heard});

  /// A local file while it is being sent; a URL once it is stored.
  final String path;
  final Duration duration;

  /// What RijHub heard in it, shown under the note so the person can see
  /// they were understood. Null until it has been transcribed.
  final String? heard;

  VoiceNote withHeard(String text) =>
      VoiceNote(path: path, duration: duration, heard: text);
}

@immutable
class AskInput {
  const AskInput({this.text, this.voiceNote, this.photos = const []});

  final String? text;
  final VoiceNote? voiceNote;

  /// Image references: local files while sending, URLs once stored.
  final List<String> photos;

  bool get isEmpty =>
      (text == null || text!.trim().isEmpty) &&
      voiceNote == null &&
      photos.isEmpty;

  /// Everything said, in words: the typed text, else what was heard.
  String get words =>
      text?.trim().isNotEmpty == true ? text!.trim() : (voiceNote?.heard ?? '');
}

/// RijHub's reading of a problem: which trade it is, what the job is
/// usually called, and what it usually costs in the city.
@immutable
class Triage {
  const Triage({
    required this.categoryId,
    required this.serviceName,
    required this.reply,
    required this.priceMin,
    required this.priceMax,
    this.isUrgent = false,
    this.heard,
    this.confident = true,
  });

  final String categoryId;

  /// What the job is called on bookings and quotes: "AC service and gas
  /// top-up".
  final String serviceName;

  /// RijHub's answer in the conversation, written for the person: "Sounds
  /// like an AC service and a gas top-up. In Abuja that's usually ₦8,000 –
  /// ₦12,000."
  final String reply;

  /// Most jobs like this cost between these, in naira.
  final int priceMin;
  final int priceMax;

  /// The person said it can't wait ("leaking", "no light at all", "today").
  final bool isUrgent;

  /// What was heard in a voice note, when there was one.
  final String? heard;

  /// False when RijHub had to guess; the conversation then offers the
  /// closest trades to pick from instead of going straight to matches.
  final bool confident;
}
