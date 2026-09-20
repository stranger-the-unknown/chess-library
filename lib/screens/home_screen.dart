import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/responsive.dart';

import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../models/chess_engine.dart' as engine;
import '../models/pgn_parser.dart';
import '../services/pgn_import_service.dart';
import '../services/engine/engine_service.dart';
import '../services/settings_service.dart';
import '../widgets/app_dialogs.dart';
import 'board_editor_screen.dart';
import 'game_screen.dart';
import 'pgn_import_screen.dart';
import '../widgets/cursors.dart';

/// Ana sekme: hızlı başlangıç eylemleri.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ContentInset(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          builder: (context, padding) => ListView(
            padding: padding,
            children: [
              Row(
                children: [
                  _logo(scheme),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('app.title'),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t('app.subtitle'),
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.3,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _primaryCard(
                context,
                icon: Icons.smart_toy_rounded,
                title: t('home.playEngine'),
                subtitle: t('home.playEngineSub'),
                onTap: () => _startEngineGame(context),
              ),
              const SizedBox(height: 12),
              _card(
                context,
                icon: Icons.content_paste_rounded,
                title: t('home.loadPgn'),
                subtitle: t('home.loadPgnSub'),
                onTap: () => _loadPgn(context),
              ),
              const SizedBox(height: 12),
              _card(
                context,
                icon: Icons.grid_on_rounded,
                title: t('home.freeBoard'),
                subtitle: t('home.freeBoardSub'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GameScreen(title: t('home.freeBoard')),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _card(
                context,
                icon: Icons.dashboard_customize_outlined,
                title: t('home.setup'),
                subtitle: t('home.setupSub'),
                onTap: () => _openEditor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logo(ColorScheme scheme) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF8FBB57), Color(0xFF4E7327)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: const Text(
        '♞',
        style: TextStyle(fontSize: 30, color: Colors.white, height: 1.1),
      ),
    );
  }

  Widget _primaryCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: kClickable,
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [scheme.primary, scheme.primary.withValues(alpha: 0.72)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: scheme.onPrimary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: scheme.onPrimary.withValues(alpha: 0.85),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                color: scheme.onPrimary.withValues(alpha: 0.85),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        mouseCursor: kClickable,
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 21, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------

  Future<void> _openEditor(BuildContext context) async {
    final fen = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => BoardEditorScreen(
          initialFen: engine.ChessGame().fen,
          title: t('home.setup'),
        ),
      ),
    );
    if (fen == null || !context.mounted) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.insights_rounded),
              title: Text(t('common.openInAnalysis')),
              onTap: () => Navigator.pop(sheetContext, 'analyze'),
            ),
            ListTile(
              leading: const Icon(Icons.smart_toy_rounded),
              title: Text(t('home.playEngine')),
              onTap: () => Navigator.pop(sheetContext, 'play'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    if (action == 'play') {
      await _startEngineGame(context, fen: fen);
      return;
    }
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            GameScreen(startFen: fen, title: t('home.setupPositionTitle')),
      ),
    );
  }

  Future<void> _startEngineGame(BuildContext context, {String? fen}) async {
    final settings = SettingsService.instance;
    int levelIndex = settings.engineLevel;
    // null = rastgele renk
    engine.Color? color = engine.Color.white;
    String? startFen = fen;

    final start = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setLocalState) {
          final scheme = Theme.of(context).colorScheme;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('home.playEngine'),
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    t('home.difficulty'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  for (int i = 0; i < EngineLevel.all.length; i++)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      // Zorluk seçilir seçilmez kaydediliyor. Eskiden
                      // yalnızca oyun başlatılırsa kaydediliyordu; geri
                      // çıkan kullanıcı ayarı eski hâlinde buluyordu.
                      // Açılış çalışırken "bu konumdan motora karşı oyna"
                      // zorluk sormadan başladığı için, zorluğu önceden
                      // buradan ayarlayabilmek gerekiyor.
                      onTap: () => setLocalState(() {
                        levelIndex = i;
                        settings.engineLevel = i;
                      }),
                      leading: Icon(
                        levelIndex == i
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: levelIndex == i
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      title: Text(
                        EngineLevel.all[i].name,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        EngineLevel.all[i].description,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    t('home.yourColor'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: 0,
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(t('common.white')),
                        ),
                        icon: const Icon(Icons.circle_outlined),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(t('common.black')),
                        ),
                        icon: const Icon(Icons.circle),
                      ),
                      ButtonSegment(
                        value: 2,
                        // Rastgele/Random: Android büyük yazıda son harf kesilmesin.
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Text(t('common.random')),
                          ),
                        ),
                        icon: const Icon(Icons.casino_outlined),
                      ),
                    ],
                    selected: {
                      color == null ? 2 : (color == engine.Color.white ? 0 : 1),
                    },
                    onSelectionChanged: (selection) => setLocalState(() {
                      switch (selection.first) {
                        case 0:
                          color = engine.Color.white;
                          break;
                        case 1:
                          color = engine.Color.black;
                          break;
                        default:
                          color = null;
                      }
                    }),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    t('home.startPosition'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          startFen == null
                              ? t('home.normalSetup')
                              : t('home.customSetup'),
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (startFen != null)
                        TextButton(
                          onPressed: () => setLocalState(() => startFen = null),
                          child: Text(t('common.reset')),
                        ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await Navigator.push<String>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BoardEditorScreen(
                                initialFen: startFen ?? engine.ChessGame().fen,
                                title: t('home.startPosition'),
                              ),
                            ),
                          );
                          if (picked != null) {
                            setLocalState(() => startFen = picked);
                          }
                        },
                        icon: const Icon(
                          Icons.dashboard_customize_outlined,
                          size: 18,
                        ),
                        label: Text(t('home.setup')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(sheetContext, true),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(t('common.start')),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (start != true || !context.mounted) return;
    settings.engineLevel = levelIndex;

    final resolvedColor = color ??
        (math.Random().nextBool() ? engine.Color.white : engine.Color.black);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(
          mode: GameMode.versusEngine,
          playerColor: resolvedColor,
          engineLevelIndex: levelIndex,
          startFen: startFen,
        ),
      ),
    );
  }

  /// PGN yükleme: dosyadan ya da metin yapıştırarak.
  Future<void> _loadPgn(BuildContext context) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: Text(t('pgn.openFile')),
              subtitle: Text(t('pgn.openFileSub')),
              onTap: () => Navigator.pop(sheetContext, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.content_paste_rounded),
              title: Text(t('pgn.pasteText')),
              subtitle: Text(t('pgn.pasteTextSub')),
              onTap: () => Navigator.pop(sheetContext, 'paste'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;

    if (source == 'file') {
      await _openPgnFile(context);
    } else {
      await _pastePgn(context);
    }
  }

  Future<void> _openPgnFile(BuildContext context) async {
    PickedPgn? picked;
    try {
      picked = await PgnImportService.pickFile();
    } catch (_) {
      picked = null;
    }
    if (!context.mounted) return;
    if (picked == null) {
      AppDialogs.snack(context, t('pgn.readError'));
      return;
    }
    await _handlePgnText(context, picked.content, picked.suggestedListName);
  }

  /// Metni çözümler; tek oyunsa doğrudan açar, çoklu ise içe aktarma
  /// ekranını gösterir.
  Future<void> _handlePgnText(
    BuildContext context,
    String text,
    String suggestedName,
  ) async {
    final games = await AppDialogs.runWithProgress<List<PgnGame>>(
      context,
      message: t('pgn.reading'),
      task: (report) => PgnParser.parseAllAsync(
        text,
        onProgress: (done, total) => report(total == 0 ? 0 : done / total),
      ),
    );
    if (!context.mounted) return;

    if (games.isEmpty) {
      AppDialogs.snack(context, t('pgn.noGames'));
      return;
    }
    if (games.length == 1) {
      final game = games.first;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GameScreen(
            uciMoves: game.uciMoves,
            startFen: game.startFen,
            title: game.title,
            initialResult: game.result,
            whiteName: game.white == '?' ? null : game.white,
            blackName: game.black == '?' ? null : game.black,
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PgnImportScreen(games: games, suggestedName: suggestedName),
      ),
    );
  }

  Future<void> _pastePgn(BuildContext context) async {
    final controller = TextEditingController();
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboard?.text != null && clipboard!.text!.contains('.')) {
      controller.text = clipboard.text!;
    }
    if (!context.mounted) return;

    final pgn = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('home.loadPgn')),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            maxLines: 10,
            minLines: 6,
            style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
            decoration: InputDecoration(hintText: t('home.pgnHint')),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('common.cancel')),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(t('common.open')),
          ),
        ],
      ),
    );

    if (pgn == null || !context.mounted) return;
    if (pgn.isEmpty) {
      AppDialogs.snack(context, t('home.pgnEmpty'));
      return;
    }
    await _handlePgnText(context, pgn, 'PGN');
  }
}
