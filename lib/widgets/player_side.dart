import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

/// "Oyuncunun gözünden oku" penceresi.
///
/// Döndürdüğü: yazılan ad, kaldırılırsa boş metin, vazgeçilirse null.
/// Ortak ad penceresi (`AppDialogs.prompt`) boş metni kabul etmediği için
/// ayrı: ad varken "Kaldır" düğmesi de var.
Future<String?> askPlayerSide(BuildContext context, {String? current}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _PlayerSideDialog(current: current),
    );

class _PlayerSideDialog extends StatefulWidget {
  const _PlayerSideDialog({this.current});

  final String? current;

  @override
  State<_PlayerSideDialog> createState() => _PlayerSideDialogState();
}

class _PlayerSideDialogState extends State<_PlayerSideDialog> {
  // Denetleyici pencerenin kendisinde: kapanma animasyonu boyunca geçerli
  // kalıyor (PGN yapıştırma penceresindeki 10.6.0 düzeltmesiyle aynı).
  late final TextEditingController _name =
      TextEditingController(text: widget.current ?? '');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, _name.text.trim());

  @override
  Widget build(BuildContext context) {
    final hasCurrent = (widget.current ?? '').isNotEmpty;
    return AlertDialog(
      title: Text(t('lists.playerSide')),
      content: TextField(
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          labelText: t('lists.playerName'),
          helperText: t('lists.playerSideHelp'),
          helperMaxLines: 3,
        ),
      ),
      actions: [
        if (hasCurrent)
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: Text(t('lists.playerSideRemove')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('common.cancel')),
        ),
        ElevatedButton(onPressed: _save, child: Text(t('common.save'))),
      ],
    );
  }
}

/// Liste kartında oyuncunun adı (sayı satırında, "Siyah" etiketinin yanında).
class PlayerSideBadge extends StatelessWidget {
  const PlayerSideBadge({
    super.key,
    required this.name,
    this.margin = const EdgeInsets.only(left: 6),
  });

  final String name;

  /// Dış boşluk; "Siyah" etiketiyle aynı varsayılan.
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: t('lists.playerSideBadge', {'name': name}),
      child: Container(
        margin: margin,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        constraints: const BoxConstraints(maxWidth: 180),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.visibility_outlined,
              size: 12,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
