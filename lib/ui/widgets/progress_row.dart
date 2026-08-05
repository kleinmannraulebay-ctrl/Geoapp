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
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 76,
              child: Text(label,
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: value.clamp(0.0, 1.0),
                  minHeight: 10,
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  color: const Color(0xFF2DD4BF),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 88,
              child: Text(
                detail,
                textAlign: TextAlign.end,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
}
