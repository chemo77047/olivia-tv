import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data.dart';
import 'main.dart';
import 'player_screen.dart';

const _sections = [
  ('fav', 'Favorites', Icons.star_rounded),
  ('kids', 'Kids', Icons.child_care_rounded),
  ('mx', 'México', Icons.flag_rounded),
  ('es', 'Español (US)', Icons.translate_rounded),
  ('us', 'US', Icons.live_tv_rounded),
  ('all', 'All Channels', Icons.apps_rounded),
  ('search', 'Search', Icons.search_rounded),
];

const _rowH = 54.0;
const _chanW = 190.0;
const _headerH = 30.0;
const _windowMin = 120;
const _stepMin = 30;

class GuideScreen extends StatefulWidget {
  final bool resumeLast;
  const GuideScreen({super.key, this.resumeLast = false});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  final store = Store.i;
  late String section;
  String query = '';
  List<Channel> list = [];
  int row = 0;
  DateTime cursor = DateTime.now();
  late DateTime winStart;
  final gridFocus = FocusNode(debugLabel: 'grid');
  final railFocus = [for (final _ in _sections) FocusNode()];
  final scroll = ScrollController();
  Timer? clock;
  DateTime now = DateTime.now();
  bool selectDown = false;
  bool longFired = false;

  @override
  void initState() {
    super.initState();
    section = store.favorites.isNotEmpty ? 'fav' : 'all';
    winStart = _floor(now);
    _refresh();
    clock = Timer.periodic(const Duration(seconds: 30), (_) {
      setState(() {
        now = DateTime.now();
        if (cursor.isBefore(now)) cursor = now;
        if (winStart.isBefore(_floor(now))) winStart = _floor(now);
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      gridFocus.requestFocus();
      final last = store.lastChannel;
      if (widget.resumeLast && last != null) {
        final all = store.section('all');
        final k = all.indexWhere((c) => c.id == last);
        if (k >= 0) _play(all, k);
      }
    });
  }

  @override
  void dispose() {
    clock?.cancel();
    gridFocus.dispose();
    for (final f in railFocus) {
      f.dispose();
    }
    scroll.dispose();
    super.dispose();
  }

  DateTime _floor(DateTime t) => DateTime(t.year, t.month, t.day, t.hour, t.minute >= 30 ? 30 : 0);

  void _refresh() {
    list = store.section(section, query);
    if (row >= list.length) row = list.isEmpty ? 0 : list.length - 1;
  }

  void _setSection(String key, {String q = ''}) {
    setState(() {
      section = key;
      query = q;
      row = 0;
      cursor = DateTime.now();
      winStart = _floor(cursor);
      _refresh();
    });
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  Future<void> _play(List<Channel> channels, int index) async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => PlayerScreen(channels: channels, index: index)),
    );
    if (!mounted) return;
    setState(() {
      now = DateTime.now();
      cursor = now;
      winStart = _floor(now);
      _refresh();
      final k = list.indexWhere((c) => c.id == id);
      if (k >= 0) row = k;
    });
    _ensureVisible();
    gridFocus.requestFocus();
  }

  Program? get _focusedProgram => list.isEmpty ? null : store.programAt(list[row].id, cursor);

  void _ensureVisible() {
    if (!scroll.hasClients) return;
    final top = row * _rowH;
    final view = scroll.position.viewportDimension;
    if (top < scroll.offset) {
      scroll.jumpTo(top);
    } else if (top + _rowH > scroll.offset + view) {
      scroll.jumpTo((top + _rowH - view).clamp(0, scroll.position.maxScrollExtent));
    }
  }

  void _moveRow(int d) {
    if (list.isEmpty) return;
    final r = (row + d).clamp(0, list.length - 1);
    if (r == row) return;
    setState(() => row = r);
    _ensureVisible();
  }

