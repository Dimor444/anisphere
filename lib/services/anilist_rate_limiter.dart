import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Global limiter for AniList GraphQL traffic.
///
/// AniList enforces ~30 requests/minute (response header `x-ratelimit-limit: 30`).
/// The True Fan cover grid alone can burst past that, which then 429s the
/// gameplay-critical character/search requests and leaves the quiz with no real
/// characters. This serializes AniList traffic inside a 60-second sliding
/// window, reserves headroom for high-priority gameplay requests so they never
/// get starved by cover thumbnails, and backs off on HTTP 429.
class AniListRateLimiter {
  AniListRateLimiter._();

  /// Shared singleton — one budget for all AniList traffic in the app.
  static final AniListRateLimiter instance = AniListRateLimiter._();

  static const Duration _window = Duration(seconds: 60);
  static const int _hardCap = 27; // never exceed this many requests / window
  static const int _lowPriorityCap = 21; // covers stop here → ~6 reserved for gameplay

  final Queue<_Job> _high = Queue<_Job>();
  final Queue<_Job> _low = Queue<_Job>();
  final Queue<DateTime> _recent = Queue<DateTime>(); // request times within the window
  bool _draining = false;

  /// Runs [request] under the AniList rate budget. High-[priority] requests
  /// (gameplay: characters, search, the result-card cover) jump ahead of — and
  /// out-reserve — low-priority cover thumbnails.
  Future<http.Response> send(Future<http.Response> Function() request, {bool priority = false}) {
    final job = _Job(request);
    (priority ? _high : _low).add(job);
    _drain();
    return job.completer.future;
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_high.isNotEmpty || _low.isNotEmpty) {
        _prune();
        final used = _recent.length;

        _Job? job;
        if (_high.isNotEmpty && used < _hardCap) {
          job = _high.removeFirst();
        } else if (_low.isNotEmpty && used < _lowPriorityCap) {
          job = _low.removeFirst();
        }

        if (job == null) {
          // No slot for the highest-eligible job yet — wait for the window to free.
          await Future<void>.delayed(const Duration(milliseconds: 500));
          continue;
        }

        _recent.add(DateTime.now());
        unawaited(_execute(job));
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _execute(_Job job) async {
    try {
      var res = await job.request();
      var attempts = 0;
      while (res.statusCode == 429 && attempts < 2) {
        attempts++;
        final wait = _retryAfter(res);
        debugPrint('[AniListRateLimiter] HTTP 429 — backing off ${wait.inSeconds}s (attempt $attempts).');
        await Future<void>.delayed(wait);
        res = await job.request();
      }
      job.completer.complete(res);
    } catch (e, st) {
      job.completer.completeError(e, st);
    }
  }

  void _prune() {
    final cutoff = DateTime.now().subtract(_window);
    while (_recent.isNotEmpty && _recent.first.isBefore(cutoff)) {
      _recent.removeFirst();
    }
  }

  Duration _retryAfter(http.Response res) {
    final secs = int.tryParse(res.headers['retry-after'] ?? '');
    if (secs != null) return Duration(seconds: secs.clamp(1, 60));
    return const Duration(seconds: 3);
  }
}

class _Job {
  final Future<http.Response> Function() request;
  final Completer<http.Response> completer = Completer<http.Response>();
  _Job(this.request);
}
