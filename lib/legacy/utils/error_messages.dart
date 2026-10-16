import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'status_mapper.dart';

class ErrorMessages {
  /// Convert various error forms into a short, user-friendly string.
  static String humanize(dynamic error, {String? context}) {
    try {
      if (error == null) {
        return 'Something went wrong. Please try again.';
      }

      if (error is TimeoutException) {
        return 'Request timed out. Please check your connection and try again.';
      }

      if (error is SocketException) {
        return 'No internet connection. Please check your network and try again.';
      }

      if (error is http.ClientException) {
        return 'We could not reach the server. Please check your connection and try again.';
      }

      if (error is FormatException) {
        return 'We received an unexpected response. Please try again.';
      }

      if (error is HandshakeException) {
        return 'Could not establish a secure connection. Please try again.';
      }

      if (error is TlsException) {
        return 'A secure connection could not be completed. Please try again.';
      }

      if (error is FileSystemException) {
        return 'We could not access that file. Please check it and try again.';
      }

      if (error is PathNotFoundException) {
        return 'The selected file could not be found.';
      }

      if (error is PlatformException) {
        return _humanizePlatformException(error);
      }

      // If it's already a string, try to decode JSON inside it or return trimmed string
      if (error is String) {
        final s = error.trim();
        // try JSON
        try {
          final decoded = jsonDecode(s);
          return _extractFromBody(decoded) ?? _shortFallback(s);
        } catch (_) {
          return _shortFallback(s);
        }
      }

      // If it's an Exception with message
      if (error is Exception) {
        final s = error.toString();
        // remove the leading "Exception: " if present
        final cleaned = s.replaceFirst(RegExp(r'^Exception:\s*'), '');
        // try parse possible JSON inside
        try {
          final decoded = jsonDecode(cleaned);
          return _extractFromBody(decoded) ?? _shortFallback(cleaned);
        } catch (_) {
          return _shortFallback(cleaned);
        }
      }

      // If it's an http.Response-like Map or decoded JSON object
      if (error is Map || error is List) {
        final extracted = _extractFromBody(error);
        if (extracted != null) return extracted;
      }

      // If it has a `message` property
      try {
        final msg = (error as dynamic).message;
        if (msg != null) return humanize(msg, context: context);
      } catch (_) {}

      try {
        final statusCode = (error as dynamic).statusCode;
        if (statusCode is int) return StatusMapper.getError(statusCode);
      } catch (_) {}

      // Fallback to toString
      final s = error.toString();
      return _shortFallback(s);
    } catch (_) {
      return 'Something went wrong. Please try again.';
    }
  }

  static String? _extractFromBody(dynamic decoded) {
    if (decoded == null) return null;
    if (decoded is String) return _shortFallback(decoded);
    if (decoded is Map) {
      // Common server shapes
      if (decoded.containsKey('statusCode') && decoded['statusCode'] is int) {
        return StatusMapper.getError(decoded['statusCode'] as int);
      }
      if (decoded.containsKey('message')) {
        return humanize(decoded['message']);
      }
      if (decoded.containsKey('error')) {
        final e = decoded['error'];
        if (e is String) return _shortFallback(e);
        if (e is Map && e.containsKey('message')) return humanize(e['message']);
      }
      if (decoded.containsKey('errors')) {
        final errs = decoded['errors'];
        if (errs is Map) {
          // Join first field errors
          for (final v in errs.values) {
            if (v is String) return _shortFallback(v);
            if (v is List && v.isNotEmpty) return humanize(v.first);
          }
        }
        if (errs is List && errs.isNotEmpty) return humanize(errs.first);
      }
      // Try nested data.message
      if (decoded.containsKey('data') && decoded['data'] is Map) {
        final d = decoded['data'];
        if (d.containsKey('message')) return humanize(d['message']);
      }
    }
    return null;
  }

  static String _humanizePlatformException(PlatformException error) {
    final code = error.code.toLowerCase();
    final message = (error.message ?? '').toLowerCase();

    if (code.contains('camera_access_denied') ||
        code.contains('photo_access_denied') ||
        code.contains('permission') ||
        message.contains('permission')) {
      return 'Permission was denied. Please enable access in your device settings and try again.';
    }

    if (code.contains('network') || message.contains('network')) {
      return 'A network problem occurred. Please try again.';
    }

    if (code.contains('sign_in_canceled') ||
        code.contains('cancel') ||
        message.contains('cancelled')) {
      return 'The action was cancelled.';
    }

    return 'This action could not be completed on your device. Please try again.';
  }

