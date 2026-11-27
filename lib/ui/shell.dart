import 'package:flutter/cupertino.dart' hide RepeatMode;

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart' hide RepeatMode;

import '../app.dart';
import '../core/models.dart';
import 'player/player_sheet.dart';
import 'player/side_panels.dart';
import 'screens/explore.dart';
import 'screens/history_screen.dart';
import 'screens/apollo_home.dart';
import 'screens/home.dart';
import 'screens/profile_hub.dart';
import 'screens/library.dart';
import 'screens/local_screen.dart';
import 'screens/search.dart';
import 'screens/settings_screen.dart';
import 'styles/chrome.dart';
import 'theme/styles.dart';
import 'screens/profile_screen.dart';
import 'theme/theme.dart';
import 'widgets/audio_controls.dart';
import 'widgets/glass.dart';
import 'widgets/playlists.dart';
import 'widgets/particle_grid.dart';
import 'screens/playlist_screen.dart';

enum _Page { home, explore, library, search, history, local, settings }

const _main = [
  (_Page.home, Icons.home_rounded, Icons.home_rounded, 'Home'),
  (_Page.explore, Icons.explore_outlined, Icons.explore_rounded, 'Explore'),
  (
    _Page.library,
    Icons.video_library_outlined,
    Icons.video_library_rounded,
    'Library',
  ),
  (_Page.search, Icons.search_rounded, Icons.search_rounded, 'Search'),
];

