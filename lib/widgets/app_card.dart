import 'package:flutter/material.dart';

/// Thẻ nội dung: nền sáng, bo mềm, viền và bóng rất nhẹ.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shadow = Theme.of(context).extension<AppShadows>();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.35),
        ),
        boxShadow: shadow?.card ?? const [],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

/// Bóng dùng chung (gắn qua ThemeExtension).
class AppShadows extends ThemeExtension<AppShadows> {
  const AppShadows({required this.card});

  final List<BoxShadow> card;

  @override
  AppShadows copyWith({List<BoxShadow>? card}) =>
      AppShadows(card: card ?? this.card);

  @override
  AppShadows lerp(ThemeExtension<AppShadows>? other, double t) {
    if (other is! AppShadows) return this;
    return AppShadows(card: t < 0.5 ? card : other.card);
  }
}
