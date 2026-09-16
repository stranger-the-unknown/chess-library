import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'cursors.dart';
import 'responsive.dart';

/// Seçicinin gövdesini kuran geri çağırım.
///
/// Verilen denetleyici kaydırma alanına, dolgu da listenin kendisine
/// bağlanmalı: başlık ve alttaki solma buna göre çalışıyor.
typedef PickerBuilder = Widget Function(
  BuildContext context,
  ScrollController controller,
  EdgeInsets padding,
);

/// Tahta ve taş takımı seçicileri.
///
/// Telefonda alttan açılan bir yaprak, geniş pencerede ortada bir panel.
/// İki sebebi var:
///
/// * [showModalBottomSheet] geniş pencerede yaprağı 640 piksele sıkıştırıp
///   ortalıyor (Material 3'ün varsayılanı). İmleç yaprağın dışındayken
///   fare tekerleği hiçbir şeye denk gelmiyor ve sayfa kıpırdamıyordu.
/// * Üç sütunluk bir ızgara o genişlikte gereksiz iri kutular çiziyor;
///   panelde daha fazla tahta bir arada görünüyor.
///
/// Her iki kipte de başlık, kapatma düğmesi, her zaman görünen bir
/// kaydırma çubuğu ve **aşağıda içerik kaldıkça** beliren bir solma var.
/// Liste eskiden satır ortasından kesiliyordu ve bu bir kusur gibi
/// duruyordu; kesmenin kendisi "devamı var" demenin en iyi yolu, yeter ki
/// kasıtlı görünsün.
Future<void> showPickerPanel(
  BuildContext context, {
  required String title,
  required PickerBuilder builder,
}) {
  if (Layout.isWide(context)) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => _PickerDialog(title: title, builder: builder),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => _PickerBody(
        title: title,
        controller: controller,
        handle: true,
        builder: builder,
      ),
    ),
  );
}

class _PickerDialog extends StatefulWidget {
  final String title;
  final PickerBuilder builder;

  const _PickerDialog({required this.title, required this.builder});

  @override
  State<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<_PickerDialog> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(40),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: math.min(960, size.width * 0.9),
        height: size.height * 0.8,
        child: _PickerBody(
          title: widget.title,
          controller: _controller,
          handle: false,
          builder: widget.builder,
        ),
      ),
    );
  }
}

class _PickerBody extends StatefulWidget {
  final String title;
  final ScrollController controller;
  final bool handle;
  final PickerBuilder builder;

  const _PickerBody({
    required this.title,
    required this.controller,
    required this.handle,
    required this.builder,
  });

  @override
  State<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends State<_PickerBody> {
  bool _more = false;

  /// Aşağıda içerik kalıp kalmadığını izler.
  ///
  /// Kaydırma bildirimiyle yapılıyor; ilk karede henüz yerleşim
  /// olmadığından bir de kare sonrası bakılıyor.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  void _update() {
    if (!mounted || !widget.controller.hasClients) return;
    final more = widget.controller.position.extentAfter > 1;
    if (more != _more) setState(() => _more = more);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surface = scheme.surfaceContainerHigh;

    return Material(
      color: surface,
      child: Column(
        children: [
          if (widget.handle)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  mouseCursor: kClickable,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (_) {
                _update();
                return false;
              },
              child: Stack(
                children: [
                  Scrollbar(
                    controller: widget.controller,
                    thumbVisibility: true,
                    child: widget.builder(
                      context,
                      widget.controller,
                      EdgeInsets.fromLTRB(
                        16,
                        16,
                        16,
                        16 + MediaQuery.viewPaddingOf(context).bottom,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 32,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 160),
                        opacity: _more ? 1 : 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                surface.withValues(alpha: 0),
                                surface,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
