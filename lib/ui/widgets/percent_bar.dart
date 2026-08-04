import 'package:flutter/material.dart';

import '../format.dart';

class PercentBar extends StatelessWidget {
  final String label;
  final double ratio; // 0..1
  final String? trailing;

  const PercentBar({
    super.key,
    required this.label,
    required this.ratio,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: text.bodySmall),
              Text(trailing ?? formatPct(ratio), style: text.bodySmall),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0), minHeight: 6),
          ),
        ],
      ),
    );
  }
}
