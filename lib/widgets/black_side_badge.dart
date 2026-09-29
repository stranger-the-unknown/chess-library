import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

/// Başlığın yanındaki küçük "Siyah" etiketi.
///
/// Siyah tarafından çalışılan açılış başlıklarında ve siyah tarafından
/// okunan oyun listelerinde; ikisi aynı görünsün diye tek yerde.
class BlackSideBadge extends StatelessWidget {
  final String tooltip;

  const BlackSideBadge({super.key, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Container(
        margin: const EdgeInsets.only(left: 6),
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
