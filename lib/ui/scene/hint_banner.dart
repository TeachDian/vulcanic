import 'package:flutter/material.dart';

import '../theme.dart';

/// A short line of guidance shown above the dock.
class HintBanner extends StatelessWidget {
  const HintBanner({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.color = Palette.bone,
    this.action,
    this.onAction,
  });

  final String text;
  final IconData icon;
  final Color color;

  /// Optional button label at the end of the banner.
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Glass(
        radius: 22,
        tint: 0.72,
        padding: EdgeInsets.fromLTRB(16, 10, action == null ? 18 : 8, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 10,
          children: [
            Icon(icon, size: 18, color: color),
            Flexible(
              child: Text(
                text,
                style: AppText.label.copyWith(fontSize: 13, height: 1.3),
              ),
            ),
            if (action != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: Palette.ember,
                  textStyle: AppText.label,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(action!),
              ),
          ],
        ),
      ),
    );
  }
}
