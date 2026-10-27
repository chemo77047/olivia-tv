import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const dataBase = 'https://raw.githubusercontent.com/chemo77047/olivia-tv/main/data';

class StreamSource {
  final String url;
  final String? userAgent;
  final String? referrer;
  StreamSource(this.url, this.userAgent, this.referrer);

  Map<String, String> get headers => {
        if (userAgent != null) 'User-Agent': userAgent!,
        if (referrer != null) 'Referer': referrer!,
      };
}

class Channel {
  final String id;
  final String name;
  final String? logo;
  final String section;
  final bool kids;
  final List<StreamSource> streams;
  Channel(this.id, this.name, this.logo, this.section, this.kids, this.streams);

  factory Channel.fromJson(Map<String, dynamic> j) => Channel(
        j['id'] as String,
        j['name'] as String,
        j['logo'] as String?,
        j['section'] as String,
        j['kids'] == true,
        [
          for (final s in (j['streams'] as List))
            StreamSource(s['u'] as String, s['ua'] as String?, s['ref'] as String?)
        ],
      );
}

class Program {
  final DateTime start;
  final DateTime end;
  final String title;
  final String desc;
  final String category;
  Program(this.start, this.end, this.title, this.desc, this.category);

  bool isOnAt(DateTime t) => !start.isAfter(t) && end.isAfter(t);
}

Map<String, List<Program>> _parseGuide(List<int> gz) {
  final j = jsonDecode(utf8.decode(gzip.decode(gz))) as Map<String, dynamic>;
  final out = <String, List<Program>>{};
  (j['ch'] as Map<String, dynamic>).forEach((id, progs) {
    out[id] = [
      for (final p in progs as List)
        Program(
          DateTime.fromMillisecondsSinceEpoch((p[0] as int) * 1000),
          DateTime.fromMillisecondsSinceEpoch((p[1] as int) * 1000),
          p[2] as String,
          p[3] as String,
          p[4] as String,
        )
    ];
  });
  return out;
}

List<Channel> _parseChannels(String s) =>
    [for (final c in jsonDecode(s) as List) Channel.fromJson(c as Map<String, dynamic>)];

class Store {
  Store._();
  static final Store i = Store._();

  List<Channel> channels = [];
  Map<String, List<Program>> guide = {};
  late SharedPreferences _prefs;
  late Directory _dir;
  final Set<String> favorites = {};
  final Map<String, int> _failedAt = {};

  static const _hideFor = Duration(days: 3);

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _dir = await getApplicationSupportDirectory();
    favorites.addAll(_prefs.getStringList('favorites') ?? []);
    final failed = _prefs.getString('failed');
    if (failed != null) {
      (jsonDecode(failed) as Map<String, dynamic>).forEach((k, v) => _failedAt[k] = v as int);
    }
    await Future.wait([_loadChannels(), _loadGuide()]);
  }

  Future<List<int>?> _fetch(String name, File cache, Duration maxAge) async {
    if (cache.existsSync() && DateTime.now().difference(cache.lastModifiedSync()) < maxAge) {
      return cache.readAsBytes();
    }
    try {
      final r = await http.get(Uri.parse('$dataBase/$name')).timeout(const Duration(seconds: 25));
      if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
        await cache.writeAsBytes(r.bodyBytes, flush: true);
        return r.bodyBytes;
      }
    } catch (_) {}
    return cache.existsSync() ? cache.readAsBytes() : null;
  }

  Future<void> _loadChannels() async {
    final bytes = await _fetch('channels.json', File('${_dir.path}/channels.json'), const Duration(hours: 6));
    String? text;
    if (bytes != null) text = utf8.decode(bytes);
    try {
      channels = await compute(_parseChannels, text ?? await rootBundle.loadString('assets/channels.json'));
    } catch (_) {
      channels = await compute(_parseChannels, await rootBundle.loadString('assets/channels.json'));
    }
  }

  Future<void> _loadGuide() async {
    final bytes = await _fetch('guide.json.gz', File('${_dir.path}/guide.json.gz'), const Duration(hours: 4));
    if (bytes == null) return;
    try {
      guide = await compute(_parseGuide, bytes);
    } catch (_) {}
  }

  bool isHidden(String id) {
    final t = _failedAt[id];
    if (t == null) return false;
    return DateTime.now().millisecondsSinceEpoch - t < _hideFor.inMilliseconds;
  }

  void markFailed(String id) {
    _failedAt[id] = DateTime.now().millisecondsSinceEpoch;
    _prefs.setString('failed', jsonEncode(_failedAt));
  }

  void markWorking(String id) {
    if (_failedAt.remove(id) != null) _prefs.setString('failed', jsonEncode(_failedAt));
  }

  bool isFavorite(String id) => favorites.contains(id);

  void toggleFavorite(String id) {
    if (!favorites.remove(id)) favorites.add(id);
    _prefs.setStringList('favorites', favorites.toList());
  }

  String? get lastChannel => _prefs.getString('last');
  set lastChannel(String? id) => id == null ? _prefs.remove('last') : _prefs.setString('last', id);

  List<Program> programs(String id) => guide[id] ?? const [];

  Program? programAt(String id, DateTime t) {
    for (final p in programs(id)) {
      if (p.isOnAt(t)) return p;
    }
    return null;
  }

  Program? nextAfter(String id, DateTime t) {
    for (final p in programs(id)) {
      if (!p.start.isBefore(t)) return p;
    }
    return null;
  }

  List<Channel> section(String key, [String query = '']) {
    final visible = channels.where((c) => !isHidden(c.id));
    switch (key) {
      case 'fav':
        return visible.where((c) => favorites.contains(c.id)).toList();
      case 'kids':
        return visible.where((c) => c.kids).toList();
      case 'mx':
      case 'es':
      case 'us':
        return visible.where((c) => c.section == key).toList();
      case 'search':
        final q = fold(query);
        if (q.isEmpty) return [];
        return visible.where((c) => fold(c.name).contains(q)).toList();
      default:
        return visible.toList();
    }
  }
}

String fold(String s) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final k = from.indexOf(ch);
    b.write(k >= 0 ? to[k] : ch);
  }
  return b.toString().trim();
}

String hm(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
}

String dayLabel(DateTime t) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final now = DateTime.now();
  final d0 = DateTime(now.year, now.month, now.day);
  final d = DateTime(t.year, t.month, t.day);
  final diff = d.difference(d0).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  return days[t.weekday - 1];
}

bool isSelectKey(LogicalKeyboardKey k) =>
    k == LogicalKeyboardKey.select ||
    k == LogicalKeyboardKey.enter ||
    k == LogicalKeyboardKey.numpadEnter ||
    k == LogicalKeyboardKey.gameButtonA;
