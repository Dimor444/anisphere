import 'dart:convert';
import 'dart:io';

import 'package:anisphere/core/constants/app_languages.dart';
import 'package:flutter_test/flutter_test.dart';

/// The plural categories intl's rule for each language can select
/// (intl/src/plural_rules.dart); a plural must give every one of them.
/// Spanish and French "many" is an exact million ("1 000 000 de …").
const _pluralCategories = <String, Set<String>>{
  'ar': {'zero', 'one', 'two', 'few', 'many', 'other'},
  'en': {'one', 'other'},
  'es': {'one', 'many', 'other'},
  'fr': {'one', 'many', 'other'},
  'tr': {'one', 'other'},
  'ja': {'other'},
  'ko': {'other'},
  'id': {'other'},
};

/// The permission prompts Info.plist has — English, the source — and the
/// languages it declares.
Set<String> _promptKeys() => {
      for (final m in RegExp(r'<key>(NS\w+UsageDescription)</key>').allMatches(File('ios/Runner/Info.plist').readAsStringSync()))
        m.group(1)!,
    };

/// A language's InfoPlist.strings: `"Key" = "text";` per line.
Map<String, String> _prompts(String code) {
  final file = File('ios/Runner/$code.lproj/InfoPlist.strings');
  if (!file.existsSync()) return const {};
  return {
    for (final m in RegExp(r'^"(\w+)"\s*=\s*"((?:[^"\\]|\\.)*)";', multiLine: true).allMatches(file.readAsStringSync()))
      m.group(1)!: m.group(2)!,
  };
}

Map<String, String> _messages(String code) => {
      for (final MapEntry(:key, :value)
          in (jsonDecode(File('lib/l10n/app_$code.arb').readAsStringSync()) as Map<String, dynamic>).entries)
        if (!key.startsWith('@')) key: value as String,
    };

/// What an ICU message uses: every argument — `{name}`, `{n, plural, …}`,
/// `{s, select, …}` — and, per plural argument, the categories it gives
/// (explicit `=N` cases are not categories).
class _Icu {
  final args = <String>{};
  final plurals = <String, Set<String>>{};
}

_Icu _parse(String m) {
  final icu = _Icu();
  var i = 0;
  String readUntil(String stops) {
    final start = i;
    while (i < m.length && !stops.contains(m[i])) {
      i++;
    }
    return m.substring(start, i).trim();
  }

  late void Function(bool nested) message;
  void argument() {
    final name = readUntil(',}');
    if (i >= m.length) throw const FormatException('an argument is never closed');
    icu.args.add(name);
    if (m[i++] == '}') return;
    final type = readUntil(',}');
    if (i >= m.length) throw FormatException('{$name, $type is never closed');
    if (m[i++] == '}') return;
    if (type != 'plural' && type != 'select') {
      readUntil('}');
      i++;
      return;
    }
    final cases = <String>{};
    while (true) {
      while (i < m.length && m[i].trim().isEmpty) {
        i++;
      }
      if (i >= m.length) throw FormatException('{$name, $type} is never closed');
      if (m[i] == '}') {
        i++;
        break;
      }
      cases.add(readUntil('{'));
      if (i >= m.length) throw FormatException('a case of {$name, $type} has no body');
      i++;
      message(true);
      i++;
    }
    if (type == 'plural') icu.plurals[name] = cases.where((c) => !c.startsWith('=')).toSet();
  }

  message = (nested) {
    while (i < m.length) {
      if (m[i] == '{') {
        i++;
        argument();
      } else if (m[i] == '}') {
        if (nested) return;
        throw FormatException('an unmatched } at $i');
      } else {
        i++;
      }
    }
    if (nested) throw const FormatException('a case is never closed');
  };
  message(false);
  return icu;
}

