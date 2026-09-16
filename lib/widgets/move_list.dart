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
  final String startsWithBlack;

  const MoveList({
    super.key,
    required this.moves,
    required this.currentIndex,
    required this.onMoveTap,
    this.vertical = false,
    this.startsWithBlack = '',
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

  /// Seçili hamleyi görünür kılar; kural [MoveScroller] içinde.
  void _follow() => _scroller.follow(
        index: widget.currentIndex,
        rowCount: (widget.moves.length / 2).ceil(),
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
    final pairs = (widget.moves.length / 2).ceil();
    return ListView.builder(
      controller: _scroller.controller,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: pairs,
      itemBuilder: (context, index) {
        final first = index * 2;
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
            _chip(context, first),
            if (first + 1 < widget.moves.length) _chip(context, first + 1),
            const SizedBox(width: 6),
          ],
        );
      },
    );
  }

  Widget _buildVertical(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pairs = (widget.moves.length / 2).ceil();
    return ListView.builder(
      controller: _scroller.controller,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: pairs,
      itemBuilder: (context, index) {
        final first = index * 2;
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
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _chip(context, first),
                ),
              ),
              Expanded(
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

  Widget _chip(BuildContext context, int index) {
    final scheme = Theme.of(context).colorScheme;
    final isCurrent = index == widget.currentIndex;
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
          onTap: () => widget.onMoveTap(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: isCurrent ? scheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.moves[index].san,
              style: TextStyle(
                color: isCurrent ? scheme.onPrimary : scheme.onSurface,
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
