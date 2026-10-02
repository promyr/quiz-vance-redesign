import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/admin_master_keys_service.dart';

class AdminKeyTestFeedback extends StatelessWidget {
  const AdminKeyTestFeedback({
    required this.result,
    super.key,
  });

  final ApiKeyTestResult result;

  @override
  Widget build(BuildContext context) {
    final feedback = _feedbackFor(result);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(feedback.icon, size: 14, color: feedback.color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                feedback.message,
                style: TextStyle(
                  color: feedback.color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (feedback.diagnostic != null) ...[
          const SizedBox(height: 3),
          Text(
            feedback.diagnostic!,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ],
    );
  }
}

_AdminKeyFeedback _feedbackFor(ApiKeyTestResult result) {
  if (result.isValid) {
    return _AdminKeyFeedback(
      message: result.safeMessage,
      color: AppColors.success,
      icon: Icons.check_circle_rounded,
    );
  }

  final code = result.safeErrorCode;
  final warning = const {
    'rate_limit',
    'provider_unavailable',
    'timeout',
    'payload_too_large',
  }.contains(code);
  return _AdminKeyFeedback(
    message: result.safeMessage,
    color: warning ? AppColors.warning : AppColors.error,
    icon: warning ? Icons.warning_amber_rounded : Icons.error_rounded,
    diagnostic: result.safeDiagnostic,
  );
}

class _AdminKeyFeedback {
  const _AdminKeyFeedback({
    required this.message,
    required this.color,
    required this.icon,
    this.diagnostic,
  });

  final String message;
  final Color color;
  final IconData icon;
  final String? diagnostic;
}
