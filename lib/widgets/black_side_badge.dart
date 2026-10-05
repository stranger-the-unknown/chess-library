import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

/// Başlığın yanındaki küçük "Siyah" etiketi.
///
/// Siyah tarafından çalışılan açılış başlıklarında ve siyah tarafından
/// okunan oyun listelerinde; ikisi aynı görünsün diye tek yerde.
class BlackSideBadge extends StatelessWidget {
  final String tooltip;

  /// Dış boşluk; varsayılanı başlığın yanında duruşu için.
  final EdgeInsetsGeometry margin;

  const BlackSideBadge({
    super.key,
    required this.tooltip,
    this.margin = const EdgeInsets.only(left: 6),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Container(
        margin: margin,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          t('common.black'),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: scheme.onInverseSurface,
          ),
        ),
      ),
    );
  }
}
