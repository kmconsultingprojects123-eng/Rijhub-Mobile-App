import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/models/models.dart';

/// Photos and voice notes: the camera, the photo library, the microphone
/// and playback. Screens use this, never the plugins, so tests can stand in
/// a fake and the app can ask for permission only at the moment it is
/// needed.
abstract interface class MediaService {
  /// A photo from the camera (or the library when [camera] is false), as a
  /// local file path. Null when the person cancels or says no.
  Future<String?> pickPhoto({required bool camera});

  /// Photos from the library, as many as the person picks. Empty when they
  /// cancel or say no.
  Future<List<String>> pickPhotos();

  /// Starts recording. False when the microphone isn't allowed.
  Future<bool> startRecording();

  /// The level of the voice being recorded, 0 to 1.
  Stream<double> get level;

  /// Stops and returns the note, or null when it was too short to keep.
  Future<VoiceNote?> stopRecording();
  Future<void> cancelRecording();

  /// Plays [note]; the stream gives progress from 0 to 1 and ends when it
  /// finishes or [stopPlaying] is called.
  Stream<double> play(VoiceNote note);
  Future<void> stopPlaying();
}

/// The device's camera, microphone and speaker.
class DeviceMediaService implements MediaService {
  final _picker = ImagePicker();
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  DateTime? _startedAt;
  String? _path;
  final _level = StreamController<double>.broadcast();
  StreamSubscription<RecordingDisposition>? _levelSub;
  StreamController<double>? _playing;

  @override
  Future<String?> pickPhoto({required bool camera}) async {
    try {
      final file = await _picker.pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 80,
      );
      return file?.path;
    } on Object catch (e) {
      debugPrint('pickPhoto: $e');
      return null;
    }
  }

  @override
  Future<List<String>> pickPhotos() async {
    try {
      final files =
          await _picker.pickMultiImage(maxWidth: 1600, imageQuality: 80);
      return [for (final f in files) f.path];
    } on Object catch (e) {
      debugPrint('pickPhotos: $e');
      return const [];
    }
  }

  @override
  Future<bool> startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) return false;
    final recorder = _recorder ??= FlutterSoundRecorder();
    await recorder.openRecorder();
    await recorder.setSubscriptionDuration(const Duration(milliseconds: 120));
    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.aac';
    _startedAt = DateTime.now();
    await recorder.startRecorder(toFile: _path, codec: Codec.aacADTS);
    _levelSub = recorder.onProgress?.listen((d) {
      final db = d.decibels ?? 0;
      _level.add((db / 60).clamp(0, 1).toDouble());
    });
    return true;
  }

  @override
  Stream<double> get level => _level.stream;

  @override
  Future<VoiceNote?> stopRecording() async {
    final recorder = _recorder;
    final started = _startedAt;
    if (recorder == null || started == null) return null;
    final path = await recorder.stopRecorder() ?? _path;
    await _levelSub?.cancel();
    _startedAt = null;
    final length = DateTime.now().difference(started);
    if (path == null || length < const Duration(milliseconds: 800)) return null;
    return VoiceNote(path: path, duration: length);
  }

  @override
  Future<void> cancelRecording() async {
    final path = await _recorder?.stopRecorder();
    await _levelSub?.cancel();
    _startedAt = null;
    if (path != null) {
      try {
        await File(path).delete();
      } on Object {
        // Already gone.
      }
    }
  }

  @override
  Stream<double> play(VoiceNote note) {
    _playing?.close();
    final out = _playing = StreamController<double>();
    if (!note.path.startsWith('/') && !note.path.startsWith('http')) {
      // Sample notes have no audio; show them playing for their length.
      _fakePlay(note, out);
      return out.stream;
    }
    () async {
      final player = _player ??= FlutterSoundPlayer();
      await player.openPlayer();
      await player.setSubscriptionDuration(const Duration(milliseconds: 100));
      final sub = player.onProgress?.listen((p) {
        if (p.duration.inMilliseconds > 0) {
          out.add(p.position.inMilliseconds / p.duration.inMilliseconds);
        }
      });
      await player.startPlayer(
        fromURI: note.path,
        codec: Codec.aacADTS,
        whenFinished: () {
          sub?.cancel();
          out.add(1);
          out.close();
        },
      );
    }();
    return out.stream;
  }

  void _fakePlay(VoiceNote note, StreamController<double> out) {
    final total = note.duration.inMilliseconds;
    var at = 0;
    Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (out.isClosed) return t.cancel();
      at += 100;
      out.add((at / total).clamp(0, 1).toDouble());
      if (at >= total) {
        t.cancel();
        out.close();
      }
    });
  }

  @override
  Future<void> stopPlaying() async {
    await _player?.stopPlayer();
    await _playing?.close();
    _playing = null;
  }
}

/// A stand-in for tests and screenshots: photos come from the bundled
/// samples, voice notes are 9 seconds long, nothing is played aloud.
class SampleMediaService implements MediaService {
  SampleMediaService(
      {this.photo = 'assets/images/onboarding/ac_technicians.webp'});

  final String photo;
  bool _recording = false;

  @override
  Future<String?> pickPhoto({required bool camera}) async => photo;

  @override
  Future<List<String>> pickPhotos() async => [photo];

  @override
  Future<bool> startRecording() async => _recording = true;

  @override
  Stream<double> get level => const Stream.empty();

  @override
  Future<VoiceNote?> stopRecording() async {
    if (!_recording) return null;
    _recording = false;
    return const VoiceNote(
        path: 'sample://voice', duration: Duration(seconds: 9));
  }

  @override
  Future<void> cancelRecording() async => _recording = false;

  @override
  Stream<double> play(VoiceNote note) => Stream.value(1);

  @override
  Future<void> stopPlaying() async {}
}
