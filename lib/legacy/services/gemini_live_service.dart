import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:gemini_live/gemini_live.dart';

/// Service that manages a real-time voice conversation with Google's
/// Gemini Multimodal Live API using the `gemini_live` package.
class GeminiLiveService {
  GeminiLiveService({
    required String apiKey,
    String model = 'gemini-3.1-flash-live-preview',
  })  : _apiKey = apiKey,
        _model = model;

  final String _apiKey;
  final String _model;

  GoogleGenAI? _genAI;
  LiveSession? _session;
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  // Session generation counter — incremented on every disconnect().
  // Each connect() captures the current value; onClose/onError ignore
  // callbacks from older (stale) sessions, breaking the reconnect loop.
  int _sessionGeneration = 0;

  // Cached for auto-reconnect.
  String _cachedSystemInstruction = '';
  String _cachedVoiceName = 'Charon';

  // --------------- callbacks ---------------
  void Function(Uint8List audioData)? onAudioReceived;
  void Function(String text)? onTextReceived;
  void Function()? onTurnComplete;
  void Function()? onSetupComplete;
  void Function(String error)? onError;
  void Function()? onDisconnected;

  bool _escalationRequested = false;
  bool get escalationRequested => _escalationRequested;

  bool _endCallRequested = false;
  bool get endCallRequested => _endCallRequested;

  // Mic suppression: true while model is speaking (echo suppression),
  // during playback, or after an audioStreamEnd nudge.
  bool _micSuppressed = false;

  /// Let the widget control mic suppression (e.g. during local playback).
  /// When the mic is re-enabled (playback done), the response timer starts
  /// so the user gets the full timeout window to speak.
  set micSuppressed(bool value) {
    _micSuppressed = value;
    if (!value && _isConnected) {
      // Mic just became active — (re)start the response timer now.
      _startResponseTimer();
    }
  }

  Timer? _sessionTimer;

  // Safety timer: if the model hasn't responded N seconds after its last
  // turn completed, send audioStreamEnd to force the server's VAD to
  // process the input (covers noisy environments where VAD can't detect
  // silence). The mic streams continuously (even silence), so we can't
  // distinguish "user is speaking" from "mic is idle" — we simply use a
  // generous timeout so the user has plenty of time to speak.
  Timer? _responseTimer;
  static const _responseTimeout = Duration(seconds: 8);

  void _startResponseTimer() {
    _responseTimer?.cancel();
    _responseTimer = Timer(_responseTimeout, () {
      if (_isConnected && _session != null && !_micSuppressed) {
        debugPrint('[GeminiLive] response timeout (${_responseTimeout.inSeconds}s) — sending audioStreamEnd nudge');
        _micSuppressed = true;
        try {
          _session!.sendAudioStreamEnd();
        } catch (e) {
          debugPrint('[GeminiLive] audioStreamEnd nudge failed: $e');
        }
      }
    });
  }

  // Retry state.
  int _retryCount = 0;
  static const _maxRetries = 3;
  static const _retryDelay = Duration(seconds: 2);

  // --------------- connect ---------------

