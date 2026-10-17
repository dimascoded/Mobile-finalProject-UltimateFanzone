import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../away_day/presentation/away_day_screen.dart';
import '../../../prediction/presentation/prediction_screen.dart';
import '../../../pundit/presentation/pundit_screen.dart';
import '../../../stadium_pointer/presentation/stadium_pointer_screen.dart';

/// Empat pintasan cepat ke fitur utama Home.
class QuickActions extends StatelessWidget {
  const QuickActions({super.key});

  static const _actions = <({String label, IconData icon, Widget page})>[
    (
      label: 'Prediksi',
      icon: Icons.scoreboard_outlined,
      page: PredictionScreen(),
    ),
    (
      label: 'Kompas',
      icon: Icons.explore,
      page: StadiumPointerScreen(),
    ),
    (
      label: 'Pundit AI',
      icon: Icons.auto_awesome,
      page: PunditScreen(),
    ),
    (
      label: 'Away Day',
      icon: Icons.currency_exchange,
      page: AwayDayScreen(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final action in _actions)
          Expanded(
            child: _QuickAction(
              label: action.label,
              icon: action.icon,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => action.page),
              ),
            ),
          ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm,
            horizontal: AppSpacing.xs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.outline, width: 1),
                ),
                child: Icon(icon, color: scheme.primary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
