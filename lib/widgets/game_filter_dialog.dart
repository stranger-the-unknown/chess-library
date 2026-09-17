import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/game_filter.dart';

/// Oyuncu ve sonuç süzgecini soran pencere.
///
/// Süzgeç şeridinde değil üç nokta menüsünde duruyor: şeritteki dört
/// düğme birbirini dışlayan tek bir seçim (hepsi/okunmuş/okunmamış/
/// favori), buradaki ise birlikte çalışan üç alan ve ikisi yazıyla
/// doldurulmak zorunda. Aynı şeride sıkıştırılınca ikisi de bozulurdu.
class GameFilterDialog extends StatefulWidget {
  final GameFilter filter;

  const GameFilterDialog({super.key, required this.filter});

  @override
  State<GameFilterDialog> createState() => _GameFilterDialogState();
}

class _GameFilterDialogState extends State<GameFilterDialog> {
  late final TextEditingController _white =
      TextEditingController(text: widget.filter.white);
  late final TextEditingController _black =
      TextEditingController(text: widget.filter.black);
  late final TextEditingController _winner =
      TextEditingController(text: widget.filter.winner);
  late ResultFilter _result = widget.filter.result;

  @override
  void dispose() {
    _white.dispose();
    _black.dispose();
    _winner.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(
      context,
      GameFilter(
        white: _white.text.trim(),
        black: _black.text.trim(),
        result: _result,
        winner: _winner.text.trim(),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label,
      {bool autofocus = false, bool last = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        textInputAction: last ? TextInputAction.done : TextInputAction.next,
        onSubmitted: last ? (_) => _submit() : null,
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const options = <ResultFilter, String>{
      ResultFilter.any: 'puzzles.filterAll',
      ResultFilter.whiteWins: 'lists.resultWhiteWins',
      ResultFilter.draw: 'lists.resultDraw',
      ResultFilter.blackWins: 'lists.resultBlackWins',
      ResultFilter.playerWins: 'lists.resultPlayerWins',
    };

    return AlertDialog(
      title: Text(t('lists.filterGames')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('lists.filterHint'),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            _field(_white, t('lists.filterWhite'), autofocus: true),
            _field(_black, t('lists.filterBlack')),
            Text(
              t('lists.filterResult'),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final entry in options.entries)
                  ChoiceChip(
                    label: Text(t(entry.value)),
                    selected: _result == entry.key,
                    onSelected: (_) => setState(() => _result = entry.key),
                  ),
              ],
            ),
            // Ad alanı yalnızca gerektiğinde: diğer seçeneklerde
            // doldurulsa bile bir anlamı olmazdı.
            if (_result == ResultFilter.playerWins) ...[
              const SizedBox(height: 12),
              _field(_winner, t('lists.filterWinner'), last: true),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.filter.isActive)
          TextButton(
            onPressed: () => Navigator.pop(context, GameFilter.none),
            child: Text(t('lists.filterClear')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('common.cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(t('lists.filterApply')),
        ),
      ],
    );
  }
}