  Future<void> connect({
    required String systemInstruction,
    String voiceName = 'Charon',
  }) async {
    _escalationRequested = false;
    _cachedSystemInstruction = systemInstruction;
    _cachedVoiceName = voiceName;

    // Capture the generation at the start of THIS connect attempt.
    // If disconnect() is called before our onClose fires, generation increments
    // and our callbacks become stale — they will be ignored.
    final myGen = _sessionGeneration;

    debugPrint('[GeminiLive] connecting (attempt ${_retryCount + 1}) model=$_model gen=$myGen');

    try {
      _genAI = GoogleGenAI(apiKey: _apiKey);

      // connect() is async — it resolves only after the setup handshake
      // completes, so when it returns we are ready to stream.
      _session = await _genAI!.live.connect(
        LiveConnectParameters(
          model: _model,
          config: GenerationConfig(
            responseModalities: [Modality.AUDIO],
            speechConfig: SpeechConfig(
              voiceConfig: VoiceConfig(
                prebuiltVoiceConfig: PrebuiltVoiceConfig(voiceName: voiceName),
              ),
            ),
          ),
          systemInstruction: Content(
            parts: [Part(text: systemInstruction)],
          ),
          tools: [
            Tool(
              functionDeclarations: [
                FunctionDeclaration(
                  name: 'escalate_to_human',
                  description:
                      'Call this function when the user explicitly asks to speak '
                      'with a real person or when you are unable to resolve '
                      'their issue after a reasonable attempt.',
                  parameters: {
                    'type': 'OBJECT',
                    'properties': {
                      'reason': {
                        'type': 'STRING',
                        'description': 'Brief reason for escalation',
                      }
                    },
                    'required': ['reason'],
                  },
                ),
                FunctionDeclaration(
                  name: 'end_call',
                  description:
                      'End the support call. ONLY call this when the user has '
                      'EXPLICITLY said goodbye, said they are done, or asked '
                      'to end the call. Examples: "bye", "goodbye", "that\'s '
                      'all thanks", "I\'m done", "end the call", "hang up". '
                      'Do NOT call this just because you answered a question. '
                      'Do NOT call this proactively. ALWAYS ask "Is there '
                      'anything else I can help with?" first and wait for the '
                      'user to confirm they are done before calling this.',
                  parameters: {
                    'type': 'OBJECT',
                    'properties': {
                      'reason': {
                        'type': 'STRING',
                        'description':
                            'Brief reason for ending (e.g. "user_said_goodbye", '
                            '"user_said_done", "user_requested_end")',
                      }
                    },
                    'required': ['reason'],
                  },
                ),
              ],
            ),
          ],
          callbacks: LiveCallbacks(
            onOpen: () {
              debugPrint('[GeminiLive] WebSocket opened');
            },
            onMessage: (LiveServerMessage message) {
              if (myGen != _sessionGeneration) return; // stale session
              _handleMessage(message);
            },
            onError: (Object error, StackTrace stackTrace) {
              if (myGen != _sessionGeneration) return; // stale session
              debugPrint('[GeminiLive] stream error: $error');
              if (_isConnected) {
                onError?.call(error.toString());
              }
            },
            onClose: (int? code, String? reason) {
              debugPrint('[GeminiLive] closed gen=$myGen current=$_sessionGeneration (code=$code, reason=$reason)');
              // If generation doesn't match, this is a stale close from an old
              // session that fired AFTER reconnect() established a new one.
              // Firing onDisconnected here would cause an infinite loop.
              if (myGen != _sessionGeneration) {
                debugPrint('[GeminiLive] ignoring stale onClose — new session already active');
                return;
              }
              final wasConnected = _isConnected;
              _cleanup();
              if (wasConnected) {
                onDisconnected?.call();
              }
            },
          ),
        ),
      );

      // If we reach here, setup handshake succeeded.
      _isConnected = true;
      _retryCount = 0;
      debugPrint('[GeminiLive] setup complete — session active');
      onSetupComplete?.call();

      // Trigger the model's greeting via realtimeInput text.
      // We use sendRealtimeText (goes through the realtimeInput path which
      // works) rather than sendText/clientContent (causes 1007).
      // The recorder is deliberately not started yet so there is no
      // competing audio stream — it starts after the first onTurnComplete.
      try {
        _session!.sendRealtimeText(
          'The user has just connected. Please greet them now.',
        );
        debugPrint('[GeminiLive] greeting trigger (realtimeText) sent');
      } catch (e) {
        debugPrint('[GeminiLive] greeting trigger failed: $e');
      }

      // Auto-reconnect before the ~15 min server timeout.
      _sessionTimer?.cancel();
      _sessionTimer = Timer(const Duration(minutes: 14), () {
        debugPrint('[GeminiLive] session refresh (14 min)');
        disconnect();
        connect(systemInstruction: systemInstruction, voiceName: voiceName);
      });
    } catch (e) {
      debugPrint('[GeminiLive] connection/setup failed: $e');
      _handleConnectionFailure('Connection failed: $e');
    }
  }

  void _handleConnectionFailure(String reason) {
    _sessionTimer?.cancel();
    _responseTimer?.cancel();
    _cleanup();
    if (_retryCount < _maxRetries) {
      _retryCount++;
      final delay = _retryDelay * _retryCount;
      debugPrint(
        '[GeminiLive] retrying in ${delay.inSeconds}s '
        '(attempt $_retryCount/$_maxRetries)',
      );
      Future.delayed(delay, () {
        connect(
          systemInstruction: _cachedSystemInstruction,
          voiceName: _cachedVoiceName,
        );
      });
    } else {
      debugPrint('[GeminiLive] all $_maxRetries retries exhausted');
      onError?.call(reason);
    }
  }

  // --------------- send audio ---------------

  int _audioChunksSent = 0;

  void sendAudioChunk(Uint8List pcm16kHz) {
    if (!_isConnected || _session == null) return;
    // Suppress mic audio while the model is speaking to prevent echo
    // from triggering VAD interruptions.
    if (_micSuppressed) return;
    try {
      _session!.sendAudio(pcm16kHz);
      _audioChunksSent++;
      if (_audioChunksSent % 50 == 1) {
        debugPrint('[GeminiLive] mic→server chunk #$_audioChunksSent '
            '(${pcm16kHz.length} bytes)');
      }
    } catch (e) {
      debugPrint('[GeminiLive] sendAudioChunk failed: $e');
    }
  }

  // --------------- send text ---------------

