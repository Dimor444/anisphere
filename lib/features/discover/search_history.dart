import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Recent-search persistence for Discover's Search tab.
///
/// Entries are saved only for COMPLETED searches (result tapped or keyboard
/// submit) — never from the debounced live-search path, which fires on every
/// typing pause and would litter history with keystroke fragments.
class SearchHistory {
  SearchHistory._();

  static const String _key = 'search_history_v2';

  /// v1 saved on every debounced fetch — full of fragments ("dr. s", "dr. st",
  /// …). Migrated once through [sanitize], then removed.
  static const String _legacyKey = 'search_history_v1';

  static const int max = 8;
  static const int minChars = 2;

  /// Load history, migrating (and de-fragmenting) v1 data on first run.
  static Future<List<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v2 = prefs.getStringList(_key);
      if (v2 != null) return v2;

      final legacy = prefs.getStringList(_legacyKey);
      if (legacy == null) return const [];
      final cleaned = sanitize(legacy);
      await prefs.setStringList(_key, cleaned);
      await prefs.remove(_legacyKey);
      return cleaned;
    } catch (_) {
      return const [];
    }
  }

  /// Record a completed search: front insertion, case-insensitive dedupe,
  /// capped at [max]. Returns the updated list (also persisted).
  static Future<List<String>> add(String term, List<String> current) async {
    final updated = addTo(current, term);
    if (!listEquals(updated, current)) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_key, updated);
      } catch (_) {}
    }
    return updated;
  }

  /// Pure version of [add] — junk-guarded (trims; rejects under [minChars]).
  @visibleForTesting
  static List<String> addTo(List<String> current, String term) {
    final t = term.trim();
    if (t.length < minChars) return current;
    final lower = t.toLowerCase();
    return [t, ...current.where((h) => h.trim().toLowerCase() != lower)].take(max).toList();
  }

  /// Clean a raw list: trim, drop under-length entries, drop entries that are
  /// a proper prefix of another entry (keystroke fragments), dedupe
  /// case-insensitively keeping the newest, cap at [max].
  @visibleForTesting
  static List<String> sanitize(List<String> raw) {
    final result = <String>[];
    for (final e in raw) {
      final t = e.trim();
      if (t.length < minChars) continue;
      final lower = t.toLowerCase();
      final isFragment = raw.any((o) {
        final ol = o.trim().toLowerCase();
        return ol != lower && ol.startsWith(lower);
      });
      if (isFragment) continue;
      if (result.any((r) => r.trim().toLowerCase() == lower)) continue;
      result.add(t);
    }
    return result.take(max).toList();
  }
}
