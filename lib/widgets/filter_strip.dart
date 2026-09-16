import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'cursors.dart';
import 'responsive.dart';

/// Süzgeç şeridindeki tek bir seçenek.
class FilterOption {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const FilterOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });
}

/// Süzgeç çipleri. Telefonda ve masaüstünde ayrı yerleşim.
///
/// **Telefon.** Çiplerin genişliği [TextPainter] ile gerçekten ölçülüyor:
/// hepsi sığıyorsa satıra eşit aralıkla yayılıyorlar, sığmıyorsa (oyun
/// sonu listelerindeki yedi çip gibi) kaydırılıyorlar. Şerit hep
/// kaydırmalıyken son çip ekranın kenarından azıcık taşıyor ve kullanıcı
/// görmediği bir şeyi aramak zorunda kalıyordu.
///
/// **Masaüstü.** Orada sorun tersiydi: geniş bir pencerede metin kadar
/// dar çipler birbirinden kopuk, ufak ve her biri başka boyda duruyordu.
/// Bu yüzden geniş yerleşimde şerit **eşit genişlikte bir segment
/// şeridine** dönüşüyor; altındaki listeyle aynı genişlikte ortalanıyor
/// ve yedi süzgeç bile kaydırma gerektirmiyor.
///
/// Ölçüm tahminle değil [TextPainter] ile yapılıyor; etiket uzunluğu dile
/// ve yazı tipi ölçeğine göre değiştiği için sabit bir sayı yanlış olurdu.
class FilterStrip extends StatelessWidget {
  final List<FilterOption> options;

  /// Çipin metin dışındaki genişliği: iki yandaki dolgu ve kenarlık.
  ///
  /// Çip Material'ın `ChoiceChip`'i değil; o widget etiketin çevresine
  /// beklenmedik genişlikte bir pay koyuyor ve ölçüm ile çizim tutmuyor.
  /// Burada çizim de ölçüm de aynı iki sayıya dayanıyor.
  static const double _labelPadding = 12;
  static const double _border = 1;
  static const double _chipPadding = _labelPadding * 2 + _border * 2;

  /// Çipler arasındaki boşluk.
  static const double _gap = 8;

  /// Masaüstünde bir çipin inebileceği en küçük genişlik.
  ///
  /// Çok sayıda süzgeç varken eşit paylaşım çipleri okunamayacak kadar
  /// daraltabilir; o noktada şerit içeriğinden geniş olmayı bırakıp
  /// gereken kadar yer kaplar.
  static const double _minDesktopChip = 92;

  const FilterStrip({super.key, required this.options});

  double _chipWidth(BuildContext context, String label) {
    final style = Theme.of(context).chipTheme.labelStyle ??
        Theme.of(context).textTheme.labelLarge;
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width + _chipPadding;
  }

  Widget _chip(BuildContext context, FilterOption option, {bool fill = false}) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).chipTheme.labelStyle;
    return Semantics(
      selected: option.selected,
      button: true,
      child: Material(
        color: option.selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          mouseCursor: kClickable,
          borderRadius: BorderRadius.circular(10),
          onTap: option.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: _labelPadding,
              vertical: 7,
            ),
            alignment: fill ? Alignment.center : null,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: option.selected
                    ? scheme.secondaryContainer
                    : scheme.outlineVariant,
                width: _border,
              ),
            ),
            child: Text(
              option.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: fill ? TextAlign.center : null,
              style: style?.copyWith(
                color: option.selected
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Masaüstü yerleşimi: eşit genişlikte, ortalanmış segmentler.
  ///
  /// Şerit en az içerik genişliği kadar; çipler oraya sığmıyorsa pencere
  /// izin verdiği ölçüde genişliyor. Hiç sığmazsa (çok dar bir masaüstü
  /// penceresi) telefondaki kaydırmalı şeride düşülüyor — böyle bir
  /// durumda bile bir süzgeç erişilemez kalmasın.
  Widget? _segments(
    BuildContext context,
    BoxConstraints constraints,
    List<double> widths,
  ) {
    final count = options.length;
    final widest = math.max(widths.reduce(math.max), _minDesktopChip);
    final gaps = _gap * (count - 1) + _gap * 2;

    final needed = widest * count + gaps;
    if (needed > constraints.maxWidth) return null;

    final width = math.min(
      constraints.maxWidth,
      math.max(Layout.maxContentWidth, needed),
    );

    return Center(
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _gap),
          child: Row(
            children: [
              for (int i = 0; i < count; i++) ...[
                if (i > 0) const SizedBox(width: _gap),
                Expanded(child: _chip(context, options[i], fill: true)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final widths =
              options.map((o) => _chipWidth(context, o.label)).toList();

          if (Layout.isWide(context)) {
            final segments = _segments(context, constraints, widths);
            if (segments != null) return segments;
          }

          final total = widths.fold<double>(0, (sum, w) => sum + w) +
              _gap * (options.length + 1);

          if (total <= constraints.maxWidth) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: _gap),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final option in options) _chip(context, option),
                ],
              ),
            );
          }

          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: options.length,
            separatorBuilder: (_, __) => const SizedBox(width: _gap),
            itemBuilder: (context, index) => Center(
              child: _chip(context, options[index]),
            ),
          );
        },
      ),
    );
  }
}
