import 'package:flutter/material.dart';

/// Nhãn mục — chữ nhỏ, rõ cấp bậc.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 2),
      child: Text(
        text.toUpperCase(),
        style: style?.copyWith(
              fontSize: 11,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface.withValues(alpha: 0.42),
            ) ??
            TextStyle(
              fontSize: 11,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface.withValues(alpha: 0.42),
            ),
      ),
    );
  }
}
