import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 글로벌 출시용 하단 안내 문구를 공통 렌더링한다.
class AppDisclaimerFooter extends StatelessWidget {
  const AppDisclaimerFooter({
    super.key,
    this.compact = true,
    this.margin = EdgeInsets.zero,
  });

  final bool compact;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: margin,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 10 : 12,
      ),
      decoration: AppTheme.cardDecoration(
        color: AppTheme.surface1.withValues(alpha: 0.78),
        borderRadius: 14,
        borderColor: AppTheme.borderSubtle,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: compact ? 16 : 18,
            color: AppTheme.textMedium,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              compact
                  ? 'sensor.disclaimer.compact'.tr()
                  : 'sensor.disclaimer.full'.tr(),
              style: TextStyle(
                color: AppTheme.textMedium,
                fontSize: compact ? 11 : 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
