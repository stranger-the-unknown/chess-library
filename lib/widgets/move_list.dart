import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/move_entry.dart';
import 'cursors.dart';

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
  final Map<int, GlobalKey> _keys = {};

  @override
  void didUpdateWidget(covariant MoveList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.moves.length != widget.moves.length) {
      _scrollToCurrent();
    }
  }

  void _scrollToCurrent() {
    if (widget.currentIndex < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _keys[widget.currentIndex]?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  GlobalKey _keyFor(int index) => _keys.putIfAbsent(index, GlobalKey.new);

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
      child: InkWell(
        mouseCursor: kClickable,
        key: _keyFor(index),
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
    );
  }
}