  void _moveTime(int dir) {
    if (list.isEmpty) return;
    final progs = store.programs(list[row].id);
    final cur = store.programAt(list[row].id, cursor);
    DateTime target;
    if (dir > 0) {
      final next = cur != null ? cur.end : cursor.add(const Duration(minutes: _stepMin));
      final p = store.nextAfter(list[row].id, next);
      target = (progs.isEmpty || p == null) ? cursor.add(const Duration(minutes: _stepMin)) : p.start;
      final maxT = now.add(const Duration(hours: 34));
      if (target.isAfter(maxT)) return;
      if (p != null && p.start.isAfter(cursor) && p.start.difference(cursor).inMinutes > 180) {
        target = cursor.add(const Duration(minutes: _stepMin));
      }
    } else {
      if (cur != null && cur.start.isAfter(now)) {
        target = cur.start.subtract(const Duration(minutes: 1));
        final prev = store.programAt(list[row].id, target);
        if (prev != null && prev.start.isAfter(now)) target = prev.start;
        if (target.isBefore(now)) target = now;
      } else if (cursor.isAfter(now)) {
        target = cursor.subtract(const Duration(minutes: _stepMin));
        if (target.isBefore(now)) target = now;
      } else {
        railFocus[_sections.indexWhere((s) => s.$1 == section)].requestFocus();
        return;
      }
    }
    setState(() {
      cursor = target;
      final winEnd = winStart.add(const Duration(minutes: _windowMin));
      while (!cursor.isBefore(winEnd.subtract(const Duration(minutes: 10)))) {
        winStart = winStart.add(const Duration(minutes: _stepMin));
        if (!cursor.isBefore(winStart.add(const Duration(minutes: _windowMin - 10)))) continue;
        break;
      }
      while (cursor.isBefore(winStart) && winStart.isAfter(_floor(now))) {
        winStart = winStart.subtract(const Duration(minutes: _stepMin));
      }
    });
  }

  void _activate() {
    if (list.isEmpty) return;
    final p = _focusedProgram;
    if (p == null || !p.start.isAfter(now)) {
      _play(list, row);
    } else {
      _showInfo();
    }
  }

  Future<void> _showInfo() async {
    if (list.isEmpty) return;
    final ch = list[row];
    final watch = await showInfoDialog(context, ch, _focusedProgram);
    if (!mounted) return;
    setState(_refresh);
    gridFocus.requestFocus();
    if (watch == true) {
      final k = list.indexWhere((c) => c.id == ch.id);
      _play(list, k >= 0 ? k : row);
    }
  }

