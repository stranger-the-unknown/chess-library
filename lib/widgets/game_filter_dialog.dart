import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../models/game_filter.dart';

/// Oyun listesi filtresini soran pencere.
///
/// Filtre şeridinde değil üç nokta menüsünde duruyor: şeritteki dört
/// düğme birbirini dışlayan tek bir seçim (hepsi/okunmuş/okunmamış/
/// favori), buradaki ise birlikte çalışan alanlar ve çoğu yazıyla
/// dolduruluyor. Aynı şeride sıkıştırınca ikisi de bozulurdu.
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
  late final TextEditingController _year = TextEditingController(
    text: widget.filter.year?.toString() ?? '',
  );
  late ResultFilter _result = widget.filter.result;
  late bool _ignoreColor = widget.filter.ignoreColor;

  @override
  void dispose() {
    _white.dispose();
    _black.dispose();
    _winner.dispose();
    _year.dispose();
    super.dispose();
  }

  int? get _parsedYear {
    final raw = _year.text.trim();
    if (raw.isEmpty) return null;
    final value = int.tryParse(raw);
    if (value == null || value < 1000 || value > 2099) return null;
    return value;
  }

  void _submit() {
    Navigator.pop(
      context,
      GameFilter(
        white: _white.text.trim(),
        black: _black.text.trim(),
        result: _result,
        winner: _winner.text.trim(),
        ignoreColor: _ignoreColor,
        year: _parsedYear,
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool autofocus = false,
    bool last = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
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
            _field(
              _white,
              _ignoreColor ? t('lists.filterPlayer') : t('lists.filterWhite'),
            ),
            _field(
              _black,
              _ignoreColor
                  ? t('lists.filterOpponent')
                  : t('lists.filterBlack'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _ignoreColor,
              onChanged: (value) =>
                  setState(() => _ignoreColor = value ?? false),
              title: Text(t('lists.filterIgnoreColor')),
              subtitle: Text(
                t('lists.filterIgnoreColorHint'),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 4),
            _field(
              _year,
              t('lists.filterYear'),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
            ),
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
