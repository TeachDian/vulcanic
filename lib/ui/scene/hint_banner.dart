import 'package:flutter/material.dart';

import '../theme.dart';

/// One short line of guidance, shown above the console.
class HintBanner extends StatelessWidget {
  const HintBanner({
    super.key,
    required this.text,
    this.icon,
    this.color = Palette.bone,
    this.action,
    this.onAction,
  });

  final String text;
  final IconData? icon;
  final Color color;

  /// Optional button label at the end of the line.
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Panel(
      radius: const BorderRadius.all(Radius.circular(16)),
      padding: EdgeInsets.fromLTRB(14, 10, action == null ? 16 : 6, 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          if (icon != null) Icon(icon, size: 18, color: color),
          Flexible(
            child: Text(text, style: AppText.label.copyWith(height: 1.3)),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: Palette.bone,
                textStyle: AppText.label.copyWith(
                  decoration: TextDecoration.underline,
                ),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}
