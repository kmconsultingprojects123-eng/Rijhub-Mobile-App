import 'dart:async';

// Simple broadcast stream for job update events. Listeners can subscribe and
// receive the updated job Map whenever a job is created or updated.
class JobEvents {
  JobEvents._();
  static final _controller = StreamController<Map<String, dynamic>>.broadcast();

  static void emitJobUpdated(Map<String, dynamic> job) {
    try {
      _controller.add(Map<String, dynamic>.from(job));
    } catch (_) {
      try { _controller.add(job); } catch (_) {}
    }
  }

  static Stream<Map<String, dynamic>> get jobUpdatedStream => _controller.stream;

  // Optional: call this on app teardown to close the stream.
  static Future<void> dispose() async {
    try { await _controller.close(); } catch (_) {}
  }
}