/// The gate. It reads the ARB files themselves, not the generated class:
/// that shows English for a message a language lacks, and can be stale.
void main() {
  test('every language has every message, the same placeholders, and the plural categories it needs', () {
    final template = _messages('en');
    final problems = <String>[];
    for (final lang in AppLanguages.all) {
      final code = lang.code;
      final messages = code == 'en' ? template : _messages(code);
      final needs = _pluralCategories[code];
      if (needs == null) {
        problems.add('$code: no plural categories listed for this language');
        continue;
      }
      for (final MapEntry(key: key, value: english) in template.entries) {
        final text = messages[key];
        if (text == null || text.trim().isEmpty) {
          problems.add('$code.$key: missing');
          continue;
        }
        final _Icu want, got;
        try {
          want = _parse(english);
          got = _parse(text);
        } on FormatException catch (e) {
          problems.add('$code.$key: not valid ICU — ${e.message}');
          continue;
        }
        if (!(got.args.containsAll(want.args) && want.args.containsAll(got.args))) {
          problems.add('$code.$key: placeholders ${got.args.toList()..sort()}, English has ${want.args.toList()..sort()}');
        }
        for (final MapEntry(key: arg, value: cases) in got.plurals.entries) {
          final lacking = needs.difference(cases);
          if (lacking.isNotEmpty) {
            problems.add('$code.$key: plural {$arg} lacks ${lacking.toList()..sort()}');
          }
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('every language has every iOS permission prompt, and the bundle declares the eight', () {
    final keys = _promptKeys();
    final problems = <String>[];
    if (keys.isEmpty) problems.add('Info.plist has no permission prompts — the pattern no longer matches it');
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final declared = RegExp(r'<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>', dotAll: true)
        .firstMatch(plist)
        ?.group(1);
    final codes = {for (final m in RegExp(r'<string>(\w+)</string>').allMatches(declared ?? '')) m.group(1)!};
    final app = {for (final l in AppLanguages.all) l.code};
    if (!(codes.containsAll(app) && app.containsAll(codes))) {
      problems.add('CFBundleLocalizations is ${codes.toList()}, the app has ${app.toList()}');
    }
    for (final code in app.where((c) => c != 'en')) {
      final prompts = _prompts(code);
      for (final key in keys) {
        if ((prompts[key] ?? '').trim().isEmpty) problems.add('$code: $key missing');
      }
      for (final key in prompts.keys.toSet().difference(keys)) {
        problems.add('$code: $key is not a prompt Info.plist has');
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  // lib/l10n/translation_review.json says who wrote each translation and
  // whether a native reader has read it; it is only true while it lists
  // exactly the messages there are.
  test('the review record lists every translated message and iOS prompt, and nothing else', () {
    final record = jsonDecode(File('lib/l10n/translation_review.json').readAsStringSync()) as Map<String, dynamic>;
    final languages = record['languages'] as Map<String, dynamic>;
    final template = _messages('en').keys.toSet();
    final problems = <String>[];
    final translated = {for (final l in AppLanguages.all) if (l.code != 'en') l.code};
    if (!(languages.keys.toSet().containsAll(translated) && translated.containsAll(languages.keys))) {
      problems.add('languages ${languages.keys.toList()}, the app has ${translated.toList()}');
    }
    for (final MapEntry(key: code, value: entry) in languages.entries) {
      final lang = entry as Map<String, dynamic>;
      if (lang['gatesLaunch'] != (code == 'ar')) problems.add('$code: gatesLaunch is ${lang['gatesLaunch']}');
      final messages = lang['messages'] as Map<String, dynamic>;
      for (final key in template.difference(messages.keys.toSet())) {
        problems.add('$code.$key: not in the record');
      }
      for (final key in messages.keys.toSet().difference(template)) {
        problems.add('$code.$key: in the record but not in the ARB files');
      }
      final prompts = (lang['iosPrompts'] as Map<String, dynamic>?) ?? const {};
      final promptKeys = _promptKeys();
      if (!(prompts.keys.toSet().containsAll(promptKeys) && promptKeys.containsAll(prompts.keys))) {
        problems.add('$code: iosPrompts ${prompts.keys.toList()}, Info.plist has ${promptKeys.toList()}');
      }
      for (final MapEntry(:key, :value) in {...messages, ...prompts}.entries) {
        final m = value as Map<String, dynamic>;
        if (!const {'assistant', 'person'}.contains(m['writtenBy'])) problems.add('$code.$key: writtenBy ${m['writtenBy']}');
        if (m['nativeRead'] is! bool) problems.add('$code.$key: nativeRead ${m['nativeRead']}');
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