/// Phone bottom bar: the main tabs plus Settings (desktop reaches Settings from the sidebar).
const _phoneTabs = [
  ..._main,
  (_Page.settings, Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
];

enum _Panel { none, queue, lyrics }

/// BitChord-style desktop layout: sidebar, a top transport bar with the now-playing pill, content and
/// an optional queue/lyrics panel. Below 900 px it becomes a phone layout with a bottom bar.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  _Page _page = _Page.search;
  final _visited = <_Page>{_Page.search};
  final _navKeys = {
    for (final p in _Page.values) p: GlobalKey<NavigatorState>(),
  };
  _Panel _panel = _Panel.none;
  final _sideSearch = TextEditingController();

  @override
  void initState() {
    super.initState();
    AppController.I.backend.errors.addListener(_onError);
  }

  @override
  void dispose() {
    AppController.I.backend.errors.removeListener(_onError);
    _sideSearch.dispose();
    super.dispose();
  }

  void _onError() {
    final e = AppController.I.backend.errors.value;
    if (e == null || !mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(e.message), behavior: SnackBarBehavior.floating),
      );
  }

  DateTime _lastSearchTap = DateTime.fromMillisecondsSinceEpoch(0);

  void _select(_Page p) {
    if (p == _page) {
      _navKeys[p]!.currentState?.popUntil((r) => r.isFirst);
      if (p == _Page.search) {
        final now = DateTime.now();
        // Double tap on Search: clear the box and results and start a fresh search.
        if (now.difference(_lastSearchTap) <
            const Duration(milliseconds: 450)) {
          SearchScreen.reset.value++;
          _lastSearchTap = DateTime.fromMillisecondsSinceEpoch(0);
        } else {
          _lastSearchTap = now;
        }
      }
    } else {
      setState(() {
        _page = p;
        _visited.add(p);
      });
    }
  }

  void _togglePanel(_Panel p) =>
      setState(() => _panel = _panel == p ? _Panel.none : p);

  Widget _root(_Page p) => switch (p) {
    _Page.home =>
      context.spec.style == UiStyle.apollo
          ? ApolloHome(onSearch: () => _select(_Page.search))
          : HomeScreen(onSearch: () => _select(_Page.search)),
    _Page.explore => const ExploreScreen(),
    _Page.library => LibraryScreen(
      onHistory: () => _select(_Page.history),
      onLocal: () => _select(_Page.local),
    ),
    _Page.search => const SearchScreen(),
    _Page.history => const HistoryScreen(),
    _Page.local => const LocalMusicScreen(),
    _Page.settings => const SettingsScreen(),
  };

  Widget _body() => IndexedStack(
    index: _Page.values.indexOf(_page),
    children: [
      for (final p in _Page.values)
        if (_visited.contains(p))
          _TabFade(
            active: p == _page,
            smooth: AppController.I.settings.smoothAnimations,
            child: Navigator(
              key: _navKeys[p],
              onGenerateRoute: (_) => CupertinoPageRoute(
                builder: (_) => Scaffold(
                  backgroundColor: Colors.transparent,
                  body: SafeArea(bottom: false, child: _root(p)),
                ),
              ),
            ),
          )
        else
          const SizedBox.shrink(),
    ],
  );

  void _submitSearch(String q) {
    if (q.trim().isEmpty) return;
    SearchScreen.request.value = '';
    SearchScreen.request.value = q.trim();
    _select(_Page.search);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ListenableBuilder(
      listenable: AppController.I.settings,
      builder: (context, _) => Scaffold(
        backgroundColor: context.bg,
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerHover: (e) => ParticleField.pointer.value = e.position,
          onPointerMove: (e) => ParticleField.pointer.value = e.position,
          onPointerDown: (e) => ParticleField.pointer.value = e.position,
          onPointerUp: (e) => ParticleField.pointer.value =
              e.kind == PointerDeviceKind.mouse ? e.position : null,
          onPointerCancel: (_) => ParticleField.pointer.value = null,
          child: Stack(
            children: [
              Positioned.fill(
                child: StyledBackdrop(
                  particles:
                      AppController.I.settings.particles &&
                      context.spec.particles,
                ),
              ),
              Positioned.fill(child: wide ? _wide(context) : _phone(context)),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Desktop / tablet / web ---------------------------------------------------------------------

  Widget _wide(BuildContext context) {
    const sidebarW = 274.0;
    return PlayerHost(
      barStyle: true,
      miniRect: (s) {
        final w = ((s.width - sidebarW) * 0.34).clamp(340.0, 650.0);
        final cx = sidebarW + (s.width - sidebarW) / 2;
        return Rect.fromLTWH(cx - w / 2, 12, w, 56);
      },
      child: Row(
        children: [
          _sidebar(context, sidebarW),
          Expanded(
            child: Column(
              children: [
                _topBar(context),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _body()),
                      if (_panel != _Panel.none)
                        SizedBox(
                          width: 380,
                          child: SidePanel(
                            title: _panel == _Panel.queue ? 'Queue' : 'Lyrics',
                            onClose: () => setState(() => _panel = _Panel.none),
                            child: _panel == _Panel.queue
                                ? const QueuePanel()
                                : const LyricsPanel(),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebar(BuildContext context, double w) {
    final playlists = AppController.I.settings;
    return SizedBox(
      width: w,
      child: Glass(
        blur: 22,
        border: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 44),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _sideSearch,
                onSubmitted: _submitSearch,
                decoration: InputDecoration(
                  hintText: 'Search',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: Colors.transparent,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.separator),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.secondaryText),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            for (final t in _main)
              _SidebarItem(
                icon: _page == t.$1 ? t.$3 : t.$2,
                label: t.$4,
                selected: _page == t.$1,
                onTap: () => _select(t.$1),
              ),
            _divider(context),
            _SidebarItem(
              icon: Icons.history_rounded,
              label: 'History',
              selected: _page == _Page.history,
              onTap: () => _select(_Page.history),
            ),
            _SidebarItem(
              icon: Icons.folder_outlined,
              label: 'Local Music',
              selected: _page == _Page.local,
              onTap: () => _select(_Page.local),
            ),
            _divider(context),
            Expanded(
              child: ListenableBuilder(
                listenable: playlists,
                builder: (context, _) {
                  final lists = UserPlaylists.all();
                  return ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      for (final p in lists)
                        _SidebarItem(
                          icon: p['id'] == UserPlaylists.likedId
                              ? Icons.favorite_rounded
                              : Icons.queue_music_rounded,
                          label: p['name'] as String,
                          selected: false,
                          onTap: () {
                            _select(_Page.library);
                            _navKeys[_Page.library]!.currentState?.push(
                              CupertinoPageRoute(
                                builder: (_) =>
                                    PlaylistScreen(id: p['id'] as String),
                              ),
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
            ),
            Container(height: 0.5, color: context.separator),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _SidebarItem(
                icon: Icons.settings_rounded,
                label: 'Settings',
                selected: _page == _Page.settings,
                onTap: () => _select(_Page.settings),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Container(height: 0.5, color: context.separator),
  );

  Widget _topBar(BuildContext context) {
    final backend = AppController.I.backend;
    final nav = _navKeys[_page]!.currentState;
    return SizedBox(
      height: 80,
      child: Glass(
        blur: 22,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ValueListenableBuilder<Snapshot>(
            valueListenable: backend.snapshot,
            builder: (context, snap, _) => Row(
              children: [
                const Wordmark(size: 30),
                const SizedBox(width: 24),
                _tb(
                  Icons.arrow_back_rounded,
                  true,
                  () => nav?.maybePop(),
                  size: 24,
                ),
                const SizedBox(width: 6),
                _tb(
                  Icons.shuffle_rounded,
                  true,
                  () => backend.setShuffle(!snap.shuffle),
                  on: snap.shuffle,
                ),
                _tb(
                  Icons.fast_rewind_rounded,
                  snap.currentIndex >= 0,
                  backend.previous,
                ),
                _tb(
                  snap.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  snap.current != null,
                  backend.toggle,
                  size: 28,
                ),
                _tb(Icons.fast_forward_rounded, snap.hasNext, backend.next),
                _tb(
                  snap.repeat == RepeatMode.one
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                  true,
                  backend.cycleRepeat,
                  on: snap.repeat != RepeatMode.off,
                ),
                const Spacer(),
                Icon(
                  Icons.volume_up_rounded,
                  size: 18,
                  color: context.secondaryText,
                ),
                const VolumeSlider(width: 100),
                const SizedBox(width: 14),
                _tb(
                  Icons.headphones_rounded,
                  true,
                  () => showOutputDialog(context),
                ),
                _tb(
                  Icons.format_quote_rounded,
                  true,
                  () => _togglePanel(_Panel.lyrics),
                  on: _panel == _Panel.lyrics,
                ),
                _tb(
                  Icons.format_list_bulleted_rounded,
                  true,
                  () => _togglePanel(_Panel.queue),
                  on: _panel == _Panel.queue,
                ),
                const SizedBox(width: 6),
                _AccountButton(onSettings: () => _select(_Page.settings)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tb(
    IconData icon,
    bool enabled,
    VoidCallback? onTap, {
    double size = 22,
    bool on = false,
  }) => IconButton(
    onPressed: enabled ? onTap : null,
    iconSize: size,
    color: context.accent,
    disabledColor: context.tertiaryText,
    style: on ? IconButton.styleFrom(backgroundColor: context.chipFill) : null,
    icon: Icon(icon),
  );

  // ---- Phone ----------------------------------------------------------------------------------------

  Widget _phone(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    final m = NavMetrics.of(context.spec.nav);
    final barTop = m.height + m.bottomGap + inset;
    return PlayerHost(
      miniRect: (s) {
        final side = m.sideMargin == 0 ? 12.0 : m.sideMargin;
        return Rect.fromLTWH(
          side,
          s.height - barTop - 12 - 56,
          s.width - side * 2,
          56,
        );
      },
      child: Stack(
        children: [
          Positioned.fill(child: _body()),
          StyledNavBar(
            tabs: [for (final t in _phoneTabs) NavTab(t.$2, t.$3, t.$4)],
            index: _phoneTabs
                .indexWhere((t) => t.$1 == _page)
                .clamp(0, _phoneTabs.length - 1),
            onSelect: (i) => _select(_phoneTabs[i].$1),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
    child: Material(
      color: selected
          ? (context.spec.defaultHue == null
                ? context.chipFill
                : context.hue.withValues(alpha: 0.18))
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(
                icon,
                size: 21,
                color: selected
                    ? (context.spec.defaultHue == null
                          ? context.accent
                          : context.hue)
                    : context.secondaryText,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? context.accent : context.secondaryText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AccountButton extends StatelessWidget {
  const _AccountButton({required this.onSettings});
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => openProfileHub(context),
    child: const ProfileAvatar(size: 40),
  );
}

/// Fades and lifts a tab in each time it becomes the visible one. With [smooth] off it just appears.
class _TabFade extends StatefulWidget {
  const _TabFade({
    required this.active,
    required this.smooth,
    required this.child,
  });
  final bool active;
  final bool smooth;
  final Widget child;

  @override
  State<_TabFade> createState() => _TabFadeState();
}

class _TabFadeState extends State<_TabFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
  );

  @override
  void didUpdateWidget(_TabFade old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && widget.smooth) {
      _c.forward(from: 0);
    } else if (!widget.smooth) {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _curve,
    child: widget.child,
    builder: (context, child) => Opacity(
      opacity: _curve.value,
      child: Transform.translate(
        offset: Offset(0, (1 - _curve.value) * 14),
        child: child,
      ),
    ),
  );
}
