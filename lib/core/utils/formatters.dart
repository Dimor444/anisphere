import 'package:timeago/timeago.dart' as timeago;

class Fmt {
  Fmt._();

  /// 1240 -> "1,240", 4821 -> "4,821"
  static String thousands(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i != 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  /// 18400 -> "18.4K", 720000 -> "720K", 1200000 -> "1.2M"
  static String compact(num n) {
    if (n < 1000) return n.toString();
    if (n < 1000000) {
      final v = n / 1000;
      return '${v.toStringAsFixed(v >= 100 ? 0 : 1)}K';
    }
    final v = n / 1000000;
    return '${v.toStringAsFixed(v >= 100 ? 0 : 1)}M';
  }

  static String timeAgo(DateTime t) => timeago.format(t, locale: 'en_short');

  /// milliseconds -> "12.480s"
  static String stopwatch(int ms) =>
      '${(ms / 1000).toStringAsFixed(3)}s';
}
