import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../flutter_flow/flutter_flow_theme.dart';
import '../../services/gemini_live_service.dart';
import '../../services/support_knowledge_base.dart';
import '../../utils/app_notification.dart';

/// Full-screen in-app voice call with Gemini Live AI support.
///
/// Flow:
///   1. Request mic permission.
///   2. Connect to Gemini Live via WebSocket.
///   3. Stream mic audio → Gemini; play Gemini audio → speaker.
///   4. If AI calls `escalate_to_human`, show a prompt to connect
///      the user with real support (phone / email).
class AiSupportCallWidget extends StatefulWidget {
  const AiSupportCallWidget({super.key});

  static String routeName = 'AiSupportCall';
  static String routePath = '/aiSupportCall';

  @override
  State<AiSupportCallWidget> createState() => _AiSupportCallWidgetState();
}

class _AiSupportCallWidgetState extends State<AiSupportCallWidget>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // ---- Gemini ----
  late final GeminiLiveService _gemini;

  // ---- Audio ----
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player; // Created fresh each turn to avoid buffer rot.
  StreamController<Uint8List>? _recorderStreamCtrl;
  StreamSubscription<Uint8List>? _recorderSub;
  bool _audioInitialised = false;
  bool _recorderStarted = false;

  // Hybrid streaming: accumulate ~1s of audio (jitter buffer), then start
  // a FRESH player (new instance!) and feed the rest in real-time.
  // The large jitter buffer absorbs WebSocket delivery bursts (chunks range
  // from 2 bytes to 15 KB) and network micro-stalls that cause underrun.
  final List<Uint8List> _startBuffer = [];
  int _startBufferBytes = 0;
  bool _playerStreamActive = false;
  bool _playerRestarting = false;
  // 24kHz × 2 bytes × 1.0s = 48000 bytes ≈ 1 second
  static const _startBufferTarget = 48000;

  bool _reconnecting = false;

  // ---- UI state ----
  _CallState _callState = _CallState.connecting;
  String _statusText = 'Connecting…';
  String _transcriptSnippet = '';
  bool _isMuted = false;
  Duration _elapsed = Duration.zero;
  Timer? _elapsedTimer;
  late final AnimationController _pulseController;

  // TODO: Replace with your real Gemini API key before testing, remove before pushing.
  static const _geminiApiKey = '';

  // ---------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _gemini = GeminiLiveService(apiKey: _geminiApiKey);
    _setupCallbacks();
    _startCall();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _endCall();
    _pulseController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // Lifecycle — keep session alive when app is backgrounded
  // ---------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[GeminiLive] lifecycle → $state');

    if (state == AppLifecycleState.resumed && _callState == _CallState.active) {
      _handleResume();
    }
  }

  /// Re-establish a clean audio session after returning from background.
  ///
  /// On Android the platform audio session can degrade while backgrounded
  /// (audio focus lost, internal buffers stale). If we let the old recorder
  /// keep running and just create a fresh player, the player inherits the
  /// degraded session and produces crackling.  Restarting the recorder forces
  /// the platform to fully re-initialise the audio session so the next
  /// player opens cleanly.
  Future<void> _handleResume() async {
    debugPrint('[GeminiLive] probing connection after resume…');

    // 1. Kill any lingering player state from before backgrounding.
    _stopPlayerStream();

    // 2. Restart the recorder to re-establish a healthy audio session.
    //    This reclaims audio focus and resets internal platform buffers.
    if (_recorderStarted && _recorder != null) {
      try {
        await _recorder!.stopRecorder();
        _recorderStarted = false;
        debugPrint('[GeminiLive] recorder stopped for audio session refresh');
      } catch (e) {
        debugPrint('[GeminiLive] recorder stop on resume failed: $e');
      }
    }

    // 3. Probe the WebSocket.
    final alive = _gemini.probeConnection();
    if (!alive) {
      debugPrint('[GeminiLive] connection dead — reconnecting…');
      if (mounted) setState(() => _statusText = 'Reconnecting…');
      _reconnectAfterBackground();
      return;
    }

    debugPrint('[GeminiLive] connection still alive after resume');

    // 4. Unsuppress mic (may have been stuck from a response timeout nudge
    //    that fired while backgrounded).
    _gemini.micSuppressed = false;

    // 5. Re-start the recorder now that the audio session is fresh.
    if (!_recorderStarted) {
      await _startRecorder();
    }
  }

  /// Tear down audio, reconnect Gemini, restart recorder.
  Future<void> _reconnectAfterBackground() async {
    if (_reconnecting) {
      debugPrint('[GeminiLive] reconnect already in progress — skipping');
      return;
    }
    _reconnecting = true;

    // Stop the old player state.
    _stopPlayerStream();

    // Reconnect the WebSocket (will trigger onSetupComplete → UI updates).
    await _gemini.reconnect();

    // Restart the recorder if it was running before.
    if (_recorderStarted) {
      _recorderStarted = false;
      // Recorder restart happens automatically on first onTurnComplete.
    }

    _reconnecting = false;
  }

  // ---------------------------------------------------------------
  // Foreground service (Android) + wakelock
  // ---------------------------------------------------------------

  Future<void> _startForegroundTask() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ai_support_call',
        channelName: 'AI Support Call',
        channelDescription: 'Keeps AI voice call active in the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    await FlutterForegroundTask.startService(
      notificationTitle: 'AI Support Call',
      notificationText: 'Voice call in progress…',
    );
    debugPrint('[GeminiLive] foreground task started');

    // Keep screen on during the call.
    WakelockPlus.enable();
  }

  Future<void> _stopForegroundTask() async {
    await FlutterForegroundTask.stopService();
    WakelockPlus.disable();
    debugPrint('[GeminiLive] foreground task stopped');
  }

  // ---------------------------------------------------------------
  // Gemini callbacks
  // ---------------------------------------------------------------

  void _setupCallbacks() {
    _gemini
      ..onSetupComplete = () {
        if (!mounted) return;
        debugPrint('[GeminiLive] Gemini setup complete');
        setState(() {
          _callState = _CallState.active;
          _statusText = 'Connected — speak now';
        });
        _startElapsedTimer();
      }
      ..onAudioReceived = (bytes) {
        _onAudioChunk(bytes);
      }
      ..onTextReceived = (text) {
        if (!mounted) return;
        setState(() => _transcriptSnippet = text);
      }
      ..onTurnComplete = () {
        if (!mounted) return;

        // If the player stream never started (short response), flush
        // whatever we have via the one-shot fallback.
        if (!_playerStreamActive && _startBuffer.isNotEmpty) {
          _playBufferOneShot();
        }

        // Pad the stream with ~1s of silence so the player buffer drains
        // cleanly on silence rather than underrunning (which causes crackling).
        // 24000 Hz × 2 bytes × 1.0s = 48000 bytes
        if (_playerStreamActive && _player != null) {
          try {
            _player!.uint8ListSink?.add(Uint8List(48000));
            debugPrint('[GeminiLive] silence padding added');
          } catch (_) {}
        }

        // Stop after 2.5s — enough for remaining audio + silence pad to drain.
        Timer(const Duration(milliseconds: 2500), () {
          _stopPlayerStream();
          _gemini.micSuppressed = false;
          debugPrint('[GeminiLive] player stopped — mic enabled');
        });

        // Start the mic recorder after the AI's first greeting turn.
        if (!_recorderStarted) {
          _startRecorder();
        }

        setState(() => _statusText = 'Listening…');
      }
      ..onError = (err) {
        debugPrint('[GeminiLive] Gemini error: $err');
        if (!mounted) return;
        setState(() {
          _callState = _CallState.error;
          _statusText = 'Connection error — tap retry';
        });
      }
      ..onDisconnected = () {
        debugPrint('[GeminiLive] Gemini disconnected');
        if (!mounted) return;
        if (_callState == _CallState.ended) return;

        // If the call was active (not user-ended), try to reconnect once
        // before showing the error state.
        if (_callState == _CallState.active) {
          debugPrint('[GeminiLive] unexpected disconnect — auto-reconnecting…');
          setState(() => _statusText = 'Reconnecting…');
          _reconnectAfterBackground();
        } else {
          setState(() {
            _callState = _CallState.error;
            _statusText = 'Call disconnected — tap retry';
          });
        }
      };
  }

  // ---------------------------------------------------------------
  // Audio helpers
  // ---------------------------------------------------------------

  Future<bool> _initAudio() async {
    try {
      // Player is created fresh for each turn — not opened here.

      // --- Recorder (opened but NOT started until after first greeting) ---
      _recorder = FlutterSoundRecorder();
      await _recorder!.openRecorder();
      debugPrint('[GeminiLive] recorder opened');

      _audioInitialised = true;
      return true;
    } catch (e) {
      debugPrint('[GeminiLive] audio init failed: $e');
      if (mounted) {
        setState(() {
          _callState = _CallState.error;
          _statusText = 'Audio setup failed — tap retry';
        });
      }
      return false;
    }
  }

  /// Start the microphone recorder — called once after the AI's first turn.
  Future<void> _startRecorder() async {
    if (_recorderStarted || _recorder == null) return;
    try {
      _recorderStreamCtrl = StreamController<Uint8List>();
      _recorderSub = _recorderStreamCtrl!.stream.listen((data) {
        if (!_isMuted) {
          _gemini.sendAudioChunk(data);
        }
      });

      await _recorder!.startRecorder(
        toStream: _recorderStreamCtrl!.sink,
        codec: Codec.pcm16,
        numChannels: 1,
        sampleRate: 16000,
      );
      _recorderStarted = true;
      debugPrint('[GeminiLive] recorder started (16 kHz PCM)');
    } catch (e) {
      debugPrint('[GeminiLive] recorder start failed: $e');
    }
  }

  /// Called for every audio chunk from the model.  Accumulates a short
  /// jitter buffer (~500ms), then starts a fresh player stream and feeds
  /// the rest in real-time.
  void _onAudioChunk(Uint8List bytes) {
    // Always buffer while the player is restarting.
    if (_playerRestarting) {
      _startBuffer.add(bytes);
      _startBufferBytes += bytes.length;
      return;
    }

    if (_playerStreamActive && _player != null) {
      // Stream is running — feed directly.
      try {
        _player!.uint8ListSink?.add(bytes);
      } catch (e) {
        debugPrint('[GeminiLive] stream feed error: $e');
      }
      return;
    }

    // Accumulate until we have ~500ms of audio.
    _startBuffer.add(bytes);
    _startBufferBytes += bytes.length;

    if (_startBufferBytes >= _startBufferTarget) {
      _startFreshPlayerStream();
    }
  }

  /// Create a brand-new player instance, start streaming, flush the buffer.
  /// A fresh instance avoids internal ring-buffer rot that causes crackling
  /// after several stop/start cycles on the same player.
  Future<void> _startFreshPlayerStream() async {
    _playerRestarting = true;
    try {
      // Dispose the previous player entirely.
      final old = _player;
      _player = null;
      if (old != null) {
        try {
          await old.stopPlayer();
        } catch (_) {}
        try {
          await old.closePlayer();
        } catch (_) {}
      }

      // Brand-new instance.
      final fresh = FlutterSoundPlayer();
      await fresh.openPlayer();
      await fresh.startPlayerFromStream(
        codec: Codec.pcm16,
        numChannels: 1,
        sampleRate: 24000,
        bufferSize: 131072, // ~2.7s ring buffer to absorb network jitter
        interleaved: true,
      );
      _player = fresh;

      // Flush everything accumulated (including chunks that arrived during restart).
      for (final chunk in _startBuffer) {
        _player!.uint8ListSink?.add(chunk);
      }
      _startBuffer.clear();
      _startBufferBytes = 0;
      _playerStreamActive = true;
      debugPrint('[GeminiLive] fresh player instance started');
    } catch (e) {
      debugPrint('[GeminiLive] player stream start error: $e');
    } finally {
      _playerRestarting = false;
    }
  }

  /// Fallback for very short responses that never reached the jitter target.
  Future<void> _playBufferOneShot() async {
    if (_startBuffer.isEmpty) return;

    final combined = Uint8List(_startBufferBytes);
    int offset = 0;
    for (final chunk in _startBuffer) {
      combined.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    _startBuffer.clear();
    _startBufferBytes = 0;

    try {
      // Dispose old player, create fresh one for this one-shot.
      final old = _player;
      _player = null;
      if (old != null) {
        try {
          await old.stopPlayer();
        } catch (_) {}
        try {
          await old.closePlayer();
        } catch (_) {}
      }

      final fresh = FlutterSoundPlayer();
      await fresh.openPlayer();
      _player = fresh;

      await _player!.startPlayer(
        fromDataBuffer: combined,
        codec: Codec.pcm16,
        sampleRate: 24000,
        numChannels: 1,
      );
    } catch (e) {
      debugPrint('[GeminiLive] one-shot play error: $e');
    }
  }

  void _stopPlayerStream() {
    final p = _player;
    _player = null;
    _playerStreamActive = false;
    _playerRestarting = false;
    _startBuffer.clear();
    _startBufferBytes = 0;
    if (p != null) {
      p.stopPlayer().catchError((_) => null).then((_) {
        p.closePlayer().catchError((_) => null);
      });
    }
  }

  void _disposeAudio() {
    _stopPlayerStream(); // Also closes/disposes the player instance.
    _recorderSub?.cancel();
    _recorderSub = null;
    _recorderStreamCtrl?.close();
    _recorderStreamCtrl = null;

    if (_audioInitialised) {
      _recorder?.stopRecorder().catchError((_) => null);
      _recorder?.closeRecorder().catchError((_) => null);
      _audioInitialised = false;
    }
    _recorderStarted = false;
    _recorder = null;
  }

  // ---------------------------------------------------------------
  // Call flow
  // ---------------------------------------------------------------

  Future<void> _startCall() async {
    if (!mounted) return;

    setState(() {
      _callState = _CallState.connecting;
      _statusText = 'Connecting…';
      _transcriptSnippet = '';
      _elapsed = Duration.zero;
    });

    // 0. Validate key.
    if (_geminiApiKey.isEmpty) {
      setState(() {
        _callState = _CallState.error;
        _statusText = 'Gemini API key not configured';
      });
      return;
    }

    // 1. Mic permission.
    debugPrint('[GeminiLive] requesting mic permission…');
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      debugPrint('[GeminiLive] mic permission denied');
      if (!mounted) return;
      setState(() {
        _callState = _CallState.error;
        _statusText = 'Microphone permission denied';
      });
      return;
    }
    debugPrint('[GeminiLive] mic permission granted');

    // 2. Open audio I/O.
    final audioOk = await _initAudio();
    if (!audioOk) return; // Error state already set inside _initAudio.

    // 3. Start foreground service to keep session alive when backgrounded.
    await _startForegroundTask();

    // 4. Connect to Gemini.
    debugPrint('[GeminiLive] connecting to Gemini…');
    await _gemini.connect(
      systemInstruction: SupportKnowledgeBase.systemPrompt,
      voiceName: 'Charon',
    );
  }

  void _endCall() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;

    // Null all callbacks FIRST — prevents any in-flight service callbacks
    // (including retry timers) from calling setState on a disposed widget.
    _gemini
      ..onSetupComplete = null
      ..onAudioReceived = null
      ..onTextReceived = null
      ..onTurnComplete = null
      ..onError = null
      ..onDisconnected = null;

    _disposeAudio();
    _gemini.disconnect();
    _stopForegroundTask();

    if (mounted) {
      setState(() {
        _callState = _CallState.ended;
        _statusText = 'Call ended';
      });
    }
  }

  void _retryCall() {
    debugPrint('[GeminiLive] retrying…');
    _disposeAudio();
    _gemini.disconnect();
    _startCall();
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    debugPrint('[GeminiLive] mute=$_isMuted');
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));

      // Check escalation flag each tick.
      if (_gemini.escalationRequested && _callState == _CallState.active) {
        setState(() => _callState = _CallState.escalating);
        _showEscalationDialog();
      }
    });
  }

  // ---------------------------------------------------------------
  // Escalation to human
  // ---------------------------------------------------------------

  Future<void> _showEscalationDialog() async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = FlutterFlowTheme.of(ctx);
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Connect with Support', style: theme.titleMedium),
          content: Text(
            'Our AI assistant thinks a human agent can help you better. '
            'How would you like to reach our support team?',
            style: theme.bodyMedium.copyWith(color: theme.secondaryText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Stay with AI'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'phone'),
              icon: const Icon(Icons.phone, size: 18),
              label: const Text('Call Support'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'email'),
              icon: const Icon(Icons.email, size: 18),
              label: const Text('Email'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA20025),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    switch (result) {
      case 'phone':
        _endCall();
        final uri = Uri.parse('tel:08053466666');
        if (!await launchUrl(uri)) {
          if (mounted) AppNotification.showError(context, 'Could not dial');
        }
        if (mounted) Navigator.of(context).pop();
        break;
      case 'email':
        _endCall();
        final uri = Uri(scheme: 'mailto', path: 'support@rijhub.com');
        if (!await launchUrl(uri)) {
          if (mounted) {
            AppNotification.showError(context, 'Could not open mail client');
          }
        }
        if (mounted) Navigator.of(context).pop();
        break;
      default:
        // User chose to stay with AI.
        setState(() => _callState = _CallState.active);
    }
  }

  // ---------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------

  String get _formattedTime {
    final m = _elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // Status badge colour & label based on _callState.
  Color get _badgeColor {
    switch (_callState) {
      case _CallState.active:
        return Colors.green;
      case _CallState.connecting:
        return Colors.orange;
      case _CallState.error:
        return Colors.red;
      case _CallState.ended:
        return Colors.grey;
      case _CallState.escalating:
        return Colors.blue;
    }
  }

  String get _badgeLabel {
    switch (_callState) {
      case _CallState.active:
        return 'AI Support';
      case _CallState.connecting:
        return 'Connecting';
      case _CallState.error:
        return 'Error';
      case _CallState.ended:
        return 'Ended';
      case _CallState.escalating:
        return 'Transferring';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const primaryColor = Color(0xFFA20025);

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            // ---- Top bar ----
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: theme.primary),
                    onPressed: () {
                      _endCall();
                      Navigator.of(context).pop();
                    },
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _badgeColor.withAlpha(26),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _badgeColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _badgeLabel,
                          style: TextStyle(
                            color: _badgeColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            const Spacer(),

            // ---- Loading spinner for connecting state ----
            if (_callState == _CallState.connecting)
              const Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Color(0xFFA20025),
                  ),
                ),
              ),

            // ---- Pulsing avatar ----
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final scale = 1.0 + (_pulseController.value * 0.08);
                return Transform.scale(
                  scale: _callState == _CallState.active ? scale : 1.0,
                  child: child,
                );
              },
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      primaryColor,
                      primaryColor.withAlpha(179),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withAlpha(77),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Center(
                  child: _callState == _CallState.error
                      ? const Icon(Icons.error_outline_rounded,
                          color: Colors.white, size: 60)
                      : const Icon(Icons.support_agent_rounded,
                          color: Colors.white, size: 60),
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ---- Name & status ----
            Text(
              'Rij — AI Support',
              style: theme.titleLarge.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _statusText,
              textAlign: TextAlign.center,
              style: theme.bodyMedium.copyWith(color: theme.secondaryText),
            ),

            if (_callState == _CallState.active) ...[
              const SizedBox(height: 6),
              Text(
                _formattedTime,
                style: theme.bodySmall.copyWith(
                  color: theme.secondaryText,
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
              ),
            ],

            // ---- Retry button on error ----
            if (_callState == _CallState.error) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _retryCall,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                ),
              ),
            ],

            // ---- Live transcript snippet ----
            if (_transcriptSnippet.isNotEmpty &&
                _callState == _CallState.active) ...[
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade900 : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color:
                          isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                    ),
                  ),
                  child: Text(
                    _transcriptSnippet,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyMedium.copyWith(
                      color: theme.secondaryText,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ],

            const Spacer(),

            // ---- Action buttons ----
            Padding(
              padding: const EdgeInsets.only(bottom: 48),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute
                  _buildActionButton(
                    icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    label: _isMuted ? 'Unmute' : 'Mute',
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                    iconColor: _isMuted
                        ? Colors.red
                        : (isDark ? Colors.white : Colors.black87),
                    onTap: _callState == _CallState.active ? _toggleMute : null,
                  ),

                  // End call
                  _buildActionButton(
                    icon: Icons.call_end_rounded,
                    label: 'End',
                    color: Colors.red,
                    iconColor: Colors.white,
                    size: 72,
                    onTap: () {
                      _endCall();
                      Navigator.of(context).pop();
                    },
                  ),

                  // Talk to human
                  _buildActionButton(
                    icon: Icons.person_rounded,
                    label: 'Human',
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                    iconColor: isDark ? Colors.white : Colors.black87,
                    onTap: _callState == _CallState.active
                        ? () {
                            setState(() => _callState = _CallState.escalating);
                            _showEscalationDialog();
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color iconColor,
    double size = 60,
    VoidCallback? onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: onTap != null ? color : color.withAlpha(102),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(icon, color: iconColor, size: size * 0.4),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: onTap != null ? null : Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

enum _CallState { connecting, active, escalating, error, ended }
