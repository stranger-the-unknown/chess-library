import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/move_entry.dart';
import 'cursors.dart';
import 'move_scroll.dart';

/// Hamle listesi. Yatay şerit (tahtanın altında) ya da dikey tablo
/// (analiz panelinde) olarak çizilir ve seçili hamleyi görünür tutar.
class MoveList extends StatefulWidget {
  final List<MoveEntry> moves;
  final int currentIndex;
  final ValueChanged<int> onMoveTap;
  final bool vertical;

  /// Listedeki ilk hamle siyaha mı ait?
  ///
  /// Siyahın oynayacağı bir konumdan başlayan oyun ve bulmacalarda şerit
  /// ilk hamleyi beyazın hamlesi gibi diziyordu: "1. Nf6" yazıyor, "1...
  /// Nf6" yazması gerekiyordu.
  final bool blackFirst;

  /// Bu sayıdan sonraki hamleler gizli ("···") gösterilir.
  ///
  /// Açılış alıştırmasında henüz sıra gelmemiş hamleler açığa çıkmasın
  /// diye. `null` ise hepsi görünür.
  final int? revealedCount;

  const MoveList({
    super.key,
    required this.moves,
    required this.currentIndex,
    required this.onMoveTap,
    this.vertical = false,
    this.blackFirst = false,
    this.revealedCount,
  });

  @override
  State<MoveList> createState() => _MoveListState();
}

class _MoveListState extends State<MoveList> {
  final MoveScroller _scroller = MoveScroller();

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void dispose() {
    _scroller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MoveList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.moves.length != widget.moves.length) _scroller.reset();
    _follow();
  }

  /// Siyah başlıyorsa ilk satırın beyaz yarısı boş kalıyor.
  int get _offset => widget.blackFirst ? 1 : 0;

  int get _rowCount => ((widget.moves.length + _offset) / 2).ceil();

  /// Seçili hamleyi görünür kılar; kural [MoveScroller] içinde.
  void _follow() => _scroller.follow(
        index: widget.currentIndex,
        rowCount: _rowCount,
      );

  @override
  Widget build(BuildContext context) {
    if (widget.moves.isEmpty) {
      return Center(
        child: Text(
          t('common.noMovesYet'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      );
    }
    return widget.vertical
        ? _buildVertical(context)
        : _buildHorizontal(context);
  }

  Widget _buildHorizontal(BuildContext context) {
    final pairs = _rowCount;
    return ListView.builder(
      controller: _scroller.controller,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: pairs,
      itemBuilder: (context, index) {
        final first = index * 2 - _offset;
        return Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                '${index + 1}.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            if (first < 0) _skipped(context) else _chip(context, first),
            if (first + 1 < widget.moves.length) _chip(context, first + 1),
            const SizedBox(width: 6),
          ],
        );
      },
    );
  }

  /// Dikey listede bir hamlenin sütun genişliği.
  ///
  /// En uzun SAN'ları (`exd8=Q+`, `O-O-O+`) masaüstü yazı ölçeğiyle de
  /// alacak kadar geniş, ama iki hamleyi yan yana tutacak kadar dar.
  ///
  /// Değer ölçülerek seçildi, ama bir uyarıyla: Flutter testleri gerçek
  /// yazı tipini kullanmıyor, her harfi punto kadar **kare** olan bir
  /// test yazı tipi kullanıyor. Orada `exd8=Q+` 133 piksel çıkıyor,
  /// gerçek yazı tipinde ~86. Bu yüzden pay bilerek geniş bırakıldı;
  /// testten okunan sayıya göre daraltmak yanıltıcı olurdu.
  static const double _moveColumnWidth = 104;

  Widget _buildVertical(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pairs = _rowCount;
    return ListView.builder(
      controller: _scroller.controller,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: pairs,
      itemBuilder: (context, index) {
        final first = index * 2 - _offset;
        return Container(
          color: index.isEven ? Colors.transparent : scheme.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  '${index + 1}.',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              // Sabit genişlik, `Expanded` değil. `Expanded` kalan yeri
              // ikiye bölüyordu: hamleler ~40 piksel olduğu için beyazla
              // siyahın arasında yüz pikselden fazla boşluk kalıyordu.
              SizedBox(
                width: _moveColumnWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: first < 0 ? _skipped(context) : _chip(context, first),
                ),
              ),
              SizedBox(
                width: _moveColumnWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: first + 1 < widget.moves.length
                      ? _chip(context, first + 1)
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Siyahın başladığı listede beyazın boş yarısı.
  Widget _skipped(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Text(
          '...',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      );

  Widget _chip(BuildContext context, int index) {
    final scheme = Theme.of(context).colorScheme;
    final isCurrent = index == widget.currentIndex;
    final revealed = widget.revealedCount;
    final hidden = revealed != null && index >= revealed;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      // Kendi `Material`'ı olmadan `InkWell`, en yakın üstteki Material'a
      // çiziyordu; o da şeridin dışında kaldığı için şeridin kenarında
      // yarısı görünen bir hamlenin üstüne gelince vurgu kutunun dışına
      // taşıyordu. Buradaki Material kaydırma alanının içinde, dolayısıyla
      // mürekkep de hamlenin sınırlarında kalıyor.
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          mouseCursor: kClickable,
          key: _scroller.keyFor(index),
          borderRadius: BorderRadius.circular(8),
          onTap: hidden ? null : () => widget.onMoveTap(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: isCurrent ? scheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              hidden ? '···' : widget.moves[index].san,
              style: TextStyle(
                color: hidden
                    ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
                    : (isCurrent ? scheme.onPrimary : scheme.onSurface),
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
