import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/backup_service.dart';
import '../widgets/cursors.dart';
import '../widgets/responsive.dart';
import 'home_screen.dart';
import 'openings/opening_list_screen.dart';
import 'playlist_screen.dart';
import 'puzzles/puzzle_collections_screen.dart';
import 'settings_screen.dart';

/// Ana bölümleri barındıran kabuk.
///
/// Dar ekranlarda (telefon) altta gezinme çubuğu, geniş pencerelerde
/// (masaüstü) solda gezinme rayı kullanılır. Sayfalar bir [IndexedStack]
/// içinde canlı kalır; sekme değiştirince yeniden yüklenmezler.
///
/// Bunun tek istisnası yedekten geri yükleme: veri kökten değiştiği için
/// sayfalar sıfırdan kurulur ([dataVersion]).
class HomeShell extends StatefulWidget {
  final int initialIndex;

  const HomeShell({super.key, this.initialIndex = 0});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index = widget.initialIndex;

  static const List<Widget> _pages = [
    HomeScreen(),
    PuzzleCollectionsScreen(),
    OpeningListScreen(),
    PlaylistScreen(),
    SettingsScreen(),
  ];

  static const List<(IconData, IconData, String)> _destinations = [
    (Icons.grid_view_rounded, Icons.grid_view_sharp, 'nav.play'),
    (Icons.extension_outlined, Icons.extension_rounded, 'nav.puzzles'),
    (Icons.menu_book_outlined, Icons.menu_book_rounded, 'nav.openings'),
    (Icons.library_books_outlined, Icons.library_books_rounded, 'nav.lists'),
    (Icons.tune_outlined, Icons.tune_rounded, 'nav.settings'),
  ];

  void _select(int index) => setState(() => _index = index);

  /// Geri tuşuna basıldığında uygulamadan çıkılacak mı?
  ///
  /// Yalnızca ilk sekmedeyken çıkılır. Başka bir sekmedeyken geri tuşu
  /// önce Oyna sekmesine döner: Android'in gezinme kuralı, geri tuşunun
  /// önce başlangıç hedefine götürmesini, çıkışın oradan olmasını söyler.
  /// Aksi hâlde ayarlara bakarken basılan bir geri tuşu uygulamayı
  /// kapatıyordu.
  bool get _canPop => _index == 0;

  void _onPopInvoked(bool didPop, Object? result) {
    if (didPop) return;
    setState(() => _index = 0);
  }

  @override
  Widget build(BuildContext context) {
    final pages = ValueListenableBuilder<int>(
      valueListenable: dataVersion,
      // Anahtar değişince sayfalar atılıp yeniden kurulur; her biri
      // verisini `initState` içinde yeniden okur.
      builder: (context, version, _) => KeyedSubtree(
        key: ValueKey<int>(version),
        child: IndexedStack(index: _index, children: _pages),
      ),
    );

    if (Layout.isWide(context)) {
      final scheme = Theme.of(context).colorScheme;
      return PopScope(
        canPop: _canPop,
        onPopInvokedWithResult: _onPopInvoked,
        child: Scaffold(
          body: Row(
            // Şerit ve ayraç, Row'un varsayılan ortalaması yüzünden içeriği
            // kadar yüksek kalıyordu; ekranın tamamını kaplamaları gerekiyor.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _rail(scheme),
              VerticalDivider(width: 1, color: scheme.outlineVariant),
              Expanded(child: pages),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        body: pages,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (final (icon, selectedIcon, key) in _destinations)
              NavigationDestination(
                // Material'ın kendi imleci masaüstünde ok olduğu için simgeyi
                // sarmalıyoruz; içteki bölge dıştakini geçersiz kıldığından
                // sarmalın burada, simgenin üzerinde olması gerekiyor.
                icon: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(icon),
                ),
                selectedIcon: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(selectedIcon),
                ),
                label: t(key),
              ),
          ],
        ),
      ),
    );
  }

  /// Masaüstündeki yan gezinme şeridi.
  ///
  /// [NavigationRail] imleç ayarı sunmuyor ve içindeki [InkResponse]
  /// masaüstünde ok imlecini zorluyor. İmleç, dıştan sarmalanarak
  /// değiştirilemediği için şerit burada elle kuruldu; görünüm Material 3
  /// rayının ölçülerini (80 genişlik, 56x32 gösterge) izler.
  Widget _rail(ColorScheme scheme) {
    return Container(
      width: 80,
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        right: false,
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 8),
              for (var i = 0; i < _destinations.length; i++)
                _railItem(i, scheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _railItem(int index, ColorScheme scheme) {
    final (icon, selectedIcon, key) = _destinations[index];
    final selected = index == _index;
    return InkWell(
      mouseCursor: kClickable,
      onTap: () => _select(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? scheme.secondaryContainer : null,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                selected ? selectedIcon : icon,
                size: 24,
                color: selected
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                t(key),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
