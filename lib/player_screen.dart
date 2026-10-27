import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'data.dart';
import 'guide_screen.dart';
import 'main.dart';

class PlayerScreen extends StatefulWidget {
  final List<Channel> channels;
  final int index;
  const PlayerScreen({super.key, required this.channels, required this.index});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final store = Store.i;
  late int index;
  VideoPlayerController? ctrl;
  int token = 0;
  String? status;
  bool banner = true;
  bool expanded = false;
  Timer? bannerTimer;
  Timer? skipTimer;
  int skipDir = 1;
  int skipped = 0;
  final focus = FocusNode();
  final favFocus = FocusNode();

  Channel get ch => widget.channels[index];

  @override
  void initState() {
    super.initState();
    index = widget.index;
    WakelockPlus.enable();
    _tune();
  }

  @override
  void dispose() {
    token++;
    bannerTimer?.cancel();
    skipTimer?.cancel();
    ctrl?.dispose();
    focus.dispose();
    favFocus.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  void _showBanner() {
    bannerTimer?.cancel();
    setState(() => banner = true);
    bannerTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && !expanded) setState(() => banner = false);
    });
  }

  Future<void> _tune() async {
    final my = ++token;
    skipTimer?.cancel();
    final old = ctrl;
    setState(() {
      ctrl = null;
      status = 'Loading ${ch.name}…';
    });
    _showBanner();
    old?.dispose();
    store.lastChannel = ch.id;
    for (final s in ch.streams) {
      final c = VideoPlayerController.networkUrl(
        Uri.parse(s.url),
        httpHeaders: s.headers,
        formatHint: s.url.contains('.m3u8') ? VideoFormat.hls : null,
      );
      try {
        await c.initialize().timeout(const Duration(seconds: 15));
        if (my != token) {
          c.dispose();
          return;
        }
        await c.play();
        setState(() {
          ctrl = c;
          status = null;
        });
        skipped = 0;
        store.markWorking(ch.id);
        c.addListener(() => _watch(c, my));
        return;
      } catch (_) {
        c.dispose();
        if (my != token) return;
      }
    }
    store.markFailed(ch.id);
    _failed(my);
  }

  void _watch(VideoPlayerController c, int my) {
    if (my != token || !c.value.hasError) return;
    token++;
    final t = token;
    setState(() {
      ctrl = null;
      status = 'Signal lost. Retrying…';
    });
    c.dispose();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && t == token) _tune();
    });
  }

  void _failed(int my) {
    if (skipped >= 5) {
      setState(() => status = '${ch.name} is not available right now.\nPress ▲ / ▼ to change channel.');
      return;
    }
    setState(() => status = '${ch.name} is not available right now. Skipping…');
    skipTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || my != token) return;
      skipped++;
      _step(skipDir);
    });
  }

  void _step(int d) {
    final n = widget.channels.length;
    if (n <= 1) return;
    var k = index;
    for (var tries = 0; tries < n; tries++) {
      k = (k + d) % n;
      if (k < 0) k += n;
      if (!store.isHidden(widget.channels[k].id)) break;
    }
    if (k == index) return;
    skipDir = d;
    setState(() {
      index = k;
      expanded = false;
    });
    _tune();
  }

  void _toggleFav() {
    store.toggleFavorite(ch.id);
    setState(() {});
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.channelUp) {
      if (expanded) return KeyEventResult.ignored;
      skipped = 0;
      _step(-1);
    } else if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.channelDown) {
      if (expanded) return KeyEventResult.ignored;
      skipped = 0;
      _step(1);
    } else if (isSelectKey(k) || k == LogicalKeyboardKey.info) {
      if (e is KeyRepeatEvent) return KeyEventResult.handled;
      if (expanded) return KeyEventResult.ignored;
      bannerTimer?.cancel();
      setState(() {
        banner = true;
        expanded = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => favFocus.requestFocus());
    } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight) {
      if (expanded) return KeyEventResult.ignored;
      _showBanner();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _collapse() {
    setState(() => expanded = false);
    focus.requestFocus();
    _showBanner();
  }

  @override
  Widget build(BuildContext context) {
    final c = ctrl;
    return PopScope(
      canPop: !expanded,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _collapse();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (c != null && c.value.isInitialized)
                Center(
                  child: AspectRatio(
                    aspectRatio: c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9,
                    child: VideoPlayer(c),
                  ),
                ),
              if (status != null)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (status!.startsWith('Loading') || status!.startsWith('Signal'))
                        const Padding(
                          padding: EdgeInsets.only(bottom: 18),
                          child: CircularProgressIndicator(color: teal),
                        ),
                      Text(status!,
                          textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, color: Colors.white70)),
                    ],
                  ),
                ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                left: 24,
                right: 24,
                bottom: banner ? 20 : -260,
                child: _banner(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _banner() {
    final now = DateTime.now();
    final p = store.programAt(ch.id, now);
    final next = store.nextAfter(ch.id, p?.end ?? now);
    final fav = store.isFavorite(ch.id);
    double? progress;
    if (p != null) {
      progress = now.difference(p.start).inSeconds / p.end.difference(p.start).inSeconds;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xE60D2A30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tealDark, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Logo(ch, size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(ch.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15, color: Color(0xFF99F6E4))),
                        ),
                        if (fav)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(Icons.star_rounded, size: 18, color: Color(0xFFFACC15)),
                          ),
                      ],
                    ),
                    Text(p?.title ?? 'No guide info',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    if (p != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            Text(hm(p.start), style: const TextStyle(color: Colors.white70)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: LinearProgressIndicator(
                                value: progress!.clamp(0, 1),
                                color: teal,
                                backgroundColor: Colors.white12,
                                minHeight: 5,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(hm(p.end), style: const TextStyle(color: Colors.white70)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Text(hm(now), style: const TextStyle(fontSize: 18, color: Colors.white70)),
            ],
          ),
          if (next != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Next: ${hm(next.start)}  ${next.title}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60)),
            ),
          if (expanded) ...[
            if (p != null && p.desc.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(p.desc, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.3)),
              ),
            const SizedBox(height: 12),
            Focus(
              skipTraversal: true,
              canRequestFocus: false,
              onKeyEvent: (_, e) => isSelectKey(e.logicalKey) && e is KeyRepeatEvent
                  ? KeyEventResult.handled
                  : KeyEventResult.ignored,
              child: Row(
                children: [
                  OutlinedButton.icon(
                    focusNode: favFocus,
                    onPressed: _toggleFav,
                    icon: Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded, color: const Color(0xFFFACC15)),
                    label: Text(fav ? 'Remove favorite' : 'Add to favorites'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, ch.id),
                    icon: const Icon(Icons.grid_view_rounded),
                    label: const Text('TV Guide'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(onPressed: _collapse, child: const Text('Close')),
                ],
              ),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('▲ ▼ change channel   •   OK: info & favorite   •   Back: TV guide',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