  KeyEventResult _onGridKey(FocusNode _, KeyEvent e) {
    final k = e.logicalKey;
    if (isSelectKey(k)) {
      if (e is KeyDownEvent) {
        selectDown = true;
        longFired = false;
      } else if (e is KeyRepeatEvent) {
        if (selectDown && !longFired) {
          longFired = true;
          _showInfo();
        }
      } else if (e is KeyUpEvent) {
        if (selectDown && !longFired) _activate();
        selectDown = false;
      }
      return KeyEventResult.handled;
    }
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.channelDown) {
      _moveRow(1);
    } else if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.channelUp) {
      _moveRow(-1);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _moveTime(1);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _moveTime(-1);
    } else if (k == LogicalKeyboardKey.info || k == LogicalKeyboardKey.contextMenu) {
      _showInfo();
    } else if (k == LogicalKeyboardKey.pageDown) {
      _moveRow(6);
    } else if (k == LogicalKeyboardKey.pageUp) {
      _moveRow(-6);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Future<void> _openSearch() async {
    final q = await showDialog<String>(context: context, builder: (_) => const _SearchDialog());
    if (!mounted) return;
    if (q != null && q.trim().isNotEmpty) {
      _setSection('search', q: q.trim());
      gridFocus.requestFocus();
    } else {
      railFocus[_sections.length - 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 118, child: _infoPanel()),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 170, child: _rail()),
                    const SizedBox(width: 10),
                    Expanded(child: _grid()),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'OK: watch   •   Hold OK: show info & favorite   •   ◀ on the left edge: menu',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoPanel() {
    final ch = list.isEmpty ? null : list[row];
    final p = _focusedProgram;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [tealDark, panel]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          if (ch != null) Logo(ch, size: 80),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  p?.title ?? ch?.name ?? 'No channels here yet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (ch != null) ch.name,
                    if (p != null) '${dayLabel(p.start)} ${hm(p.start)} – ${hm(p.end)}',
                    if (p != null && p.category.isNotEmpty) p.category,
                  ].join('   •   '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF99F6E4)),
                ),
                const SizedBox(height: 4),
                Text(
                  p?.desc.isNotEmpty == true
                      ? p!.desc
                      : (ch == null
                          ? (section == 'fav' ? 'Hold OK on any show to add its channel to Favorites.' : '')
                          : 'No guide info for this channel.'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('Olivia TV', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: teal)),
              Text(hm(now), style: const TextStyle(fontSize: 16, color: Colors.white70)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rail() {
    return FocusTraversalGroup(
      child: ListView(
        children: [
          for (var i = 0; i < _sections.length; i++)
            _RailItem(
              focusNode: railFocus[i],
              label: _sections[i].$2,
              icon: _sections[i].$3,
              selected: section == _sections[i].$1,
              onFocus: () {
                final key = _sections[i].$1;
                if (key != 'search' && key != section) _setSection(key);
              },
              onActivate: () {
                if (_sections[i].$1 == 'search') {
                  _openSearch();
                } else {
                  gridFocus.requestFocus();
                }
              },
              onRight: () => gridFocus.requestFocus(),
            ),
        ],
      ),
    );
  }

  Widget _grid() {
    return LayoutBuilder(builder: (context, box) {
      final ppm = (box.maxWidth - _chanW) / _windowMin;
      return Focus(
        focusNode: gridFocus,
        onKeyEvent: _onGridKey,
        child: ListenableBuilder(
          listenable: gridFocus,
          builder: (context, _) {
            final focused = gridFocus.hasFocus;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: _headerH, child: _timeHeader(ppm)),
                Expanded(
                  child: list.isEmpty
                      ? Center(
                          child: Text(
                            section == 'fav'
                                ? 'No favorites yet.\nHold OK on a show to add its channel.'
                                : section == 'search'
                                    ? 'No channels match "$query".'
                                    : 'No channels.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 18, color: Colors.white54),
                          ),
                        )
                      : Stack(
                          children: [
                            ListView.builder(
                              controller: scroll,
                              itemExtent: _rowH,
                              itemCount: list.length,
                              itemBuilder: (_, i) => _row(i, ppm, focused && i == row),
                            ),
                            if (now.isAfter(winStart))
                              Positioned(
                                left: _chanW + now.difference(winStart).inSeconds / 60 * ppm,
                                top: 0,
                                bottom: 0,
                                child: IgnorePointer(child: Container(width: 2, color: const Color(0xFFF472B6))),
                              ),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      );
    });
  }

  Widget _timeHeader(double ppm) {
    return Row(
      children: [
        SizedBox(
          width: _chanW,
          child: Text(dayLabel(winStart),
              style: const TextStyle(fontWeight: FontWeight.w700, color: teal, fontSize: 15)),
        ),
        Expanded(
          child: Stack(
            children: [
              for (var m = 0; m < _windowMin; m += _stepMin)
                Positioned(
                  left: m * ppm,
                  top: 4,
                  child: Text(hm(winStart.add(Duration(minutes: m))),
                      style: const TextStyle(color: Colors.white70, fontSize: 14)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(int i, double ppm, bool rowFocused) {
    final ch = list[i];
    final winEnd = winStart.add(const Duration(minutes: _windowMin));
    final progs = store.programs(ch.id).where((p) => p.end.isAfter(winStart) && p.start.isBefore(winEnd)).toList();
    final focusedProg = rowFocused ? store.programAt(ch.id, cursor) : null;
    final cells = <Widget>[];
    if (progs.isEmpty) {
      cells.add(_cell(0, _windowMin * ppm, ch.name, rowFocused, live: true, dim: true));
    } else {
      for (final p in progs) {
        final s = p.start.isBefore(winStart) ? winStart : p.start;
        final e = p.end.isAfter(winEnd) ? winEnd : p.end;
        final left = s.difference(winStart).inSeconds / 60 * ppm;
        final w = e.difference(s).inSeconds / 60 * ppm;
        cells.add(_cell(left, w, p.title, identical(p, focusedProg), live: p.isOnAt(now)));
      }
      if (rowFocused && focusedProg == null) {
        final left = cursor.isBefore(winStart) ? 0.0 : cursor.difference(winStart).inSeconds / 60 * ppm;
        cells.add(_cell(left, _stepMin * ppm, 'No info', true, dim: true));
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: _chanW - 4,
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: rowFocused ? tealDark : panel,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Logo(ch, size: 34),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(ch.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: rowFocused ? FontWeight.w700 : FontWeight.w500)),
                ),
                if (store.isFavorite(ch.id)) const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFACC15)),
              ],
            ),
          ),
          Expanded(child: Stack(children: cells)),
        ],
      ),
    );
  }

  Widget _cell(double left, double width, String title, bool focused, {bool live = false, bool dim = false}) {
    return Positioned(
      left: left,
      top: 0,
      bottom: 0,
      width: (width - 3).clamp(2, double.infinity),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: focused ? teal : (live ? const Color(0xFF12383F) : panel),
          borderRadius: BorderRadius.circular(6),
          border: focused ? Border.all(color: Colors.white, width: 2) : null,
        ),
        child: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: focused ? Colors.black : (dim ? Colors.white54 : Colors.white),
            fontWeight: focused ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final FocusNode focusNode;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onFocus;
  final VoidCallback onActivate;
  final VoidCallback onRight;

  const _RailItem({
    required this.focusNode,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onFocus,
    required this.onActivate,
    required this.onRight,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onFocusChange: (f) {
        if (f) onFocus();
      },
      onKeyEvent: (_, e) {
        if (e is KeyUpEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
          onRight();
          return KeyEventResult.handled;
        }
        if (isSelectKey(e.logicalKey) && e is KeyDownEvent) {
          onActivate();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final f = focusNode.hasFocus;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: f ? teal : (selected ? tealDark : panel),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: f ? Colors.black : (selected ? Colors.white : teal)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: f ? Colors.black : Colors.white,
                      )),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SearchDialog extends StatefulWidget {
  const _SearchDialog();

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  final ctrl = TextEditingController();

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: panel,
      title: const Text('Search channels'),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: 'e.g. Azteca, Telemundo, Disney'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Search')),
      ],
    );
  }
}

class Logo extends StatelessWidget {
  final Channel ch;
  final double size;
  const Logo(this.ch, {super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tealDark, borderRadius: BorderRadius.circular(size / 5)),
      child: Text(
        ch.name.isEmpty ? '?' : ch.name[0].toUpperCase(),
        style: TextStyle(fontSize: size * 0.45, fontWeight: FontWeight.w800),
      ),
    );
    if (ch.logo == null) return fallback;
    return SizedBox(
      width: size,
      height: size,
      child: Image.network(
        ch.logo!,
        fit: BoxFit.contain,
        cacheWidth: (size * 2).round(),
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

Future<bool?> showInfoDialog(BuildContext context, Channel ch, Program? p) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _InfoDialog(ch: ch, program: p),
  );
}

class _InfoDialog extends StatefulWidget {
  final Channel ch;
  final Program? program;
  const _InfoDialog({required this.ch, required this.program});

  @override
  State<_InfoDialog> createState() => _InfoDialogState();
}

class _InfoDialogState extends State<_InfoDialog> {
  final opened = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final p = widget.program;
    final fav = Store.i.isFavorite(widget.ch.id);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, e) {
        if (isSelectKey(e.logicalKey) &&
            (e is KeyRepeatEvent || DateTime.now().difference(opened).inMilliseconds < 400)) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AlertDialog(
        backgroundColor: panel,
        title: Row(
          children: [
            Logo(widget.ch, size: 48),
            const SizedBox(width: 14),
            Expanded(child: Text(p?.title ?? widget.ch.name, maxLines: 2, overflow: TextOverflow.ellipsis)),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  widget.ch.name,
                  if (p != null) '${dayLabel(p.start)} ${hm(p.start)} – ${hm(p.end)}',
                  if (p != null && p.category.isNotEmpty) p.category,
                ].join('   •   '),
                style: const TextStyle(color: Color(0xFF99F6E4)),
              ),
              const SizedBox(height: 12),
              Text(
                p == null ? 'No guide info for this channel.' : (p.desc.isEmpty ? 'No description.' : p.desc),
                style: const TextStyle(fontSize: 15, height: 1.35),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Store.i.toggleFavorite(widget.ch.id);
              setState(() {});
            },
            icon: Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded, color: const Color(0xFFFACC15)),
            label: Text(fav ? 'Remove favorite' : 'Add to favorites'),
          ),
          FilledButton.icon(
            autofocus: true,
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Watch channel'),
          ),
        ],
      ),
    );
  }
}