  void sendText(String text) {
    if (!_isConnected || _session == null) return;
    try {
      _session!.sendText(text);
    } catch (e) {
      debugPrint('[GeminiLive] sendText failed: $e');
    }
  }

  // --------------- handle messages ---------------

  int _audioChunksReceived = 0;
  int _turnCount = 0;

  void _handleMessage(LiveServerMessage message) {
    try {
      // Tool call (escalation)
      if (message.toolCall != null) {
        debugPrint('[GeminiLive] ← toolCall received');
        _handleToolCall(message);
        // Don't return — the same message might carry other fields too.
      }

      // Check for interruption flag.
      if (message.serverContent?.interrupted == true) {
        debugPrint('[GeminiLive] ⚠ model was INTERRUPTED by user speech');
      }

      // Audio data (base64 inline data from model)
      if (message.data != null) {
        _micSuppressed = true; // suppress mic echo
        _responseTimer?.cancel(); // model is responding, no need for nudge
        final audioBytes = Uint8List.fromList(base64Decode(message.data!));
        _audioChunksReceived++;
        if (_audioChunksReceived % 20 == 1) {
          debugPrint('[GeminiLive] ← audio chunk #$_audioChunksReceived '
              '(${audioBytes.length} bytes)');
        }
        onAudioReceived?.call(audioBytes);
      }

      // Text data
      if (message.text != null) {
        debugPrint('[GeminiLive] ← text: "${message.text}"');
        onTextReceived?.call(message.text!);
      }

      // Turn complete — check AFTER processing audio/text so nothing is skipped.
      // NOTE: mic stays suppressed here — the widget unsuppresses it after
      // local playback finishes to prevent echo.
      if (message.serverContent?.turnComplete == true) {
        _turnCount++;
        debugPrint('[GeminiLive] ← turnComplete #$_turnCount '
            '(received $_audioChunksReceived audio chunks total)');
        _audioChunksReceived = 0;
        onTurnComplete?.call();
        // Response timer is NOT started here — it starts when the widget
        // unsuppresses the mic after local playback finishes.
      }

      // Go-away warning (server about to close).
      if (message.goAway != null) {
        debugPrint('[GeminiLive] ⚠ server go-away received');
      }
    } catch (e) {
      debugPrint('[GeminiLive] message handling error: $e');
    }
  }

  void _handleToolCall(LiveServerMessage message) {
    try {
      final toolCall = message.toolCall;
      if (toolCall == null) return;
      final calls = toolCall.functionCalls;
      if (calls == null) return;

      for (final call in calls) {
        if (call.name == 'escalate_to_human') {
          _escalationRequested = true;
          debugPrint('[GeminiLive] escalation requested by AI');
          _session?.sendFunctionResponse(
            id: call.id ?? '',
            name: 'escalate_to_human',
            response: {'result': 'Connecting user to human support now.'},
          );
        } else if (call.name == 'end_call') {
          _endCallRequested = true;
          debugPrint('[GeminiLive] end_call requested by AI: ${call.args}');
          _session?.sendFunctionResponse(
            id: call.id ?? '',
            name: 'end_call',
            response: {'result': 'Ending the call now. Goodbye.'},
          );
        }
      }
    } catch (e) {
      debugPrint('[GeminiLive] toolCall handling error: $e');
    }
  }

  // --------------- reconnect ---------------

  /// Reconnect using the cached system instruction + voice.
  /// Safe to call even if already connected — it disconnects first.
  Future<void> reconnect() async {
    debugPrint('[GeminiLive] reconnect requested (isConnected=$_isConnected)');
    _retryCount = 0;
    disconnect();
    await connect(
      systemInstruction: _cachedSystemInstruction,
      voiceName: _cachedVoiceName,
    );
  }

  /// Send a no-op audio chunk to probe the WebSocket.
  /// Returns true if the send succeeds (connection alive).
  bool probeConnection() {
    if (!_isConnected || _session == null) {
      debugPrint('[GeminiLive] probe: not connected');
      return false;
    }
    try {
      // Send a tiny silence frame (2 bytes of zero = one PCM sample).
      _session!.sendAudio(Uint8List(2));
      debugPrint('[GeminiLive] probe: connection alive');
      return true;
    } catch (e) {
      debugPrint('[GeminiLive] probe: connection dead ($e)');
      _cleanup();
      return false;
    }
  }

  // --------------- disconnect ---------------

  void disconnect() {
    debugPrint('[GeminiLive] disconnect requested (gen=$_sessionGeneration)');
    // Increment generation FIRST so any pending onClose from the current
    // session is treated as stale and does not fire onDisconnected.
    _sessionGeneration++;
    _sessionTimer?.cancel();
    _responseTimer?.cancel();
    try {
      _session?.close();
    } catch (_) {}
    _cleanup();
    _genAI?.close();
    _genAI = null;
  }

  void _cleanup() {
    _isConnected = false;
    _session = null;
  }
}
