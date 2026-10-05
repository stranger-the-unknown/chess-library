import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/settings_service.dart';

/// İzleme hızı düğmesi: basınca beş hız açılıyor.
///
/// Açılış ve oyun ekranlarının gezinme satırında. Seçilen hız ayara da
/// yazılıyor (tek hız: "ayarda bir, ekranda başka" yok); izleme sürerken
/// değişirse hemen geçerli olması çağıranın işi.
class WatchSpeedButton extends StatelessWidget {
  const WatchSpeedButton({
    super.key,
    required this.value,
    required this.onSelected,
    this.iconSize = 24,
  });

  final WatchSpeed value;
  final ValueChanged<WatchSpeed> onSelected;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<WatchSpeed>(
      tooltip: t('settings.watchSpeedNow', {'speed': value.label}),
      icon: Icon(Icons.speed_rounded, size: iconSize),
      // `initialValue` bilerek yok: menüyü seçili hızı düğmenin üstüne
      // hizalayarak açıyor ve ekranın altındaki düğmede alttaki hızlar
      // ekran dışına taşıyordu. Seçili hız işaretle görünüyor.
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final speed in WatchSpeed.ordered)
          CheckedPopupMenuItem<WatchSpeed>(
            value: speed,
            checked: speed == value,
            child: Text(speed.label),
          ),
      ],
    );
  }
}
