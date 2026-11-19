import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/drill/drill.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/piece_practice/piece_practice.dart';

/// Top-level navigation destinations in [AppNavigationShell].
enum AppShellTab { drill, catalog }

/// Responsive root shell switching between Drill and Catalog with strict MIDI pause gating.
class AppNavigationShell extends ConsumerStatefulWidget {
  const AppNavigationShell({super.key, this.initialTab = AppShellTab.drill});

  final AppShellTab initialTab;

  @override
  ConsumerState<AppNavigationShell> createState() => _AppNavigationShellState();
}

class _AppNavigationShellState extends ConsumerState<AppNavigationShell> {
  late AppShellTab _selectedTab;
  bool _wasDrillPausedBeforeModal = false;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    if (_selectedTab != AppShellTab.drill) {
      Future<void>.microtask(() {
        if (mounted && _selectedTab != AppShellTab.drill) {
          ref.read(drillControllerProvider.notifier).setPaused(true);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = switch (_selectedTab) {
      AppShellTab.drill => const DrillScreen(),
      AppShellTab.catalog => CatalogScreen(
        onSelectVariant: (piece, variant) =>
            unawaited(_openPieceScore(piece, variant)),
        appBarActions: <Widget>[
          MidiStatusActionButton(
            onBeforeOpen: _pauseDrillBeforeModal,
            onAfterClose: _restoreDrillAfterModal,
          ),
        ],
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
    ref
        .read(drillControllerProvider.notifier)
        .setPaused(nextTab != AppShellTab.drill);
  }

  void _pauseDrillBeforeModal() {
    final drill = ref.read(drillControllerProvider.notifier);
    _wasDrillPausedBeforeModal = drill.isPaused;
    drill.setPaused(true);
  }

  void _restoreDrillAfterModal() {
    if (!mounted) {
      return;
    }
    if (!_wasDrillPausedBeforeModal && _selectedTab == AppShellTab.drill) {
      ref.read(drillControllerProvider.notifier).setPaused(false);
    }
  }

  Future<void> _openPieceScore(Piece piece, ScoreVariant variant) async {
    ref.read(drillControllerProvider.notifier).setPaused(true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              PieceScoreScreen(piece: piece, initialVariant: variant),
        ),
      );
    } finally {
      if (mounted) {
        ref
            .read(drillControllerProvider.notifier)
            .setPaused(_selectedTab != AppShellTab.drill);
      }
    }
  }
}
