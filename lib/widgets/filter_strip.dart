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
  /// Yalnızca geniş pencerede uygulanıyor: orada yer bol olduğu için
  /// şerit gerekirse büyüyebilir. Telefonda taban yok — satır zaten
  /// kıt ve çipler ellerindeki yeri paylaşıyorlar.
  static const double _minDesktopChip = 92;

  /// Ölçüye eklenen küçük pay.
  ///
  /// Genişlik en uzun etikete göre paylaştırıldığı için hesapta hiç
  /// boşluk kalmıyor; yarım pikselik bir fark bile en uzun etiketi üç
  /// noktaya düşürüyor. Bu pay o sınırı kaldırıyor.
  static const double _slack = 6;

  const FilterStrip({super.key, required this.options});

  /// Etiketin **gerçekte çizileceği** biçem.
  ///
  /// [Text], verilen biçemi üstteki [DefaultTextStyle] ile birleştiriyor.
  /// Ölçüm yalnız `chipTheme.labelStyle`'a bakarsa aradaki fark kadar dar
  /// çıkıyor: o biçem harf aralığı belirtmiyor, üstteki gövde biçemi ise
  /// 0.3 piksel veriyor. On üç harflik "Beyaz kazanır" böylece dört
  /// piksel taşıp üç noktaya düşüyordu — İngilizcede etiketler kısa
  /// olduğu için fark görünmüyordu.
  static TextStyle _labelStyle(BuildContext context) {
    final theme = Theme.of(context);
    final label = theme.chipTheme.labelStyle ?? theme.textTheme.labelLarge;
    final ambient = DefaultTextStyle.of(context).style;
    if (label == null) return ambient;
    return label.inherit ? ambient.merge(label) : label;
  }

  static double _chipWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: _labelStyle(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width + _chipPadding + _slack;
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
  /// Şeridin geniş pencerede kaplayacağı genişlik; sığmıyorsa null.
  ///
  /// Arama kutusu da bunu kullanıyor ([ListToolbar]): kutu şeritten dar
  /// kalırsa ikisi hizasız görünüyor — yedi süzgeçli oyun sonu listesinde
  /// şerit kutuyu açıkça geçiyordu.
  static double? desktopWidth(
    BuildContext context,
    List<FilterOption> options,
    double available,
  ) {
    final width = _evenWidth(context, options, available,
        minChip: _minDesktopChip);
    if (width == null) return null;
    // Masaüstünde şerit en az içerik genişliği kadar; altındaki listeyle
    // aynı hizada dursun diye.
    return math.min(available, math.max(Layout.maxContentWidth, width));
  }

  /// Eşit genişlikte dizilebiliyorsa şeridin isteyeceği genişlik.
  ///
  /// En uzun etikete göre hesaplanıyor: çiplerin hepsi o genişlikte
  /// olacak. Sığmıyorsa null döner ve şerit doğal genişliklere düşer.
  ///
  /// [minChip] yalnızca masaüstünde veriliyor; telefonda taban koymak
  /// eşit genişliği hepten imkânsız kılar ve çipler yine metin kadar
  /// dar kalırdı.
  static double? _evenWidth(
    BuildContext context,
    List<FilterOption> options,
    double available, {
    double minChip = 0,
  }) {
    if (options.isEmpty) return null;
    final widths = [
      for (final option in options) _chipWidth(context, option.label),
    ];
    final count = options.length;
    final widest = math.max(widths.reduce(math.max), minChip);
    final needed = widest * count + _gap * (count - 1) + _gap * 2;
    return needed > available ? null : needed;
  }

  /// Eşit genişlikte çiplerden oluşan şerit.
  Widget _segments(BuildContext context, double width) {
    final count = options.length;
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

          // 1) Hepsi eşit genişlikte sığıyorsa en iyisi bu: düğmeler
          //    aynı boyda ve satırı dolduruyorlar. Masaüstünde şerit
          //    içerik genişliğine ortalanıyor, telefonda satırı kaplıyor.
          if (Layout.isWide(context)) {
            final width = desktopWidth(context, options, constraints.maxWidth);
            if (width != null) return _segments(context, width);
          } else {
            final width =
                _evenWidth(context, options, constraints.maxWidth);
            if (width != null) {
              return _segments(context, constraints.maxWidth);
            }
          }

          // 2) Eşit genişlikte sığmıyor ama doğal genişlikleriyle
          //    sığıyorsa artan yer eşit paylaştırılıyor: her çip aynı
          //    miktarda büyüyor, satır doluyor ve kısa etiketli çipler
          //    ("All", "Read") metin kadar dar kalmıyor.
          final count = options.length;
          final sum = widths.fold<double>(0, (total, w) => total + w);
          final gaps = _gap * (count - 1) + _gap * 2;

          if (sum + gaps <= constraints.maxWidth) {
            final extra = (constraints.maxWidth - gaps - sum) / count;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: _gap),
              child: Row(
                children: [
                  for (int i = 0; i < count; i++) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    SizedBox(
                      width: widths[i] + extra,
                      child: _chip(context, options[i], fill: true),
                    ),
                  ],
                ],
              ),
            );
          }

          // 3) Hiç sığmıyorsa kaydırmalı şerit.

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

/// Arama kutusu ve süzgeç şeridini birlikte yerleştirir.
///
/// Geniş pencerede ikisinin genişliği birbirine bağlı: kutu şeritten
/// [_searchExtra] kadar uzun. Ayrı ayrı kurulduklarında kutu içerik
/// genişliğinde (760) kalıyor, yedi süzgeçli şerit ise etiketler için
/// daha çok yer istediğinden onu geçiyordu.
///
/// Dar pencerede ikisi de eskisi gibi tüm genişliği kullanıyor.
class ListToolbar extends StatelessWidget {
  final Widget search;
  final List<FilterOption> options;

  /// Arama kutusunun şeritten ne kadar uzun olacağı.
  static const double _searchExtra = 32;

  const ListToolbar({
    super.key,
    required this.search,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final strip = Layout.isWide(context)
                ? FilterStrip.desktopWidth(context, options, constraints.maxWidth)
                : null;
            if (strip == null) return search;
            return Center(
              child: SizedBox(
                width: math.min(constraints.maxWidth, strip + _searchExtra),
                child: search,
              ),
            );
          },
        ),
        FilterStrip(options: options),
      ],
    );
  }
}
