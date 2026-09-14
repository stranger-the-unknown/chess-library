import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';

/// Sayı aralığı ve "işaretle / kaldır" soran diyalog.
///
/// Bulmaca listelerinde ve oyun listelerinde aynı biçimde kullanılır.
class RangeDialog extends StatefulWidget {
  final int min;
  final int max;
  final String hint;
  final String markLabel;
  final String unmarkLabel;

  const RangeDialog({
    super.key,
    required this.min,
    required this.max,
    required this.hint,
    required this.markLabel,
    required this.unmarkLabel,
  });

  @override
  State<RangeDialog> createState() => _RangeDialogState();
}

class _RangeDialogState extends State<RangeDialog> {
  late final TextEditingController _from =
      TextEditingController(text: '${widget.min}');
  late final TextEditingController _to =
      TextEditingController(text: '${widget.max}');
  bool _mark = true;
  String? _error;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _submit() {
    final from = int.tryParse(_from.text.trim());
    final to = int.tryParse(_to.text.trim());
    if (from == null || to == null || from > to) {
      setState(() => _error = t('puzzles.rangeInvalid'));
      return;
    }
    Navigator.pop(context, (from, to, _mark));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('puzzles.markRange')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.hint,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _from,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: t('puzzles.rangeFrom'),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _to,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: t('puzzles.rangeTo'),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: true, label: Text(widget.markLabel)),
              ButtonSegment(value: false, label: Text(widget.unmarkLabel)),
            ],
            selected: {_mark},
            onSelectionChanged: (value) => setState(() => _mark = value.first),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('common.cancel')),
        ),
        ElevatedButton(onPressed: _submit, child: Text(t('common.ok'))),
      ],
    );
  }
}
