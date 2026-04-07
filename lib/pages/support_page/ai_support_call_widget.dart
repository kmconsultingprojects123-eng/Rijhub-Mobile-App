import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../flutter_flow/flutter_flow_theme.dart';
import '../../services/gemini_live_service.dart';
import '../../services/support_knowledge_base.dart';
import '../../state/app_state_notifier.dart';
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
  StreamController<Uint8List>? _recorderStreamCtrl;
  StreamSubscription<Uint8List>? _recorderSub;
  bool _audioInitialised = false;
  bool _recorderStarted = false;

  // PCM playback via flutter_pcm_sound.
  // Chunks are fed directly to the platform as they arrive — no queue needed.
  bool _pcmPlayerReady = false;
  bool _pcmPlaying = false;
  bool _awaitingDrain = false; // true after turn complete, waiting for buffer to empty

  bool _reconnecting = false;

  // ---- UI state ----
  _CallState _callState = _CallState.connecting;
  String _statusText = 'Connecting…';
  String _transcriptSnippet = '';
  bool _isMuted = false;
  Duration _elapsed = Duration.zero;
  Timer? _elapsedTimer;
  late final AnimationController _pulseController;

  // ---- Call lifecycle limits ----
  static const _maxCallDuration = Duration(minutes: 15);
  static const _silenceTimeout = Duration(seconds: 60);
  static const _silenceWarningAt = Duration(seconds: 45);
  DateTime _lastActivityTime = DateTime.now();
  bool _silenceWarningSent = false;
  bool _endCallPending = false;

  // TODO: Replace with your real Gemini API key before testing, remove before pushing.
  static const _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

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

    // 1. Kill any lingering player state from before backgrounding, then re-init.
    _releasePcmPlayer();
    await _initPcmPlayer();

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
    _releasePcmPlayer();

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
        _lastActivityTime = DateTime.now();
        _onAudioChunk(bytes);
      }
      ..onTextReceived = (text) {
        if (!mounted) return;
        _lastActivityTime = DateTime.now();
        _silenceWarningSent = false;
        setState(() => _transcriptSnippet = text);
      }
      ..onTurnComplete = () {
        if (!mounted) return;

        // If AI requested end_call during this turn, wait for audio to
        // finish playing (via drain callback) then exit gracefully.
        if (_gemini.endCallRequested && !_endCallPending) {
          _endCallPending = true;
          debugPrint('[CallLifecycle] end_call detected at turnComplete — '
              'waiting for audio drain then exiting');
          _awaitingDrain = true; // will be cleared by _onPcmFeed
          // After audio drains (or max 5s), end the call.
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted && _endCallPending) {
              debugPrint('[CallLifecycle] grace period done — ending call');
              _endCall();
              if (mounted) Navigator.of(context).pop();
            }
          });
          return; // don't re-enable mic, call is ending
        }

        // Normal turn end — re-enable mic when audio finishes playing.
        _waitForQueueDrain();

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
      // --- Recorder first (so flutter_sound sets its audio session) ---
      _recorder = FlutterSoundRecorder();
      await _recorder!.openRecorder();
      debugPrint('[GeminiLive] recorder opened');

      // --- PCM player AFTER recorder (takes over audio session with
      //     playAndRecord so both mic and speaker work simultaneously) ---
      await _initPcmPlayer();

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
          _lastActivityTime = DateTime.now();
          _silenceWarningSent = false;
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

  // --------------- PCM playback (flutter_pcm_sound) ---------------

  /// Initialise the PCM player once per call session.
  Future<void> _initPcmPlayer() async {
    if (_pcmPlayerReady) return;
    await FlutterPcmSound.setLogLevel(LogLevel.error);
    await FlutterPcmSound.setup(
      sampleRate: 24000,
      channelCount: 1,
      iosAudioCategory: IosAudioCategory.playAndRecord,
    );
    // Request a callback when fewer than 6000 frames (~250ms) remain.
    await FlutterPcmSound.setFeedThreshold(6000);
    FlutterPcmSound.setFeedCallback(_onPcmFeed);
    _pcmPlayerReady = true;
    debugPrint('[PCMPlayer] initialised (24kHz, mono, threshold=6000)');
  }

  int _pcmChunkCount = 0;

  /// Called by the platform when its buffer runs low or empty.
  /// With direct feeding this is mainly used to detect when all audio
  /// has finished playing so we can re-enable the mic.
  void _onPcmFeed(int remainingFrames) {
    if (remainingFrames == 0 && _awaitingDrain) {
      _awaitingDrain = false;
      _pcmPlaying = false;
      _gemini.micSuppressed = false;
      debugPrint('[PCMPlayer] buffer fully drained — mic enabled');
    }
  }

  /// Called for every audio chunk from the model.
  /// Feeds directly to the platform — no intermediate queue.
  void _onAudioChunk(Uint8List bytes) {
    _pcmChunkCount++;
    if (_pcmChunkCount <= 3 || _pcmChunkCount % 50 == 0) {
      debugPrint('[PCMPlayer] chunk #$_pcmChunkCount fed (${bytes.length} bytes)');
    }

    // Feed directly to the platform.
    final pcmBuffer = PcmArrayInt16(bytes: bytes.buffer.asByteData());
    FlutterPcmSound.feed(pcmBuffer);
    _pcmPlaying = true;
    _awaitingDrain = false;
  }

  /// After a turn completes, set the flag so the feed callback knows
  /// to re-enable the mic when the platform buffer fully drains.
  void _waitForQueueDrain() {
    _awaitingDrain = true;
    debugPrint('[PCMPlayer] awaiting buffer drain to re-enable mic');
  }

  /// Release PCM player resources.
  void _releasePcmPlayer() {
    _pcmPlaying = false;
    _awaitingDrain = false;
    if (_pcmPlayerReady) {
      FlutterPcmSound.release().catchError((_) => null);
      _pcmPlayerReady = false;
      debugPrint('[PCMPlayer] released');
    }
  }

  void _disposeAudio() {
    _releasePcmPlayer();
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

    // 4. Connect to Gemini with user context.
    final appState = AppStateNotifier.instance;
    final profile = appState.profile;
    final userName = profile?['name'] as String? ?? '';
    final userRole = profile?['role'] as String? ?? 'guest';
    final isGuest = profile?['isGuest'] == true;

    final roleLabel = isGuest
        ? 'a guest (not signed in)'
        : userRole == 'artisan'
            ? 'an Artisan (service provider)'
            : 'a Customer (client)';

    final userContext = '\n\n## CURRENT CALLER'
        '\nThe person on this call is $roleLabel.'
        '${userName.isNotEmpty ? ' Their name is $userName.' : ''}'
        '\nTailor your answers to their role. For example:'
        '\n- If they are a Customer, help with finding artisans, booking, payments, posting jobs, and leaving reviews.'
        '\n- If they are an Artisan, help with managing services, KYC verification, receiving payments, withdrawals, applying for jobs, and their dashboard.'
        '\n- If they are a guest, let them know they need to create an account for most features, and guide them through signing up if they want to.'
        '${userName.isNotEmpty ? '\nAddress them by name when appropriate to make the conversation personal.' : ''}';

    debugPrint(
        '[GeminiLive] connecting to Gemini… (role=$userRole, name=$userName)');
    await _gemini.connect(
      systemInstruction: SupportKnowledgeBase.systemPrompt + userContext,
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
    _lastActivityTime = DateTime.now();
    _silenceWarningSent = false;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));

      if (_callState != _CallState.active) return;

      // 1. end_call is now handled in onTurnComplete (not here) so the
      //    grace period only starts after all audio has been delivered.

      // 2. AI requested escalation.
      if (_gemini.escalationRequested) {
        debugPrint('[CallLifecycle] AI requested escalation — showing dialog');
        setState(() => _callState = _CallState.escalating);
        _showEscalationDialog();
        return;
      }

      // 3. Max call duration reached — warn at 14min, end at 15min.
      if (_elapsed >= _maxCallDuration) {
        debugPrint(
            '[CallLifecycle] Max duration reached ($_maxCallDuration) — forcing wrap-up');
        _gemini.sendText(
          '[System: The call has reached the maximum duration. '
          'Please wrap up and say goodbye to the user.]',
        );
        // Give AI 15 seconds to say goodbye, then force end.
        Future.delayed(const Duration(seconds: 15), () {
          if (mounted && _callState == _CallState.active) {
            debugPrint(
                '[CallLifecycle] Force-ending call after 15s grace period');
            _endCall();
            Navigator.of(context).pop();
          }
        });
        return;
      }
      if (_elapsed == _maxCallDuration - const Duration(minutes: 1)) {
        debugPrint(
            '[CallLifecycle] 1 minute remaining — sending wrap-up prompt');
        _gemini.sendText(
          '[System: One minute remaining on this call. '
          'Start wrapping up and ask if the user needs anything else.]',
        );
      }

      // 4. Silence / inactivity timeout.
      final silenceDuration = DateTime.now().difference(_lastActivityTime);
      if (silenceDuration >= _silenceTimeout) {
        debugPrint(
            '[CallLifecycle] Silence timeout (${_silenceTimeout.inSeconds}s) — ending call');
        _endCall();
        if (mounted) Navigator.of(context).pop();
        return;
      }
      if (!_silenceWarningSent && silenceDuration >= _silenceWarningAt) {
        _silenceWarningSent = true;
        debugPrint(
            '[CallLifecycle] Silence warning at ${silenceDuration.inSeconds}s — prompting AI to check on user');
        _gemini.sendText(
          '[System: The user has been silent for a while. '
          'Ask if they are still there. If no response, the call will end soon.]',
        );
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