  static String _shortFallback(String s) {
    if (s.isEmpty) return 'Something went wrong. Please try again.';

    // Recognize some common server messages and remap to friendlier text
    final normalized = s.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    if (normalized.isEmpty) return 'Something went wrong. Please try again.';

    final lc = normalized.toLowerCase();

    final statusMatch = RegExp(r'\b(4\d\d|5\d\d|3\d\d)\b').firstMatch(lc);
    if (statusMatch != null) {
      final parsed = int.tryParse(statusMatch.group(1)!);
      if (parsed != null) {
        return parsed >= 400
            ? StatusMapper.getError(parsed)
            : StatusMapper.getMessage(parsed);
      }
    }

    // Detect HTTP 413 / "Request Entity Too Large" responses which may come back as
    // plain text, JSON, or verbose HTML from nginx. Map to a clear user-facing message.
    if (lc.contains('request entity too large') ||
        lc.contains('413 request') ||
        (RegExp(r'\b413\b').hasMatch(lc) &&
            (lc.contains('request') ||
                lc.contains('entity') ||
                lc.contains('<html')))) {
      return 'The file you tried to upload is too large. Please choose a smaller image or compress it and try again.';
    }

    if (lc.contains('artisan profile not found'))
      return 'We could not find your artisan profile. Please complete your artisan registration.';
    if (lc.contains('invalid image data') || lc.contains('invalid image'))
      return 'Failed to load an image. Please try again.';
    if (lc.contains('missing auth token') ||
        lc.contains('not authenticated') ||
        lc.contains('session expired'))
      return 'Your session has expired. Please sign in again.';
    if (lc.contains('401') ||
        lc.contains('unauthorized') ||
        lc.contains('not authenticated'))
      return 'You are not authenticated. Please sign in again.';
    if (lc.contains('403') ||
        lc.contains('forbidden') ||
        lc.contains('permission'))
      return 'You do not have permission to do this.';
    if (lc.contains('404') || lc.contains('not found'))
      return 'Requested resource not found.';
    if (lc.contains('409') ||
        lc.contains('already exists') ||
        lc.contains('duplicate'))
      return 'This already exists or conflicts with existing data.';
    if (lc.contains('422') || lc.contains('validation'))
      return 'Please correct the highlighted information and try again.';
    if (lc.contains('429') ||
        lc.contains('too many requests') ||
        lc.contains('rate limit'))
      return 'Too many requests. Please wait a moment and try again.';
    if (lc.contains('500') || lc.contains('internal server error'))
      return 'Something went wrong on our end. Please try again.';
    if (lc.contains('502') ||
        lc.contains('503') ||
        lc.contains('504') ||
        lc.contains('bad gateway') ||
        lc.contains('service unavailable') ||
        lc.contains('gateway timeout')) {
      return 'The service is temporarily unavailable. Please try again shortly.';
    }
    if (lc.contains('timeout')) return 'Request timed out. Please try again.';
    if (lc.contains('socketexception') ||
        (lc.contains('network') && lc.contains('error')))
      return 'Network error. Please check your internet connection and try again.';
    if (lc.contains('clientexception'))
      return 'Could not connect to the server. Please try again.';
    if (lc.contains('formatexception') ||
        lc.contains('unexpected response format'))
      return 'We received an unexpected response. Please try again.';
    if (lc.contains('handshakeexception') ||
        lc.contains('certificate') ||
        lc.contains('tls'))
      return 'A secure connection could not be established. Please try again.';
    if (lc.contains('file not found') || lc.contains('pathnotfoundexception'))
      return 'The selected file could not be found.';
    if (lc.contains('unsupported') && lc.contains('file'))
      return 'This file type is not supported.';
    if (lc.contains('too large') && lc.contains('file'))
      return 'The selected file is too large. Please choose a smaller file.';
    if (lc.contains('json'))
      return 'We received data in an unexpected format. Please try again.';
    if (lc.contains('cancelled') || lc.contains('canceled'))
      return 'The action was cancelled.';
    if (lc.contains('socket') && lc.contains('disconnected'))
      return 'Realtime connection lost. Some features may be unavailable.';
    if (lc.contains('job id required') || lc.contains('job id not found'))
      return 'We could not find that job. Please refresh and try again.';
    if (lc.contains('profile image file not found'))
      return 'We could not find the selected profile image. Please choose it again.';
    if (lc.contains('upload failed'))
      return 'The upload could not be completed. Please try again.';
    if (lc.contains('failed to fetch'))
      return 'We could not load the requested data. Please try again.';
    if (lc.contains('unable to fetch'))
      return 'We could not load the requested data. Please try again.';
    if (lc.contains('failed to update'))
      return 'We could not save your changes. Please try again.';
    if (lc.contains('failed to delete'))
      return 'We could not delete that item. Please try again.';
    if (lc.contains('failed to create'))
      return 'We could not complete that action. Please try again.';
    if (lc.length > 200) return '${normalized.substring(0, 200)}...';

    return normalized;
  }
}
