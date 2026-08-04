import 'package:flutter/material.dart';

/// Beschriftete Fortschrittszeile: Label, Balken, Detailtext.
class ProgressRow extends StatelessWidget {
  final String label;
  final double value;
  final String detail;

  const ProgressRow({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 80, child: Text(label)),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: value.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: const Color(0xFF263238),
                  color: const Color(0xFF26A69A),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 90,
              child: Text(detail, textAlign: TextAlign.end),
            ),
          ],
        ),
      );
}
