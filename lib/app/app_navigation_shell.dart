import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/drill/drill.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/piece_practice/piece_practice.dart';
import 'package:piano_exercises/features/score_editor/score_editor.dart';

/// Top-level navigation destinations in [AppNavigationShell].
enum AppShellTab { drill, catalog, compose }

/// Responsive root shell switching between Drill, Catalog, and Compose with strict MIDI pause gating.
class AppNavigationShell extends ConsumerStatefulWidget {
  const AppNavigationShell({super.key, this.initialTab = AppShellTab.drill});

  final AppShellTab initialTab;

  @override
  ConsumerState<AppNavigationShell> createState() => _AppNavigationShellState();
}

class _AppNavigationShellState extends ConsumerState<AppNavigationShell> {
  late AppShellTab _selectedTab;
  int _modalPauseDepth = 0;
  bool _isRouteOpen = false;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    Future<void>.microtask(() {
      if (mounted) {
        _syncTabPauses();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Retain Compose tab draft and pause state across tab switches.
    ref.listen<bool>(scoreEditorPausedProvider, (_, _) {});
    ref.listen<ScoreEditorState>(
      scoreEditorControllerProvider(ScoreEditorSessionId.composeTab),
      (_, _) {},
    );

    final sharedMidiButton = MidiStatusActionButton(
      onBeforeOpen: _pauseBeforeModal,
      onAfterClose: _restoreAfterModal,
    );
    final content = switch (_selectedTab) {
      AppShellTab.drill => const DrillScreen(),
      AppShellTab.catalog => CatalogScreen(
        onSelectVariant: (piece, variant) =>
            unawaited(_openPieceScore(piece, variant)),
        onEditVariant: (piece, variant) =>
            unawaited(_openScoreEditor(piece, variant)),
        appBarActions: <Widget>[sharedMidiButton],
      ),
      AppShellTab.compose => ScoreEditorScreen(
        sessionId: ScoreEditorSessionId.composeTab,
        appBarActions: <Widget>[sharedMidiButton],
      ),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Scaffold(
            body: content,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _selectedTab.index,
              onDestinationSelected: _selectTab,
              destinations: const <NavigationDestination>[
                NavigationDestination(
                  key: ValueKey<String>('shell_nav_drill'),
                  icon: Icon(Icons.music_note_outlined),
                  selectedIcon: Icon(Icons.music_note),
                  label: 'Drill',
                ),
                NavigationDestination(
                  key: ValueKey<String>('shell_nav_catalog'),
                  icon: Icon(Icons.library_music_outlined),
                  selectedIcon: Icon(Icons.library_music),
                  label: 'Catalog',
                ),
                NavigationDestination(
                  key: ValueKey<String>('shell_nav_compose'),
                  icon: Icon(Icons.edit_note_outlined),
                  selectedIcon: Icon(Icons.edit_note),
                  label: 'Compose',
                ),
              ],
            ),
          );
        }

        return Scaffold(
          body: Row(
            children: <Widget>[
              SafeArea(
                right: false,
                child: NavigationRail(
                  selectedIndex: _selectedTab.index,
                  onDestinationSelected: _selectTab,
                  labelType: NavigationRailLabelType.all,
                  destinations: const <NavigationRailDestination>[
                    NavigationRailDestination(
                      icon: Icon(Icons.music_note_outlined),
                      selectedIcon: Icon(Icons.music_note),
                      label: Text(
                        'Drill',
                        key: ValueKey<String>('shell_nav_drill'),
                      ),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.library_music_outlined),
                      selectedIcon: Icon(Icons.library_music),
                      label: Text(
                        'Catalog',
                        key: ValueKey<String>('shell_nav_catalog'),
                      ),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.edit_note_outlined),
                      selectedIcon: Icon(Icons.edit_note),
                      label: Text(
                        'Compose',
                        key: ValueKey<String>('shell_nav_compose'),
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(child: content),
            ],
          ),
        );
      },
    );
  }

  void _selectTab(int index) {
    final nextTab = AppShellTab.values[index];
    if (nextTab == _selectedTab) {
      return;
    }
    setState(() => _selectedTab = nextTab);
    _syncTabPauses();
  }

  void _syncTabPauses() {
    if (!mounted) {
      return;
    }
    final blocked = _modalPauseDepth > 0 || _isRouteOpen;
    ref
        .read(drillControllerProvider.notifier)
        .setPaused(blocked || _selectedTab != AppShellTab.drill);
    ref
        .read(scoreEditorPausedProvider.notifier)
        .setPaused(blocked || _selectedTab != AppShellTab.compose);
  }

  void _pauseBeforeModal() {
    _modalPauseDepth += 1;
    _syncTabPauses();
  }

  void _restoreAfterModal() {
    if (_modalPauseDepth > 0) {
      _modalPauseDepth -= 1;
    }
    _syncTabPauses();
  }

  Future<void> _openPieceScore(Piece piece, ScoreVariant variant) async {
    if (_isRouteOpen) {
      return;
    }
    _isRouteOpen = true;
    _syncTabPauses();
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PieceScoreScreen(
            piece: piece,
            initialVariant: variant,
            onEditVariant: _pushScoreEditorRoute,
          ),
        ),
      );
    } finally {
      _isRouteOpen = false;
      _syncTabPauses();
    }
  }

  Future<void> _openScoreEditor(Piece piece, ScoreVariant variant) async {
    if (_isRouteOpen) {
      return;
    }
    _isRouteOpen = true;
    _syncTabPauses();
    try {
      await _pushScoreEditorRoute(piece, variant);
    } finally {
      _isRouteOpen = false;
      _syncTabPauses();
    }
  }

  Future<void> _pushScoreEditorRoute(Piece piece, ScoreVariant variant) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ScoreEditorScreen(
          sessionId: ScoreEditorSessionId('edit_${variant.id}'),
          initialPiece: piece,
          initialVariant: variant,
        ),
      ),
    );
  }
}
