import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../widgets/responsive.dart';

import '../l10n/app_strings.dart';
import '../models/chess_engine.dart' as engine;
import '../services/engine/engine_service.dart';
import '../services/settings_service.dart';
import '../widgets/piece_widget.dart';
import '../widgets/cursors.dart';
import '../widgets/board_background.dart';

/// Görünüm ve davranış ayarları.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settings = SettingsService.instance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(t('nav.settings'))),
      body: AnimatedBuilder(
        animation: _settings,
        builder: (context, _) => ContentWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _section(t('settings.appearance')),
              _card([
                ListTile(
                  leading: const Icon(Icons.brightness_6_rounded),
                  title: Text(t('settings.theme')),
                  subtitle: Text(switch (_settings.themeMode) {
                    ThemeMode.dark => t('settings.themeDark'),
                    ThemeMode.light => t('settings.themeLight'),
                    ThemeMode.system => t('settings.themeSystem'),
                  }),
                  trailing: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_rounded),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_rounded),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.smartphone_rounded),
                      ),
                    ],
                    selected: {_settings.themeMode},
                    onSelectionChanged: (selection) =>
                        _settings.themeMode = selection.first,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              _card([
                ListTile(
                  leading: const Icon(Icons.language_rounded),
                  title: Text(t('settings.language')),
                  subtitle: Text(switch (_settings.language) {
                    AppLanguage.turkish => t('settings.languageTurkish'),
                    AppLanguage.english => t('settings.languageEnglish'),
                    AppLanguage.spanish => t('settings.languageSpanish'),
                    AppLanguage.german => t('settings.languageGerman'),
                    AppLanguage.french => t('settings.languageFrench'),
                    AppLanguage.system => t('settings.languageSystem'),
                  }),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _pickLanguage,
                ),
              ]),
              const SizedBox(height: 8),
              _card([
                ListTile(
                  leading: const Icon(Icons.grid_view_rounded),
                  title: Text(t('settings.boardTheme')),
                  subtitle: Text(BoardAssets.label(_settings.boardTheme)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _pickBoard,
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: const Icon(Icons.extension_rounded),
                  title: Text(t('settings.pieceSet')),
                  subtitle: Text(BoardAssets.label(_settings.pieceSet)),
                  trailing: SizedBox(
                    width: 76,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        PieceWidget(
                          piece: const engine.Piece(
                            engine.PieceType.knight,
                            engine.Color.white,
                          ),
                          size: 26,
                        ),
                        PieceWidget(
                          piece: const engine.Piece(
                            engine.PieceType.queen,
                            engine.Color.black,
                          ),
                          size: 26,
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                  onTap: _pickPieceSet,
                ),
              ]),
              const SizedBox(height: 8),
              _card([
                SwitchListTile(
                  secondary: const Icon(Icons.tag_rounded),
                  title: Text(t('settings.coordinates')),
                  subtitle: Text(t('settings.coordinatesSub')),
                  value: _settings.showCoordinates,
                  onChanged: (value) => _settings.showCoordinates = value,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.radio_button_checked_rounded),
                  title: Text(t('settings.legalMoves')),
                  value: _settings.showLegalMoves,
                  onChanged: (value) => _settings.showLegalMoves = value,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.highlight_rounded),
                  title: Text(t('settings.lastMove')),
                  value: _settings.highlightLastMove,
                  onChanged: (value) => _settings.highlightLastMove = value,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.animation_rounded),
                  title: Text(t('settings.animations')),
                  value: _settings.animateMoves,
                  onChanged: (value) => _settings.animateMoves = value,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.equalizer_rounded),
                  title: Text(t('settings.evalBar')),
                  subtitle: Text(t('settings.evalBarSub')),
                  value: _settings.showEvaluationBar,
                  onChanged: (value) => _settings.showEvaluationBar = value,
                ),
              ]),
              const SizedBox(height: 16),
              _section(t('settings.soundSection')),
              _card([
                SwitchListTile(
                  secondary: const Icon(Icons.volume_up_rounded),
                  title: Text(t('settings.sound')),
                  value: _settings.soundEnabled,
                  onChanged: (value) => _settings.soundEnabled = value,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.vibration_rounded),
                  title: Text(t('settings.haptics')),
                  value: _settings.hapticsEnabled,
                  onChanged: (value) => _settings.hapticsEnabled = value,
                ),
              ]),
              const SizedBox(height: 16),
              _section(t('settings.engineSection')),
              _card([
                ListTile(
                  leading: const Icon(Icons.memory_rounded),
                  title: Text(t('settings.defaultDifficulty')),
                  subtitle: Text(
                    '${EngineLevel.all[_settings.engineLevel].name} · '
                    '~${EngineLevel.all[_settings.engineLevel].approximateElo} Elo',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _pickLevel,
                ),
              ]),
              const SizedBox(height: 16),
              _section(t('settings.about')),
              _card([
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: Text(t('app.title')),
                  subtitle: Text(
                    t('settings.aboutText'),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  // -------------------------------------------------------------------------

  Future<void> _pickLanguage() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              for (final entry in const [
                (AppLanguage.system, 'settings.languageSystem'),
                (AppLanguage.turkish, 'settings.languageTurkish'),
                (AppLanguage.english, 'settings.languageEnglish'),
                (AppLanguage.spanish, 'settings.languageSpanish'),
                (AppLanguage.german, 'settings.languageGerman'),
                (AppLanguage.french, 'settings.languageFrench'),
              ])
                ListTile(
                  leading: Icon(
                    _settings.language == entry.$1
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: _settings.language == entry.$1
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  title: Text(t(entry.$2)),
                  onTap: () {
                    _settings.language = entry.$1;
                    setSheetState(() {});
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _pickBoard() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, controller) => StatefulBuilder(
          builder: (context, setSheetState) => GridView.builder(
            controller: controller,
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.82,
            ),
            itemCount: BoardAssets.boards.length,
            itemBuilder: (context, index) {
              final name = BoardAssets.boards[index];
              final selected = name == _settings.boardTheme;
              return InkWell(
                mouseCursor: kClickable,
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  _settings.boardTheme = name;
                  setSheetState(() {});
                },
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: BoardBackground(board: name, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      BoardAssets.label(name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _pickPieceSet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, controller) => StatefulBuilder(
          builder: (context, setSheetState) => ListView.separated(
            controller: controller,
            padding: const EdgeInsets.all(16),
            itemCount: BoardAssets.pieceSets.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final name = BoardAssets.pieceSets[index];
              final selected = name == _settings.pieceSet;
              final scheme = Theme.of(context).colorScheme;
              return Material(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.16)
                    : scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  mouseCursor: kClickable,
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    _settings.pieceSet = name;
                    setSheetState(() {});
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            BoardAssets.label(name),
                            style: TextStyle(
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                        // Örnek taşlar küçük bir kare şeridi üzerinde
                        // gösterilir: hem beyaz hem siyah taş, uygulama
                        // teması ne olursa olsun okunur kalır.
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final (i, code) in const [
                                'wk',
                                'wq',
                                'bn',
                                'bp',
                              ].indexed)
                                Container(
                                  width: 30,
                                  height: 30,
                                  color: Color(
                                    i.isEven
                                        ? BoardAssets.squareColors(
                                            _settings.boardTheme,
                                          ).$1
                                        : BoardAssets.squareColors(
                                            _settings.boardTheme,
                                          ).$2,
                                  ),
                                  child: SvgPicture.asset(
                                    BoardAssets.piecePath(name, code),
                                    width: 30,
                                    height: 30,
                                    placeholderBuilder: (context) =>
                                        const SizedBox(width: 30, height: 30),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (selected)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Icon(
                              Icons.check_circle_rounded,
                              color: scheme.primary,
                              size: 20,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _pickLevel() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            for (int i = 0; i < EngineLevel.all.length; i++)
              ListTile(
                leading: Icon(
                  _settings.engineLevel == i
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: _settings.engineLevel == i
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: Text(
                  '${EngineLevel.all[i].name} · ~${EngineLevel.all[i].approximateElo} Elo',
                ),
                subtitle: Text(EngineLevel.all[i].description),
                onTap: () {
                  _settings.engineLevel = i;
                  setSheetState(() {});
                },
              ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }
}
