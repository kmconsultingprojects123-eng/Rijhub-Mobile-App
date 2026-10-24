import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Reads the Ask chat's messages aloud, for people who'd rather listen than
/// read. Screens use this, never the plugin, so tests can stand in a fake.
abstract interface class Speaker {
  /// Says [text] after anything already being said. [key] is the message
  /// it belongs to, for [saying].
  void say(String text, {Object? key});

  /// Stops at once, and forgets anything waiting to be said.
  Future<void> stop();

  /// The key of what's being said now (a line said without one has its
  /// own); null when quiet.
  ValueListenable<Object?> get saying;
}

/// What [Speaker.saying] holds for a line said without a key.
final unkeyed = Object();

/// The phone's own speech engine: instant, offline and free. Nigerian
/// English where the phone has it (most Android phones), else British.
class DeviceSpeaker implements Speaker {
  final _tts = FlutterTts();
  final _queue = Queue<(String, Object?)>();
  final _saying = ValueNotifier<Object?>(null);
  late final Future<void> _ready = _setUp();
  bool _running = false;

  // Bumped by [stop], so a line already playing doesn't lead on to the
  // next one after it.
  int _turn = 0;

  @override
  ValueListenable<Object?> get saying => _saying;

  Future<void> _setUp() async {
    try {
      await _tts.awaitSpeakCompletion(true);
      for (final language in const ['en-NG', 'en-GB', 'en-US']) {
        if (await _tts.isLanguageAvailable(language) == true) {
          await _tts.setLanguage(language);
          break;
        }
      }
      // A little slower than usual (0.5), so every word is clear.
      await _tts.setSpeechRate(0.45);
      if (Platform.isIOS) {
        // The kind of session the voice-note recorder needs, so neither
        // undoes the other, and out of the loudspeaker, not the earpiece.
        await _tts.setSharedInstance(true);
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playAndRecord,
          [
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            IosTextToSpeechAudioCategoryOptions.duckOthers,
          ],
        );
      }
    } on Object catch (e) {
      debugPrint('speech: $e');
    }
  }

  @override
  void say(String text, {Object? key}) {
    final words = spoken(text);
    if (words.isEmpty) return;
    _queue.add((words, key));
    if (!_running) unawaited(_run());
  }

  Future<void> _run() async {
    _running = true;
    final turn = _turn;
    await _ready;
    while (_queue.isNotEmpty && turn == _turn) {
      final (words, key) = _queue.removeFirst();
      _saying.value = key ?? unkeyed;
      try {
        await _tts.speak(words);
      } on Object catch (e) {
        debugPrint('speech: $e');
      }
    }
    if (turn != _turn) return;
    _saying.value = null;
    _running = false;
  }

  @override
  Future<void> stop() async {
    _turn++;
    _queue.clear();
    _running = false;
    _saying.value = null;
    try {
      await _tts.stop();
    } on Object catch (e) {
      debugPrint('speech: $e');
    }
  }
}

/// Says nothing, and keeps what it was asked to say: for tests and
/// screenshots.
class SampleSpeaker implements Speaker {
  final said = <String>[];
  final _saying = ValueNotifier<Object?>(null);

  @override
  ValueListenable<Object?> get saying => _saying;

  @override
  void say(String text, {Object? key}) => said.add(spoken(text));

  @override
  Future<void> stop() async {}
}

/// [text] the way it should sound: "₦8,000 – ₦12,000" is "8,000 to 12,000
/// naira", "AC" is two letters, a phone number is read digit by digit, and
/// Employi rhymes with "employee".
String spoken(String text) => text
    .replaceAllMapped(RegExp(r'₦([\d,]+)\s*[–-]\s*₦([\d,]+)'),
        (m) => '${m[1]} to ${m[2]} naira')
    .replaceAllMapped(RegExp(r'₦([\d,]+)'), (m) => '${m[1]} naira')
    .replaceAllMapped(RegExp(r'\+?\b\d{3,4}(?: \d{3,4}){2,3}\b'), _digits)
    .replaceAll(RegExp(r'\bACs\b'), 'A.C.s')
    .replaceAll(RegExp(r'\bAC\b'), 'A.C.')
    .replaceAll('Employi', 'Employee')
    .replaceAll(' · ', ', ')
    .replaceAll('–', ' to ')
    .trim();

/// "+234 803 123 4567" as "plus 2 3 4, 8 0 3, 1 2 3, 4 5 6 7".
String _digits(Match m) => m[0]!
    .split(' ')
    .map((group) => group.startsWith('+')
        ? 'plus ${group.substring(1).split('').join(' ')}'
        : group.split('').join(' '))
    .join(', ');
