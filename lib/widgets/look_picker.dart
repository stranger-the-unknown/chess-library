import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_look.dart';
import 'app_logo.dart';

/// Görünüm seçme penceresi: her görünüm kendi simgesiyle.
///
/// Seçileni döner; vazgeçilirse `null`.
Future<AppLook?> showLookPicker(BuildContext context, AppLook current) {
  return showModalBottomSheet<AppLook>(
    context: context,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Text(
                t('settings.look'),
                style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                // Telefonda beşerli iki sıra; dar ekranda dörderli.
                final columns = constraints.maxWidth >= 320 ? 5 : 4;
                final width = constraints.maxWidth / columns;
                return Wrap(
                  runSpacing: 10,
                  children: [
                    for (final look in AppLook.values)
                      SizedBox(
                        width: width,
                        child: _LookTile(
                          look: look,
                          selected: look == current,
                          onTap: () => Navigator.pop(sheetContext, look),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _LookTile extends StatelessWidget {
  const _LookTile({
    required this.look,
    required this.selected,
    required this.onTap,
  });

  final AppLook look;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = t('look.${look.id}');
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('look-${look.id}'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Seçili olanın çevresinde halka; ötekilerde aynı yer boş,
              // seçim değişince simgeler kaymıyor.
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected ? scheme.primary : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: AppLogo(look: look, size: 46),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
