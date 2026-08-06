import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Multi-select interest / hobby chips for onboarding and profile.
class InterestTagsChips extends StatelessWidget {
  final List<InterestOption> options;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;
  final bool multiSelect;

  const InterestTagsChips({
    super.key,
    required this.options,
    required this.selectedIds,
    required this.onChanged,
    this.multiSelect = true,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((option) {
        final selected = selectedIds.contains(option.id);
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            final next = Set<String>.from(selectedIds);
            if (multiSelect) {
              if (selected) {
                next.remove(option.id);
              } else {
                next.add(option.id);
              }
            } else {
              next
                ..clear()
                ..add(option.id);
            }
            onChanged(next);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: selected ? AppColors.brandGradient : null,
              color: selected ? null : AppColors.chipIdle,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: selected ? Colors.transparent : AppColors.mutedBorder,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              option.label,
              style: AppTextStyles.ui(
                size: 14,
                weight: FontWeight.w600,
                color: selected ? AppColors.white : AppColors.ink,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Read-only chip row for profile / post cards.
class InterestTagsDisplay extends StatelessWidget {
  final List<String> labels;
  final int? maxVisible;

  const InterestTagsDisplay({
    super.key,
    required this.labels,
    this.maxVisible,
  });

  @override
  Widget build(BuildContext context) {
    final shown = maxVisible == null ? labels : labels.take(maxVisible!).toList();
    final overflow = maxVisible != null && labels.length > maxVisible! ? labels.length - maxVisible! : 0;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...shown.map(
          (label) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primary.withOpacity(0.18)),
            ),
            child: Text(
              label,
              style: AppTextStyles.ui(size: 12, weight: FontWeight.w600, color: AppColors.primaryDeep),
            ),
          ),
        ),
        if (overflow > 0)
          Text('+$overflow', style: AppTextStyles.caption.copyWith(color: AppColors.primary)),
      ],
    );
  }
}

class InterestOption {
  final String id;
  final String label;

  const InterestOption({required this.id, required this.label});
}
