import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/observability/app_observability.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../auth/domain/auth_state.dart';
import '../data/billing_repository.dart';

class PremiumCheckoutException implements Exception {
  const PremiumCheckoutException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PremiumCheckoutCoordinator {
  PremiumCheckoutCoordinator(
    this._billingRepository, {
    required AppObservability observability,
  }) : _observability = observability;

  final BillingRepository _billingRepository;
  final AppObservability _observability;

  Future<String> startCheckout({
    required AuthState? authState,
    required BillingPlan plan,
  }) async {
    final userId = authState?.userId?.trim() ?? '';
    if (userId.isEmpty) {
      _observability.trackEvent(
        'premium.checkout_blocked_missing_session',
        level: AppEventLevel.warning,
      );
      throw const PremiumCheckoutException(
        'A assinatura premium nao esta disponivel sem uma sessao valida.',
      );
    }
    _observability.trackEvent(
      'premium.checkout_requested',
      attributes: <String, Object?>{
        'plan_code': plan.code,
      },
    );

    final trimmedName = authState?.name?.trim();
    final userName =
        trimmedName != null && trimmedName.isNotEmpty ? trimmedName : 'Usuario';
    final userEmail = authState?.email?.trim() ?? '';

    try {
      final checkout = await _billingRepository.startCheckout(
        userId: userId,
        name: userName,
        email: userEmail,
        planCode: plan.code,
      );

      final checkoutUrl = checkout.checkoutUrl.trim();
      if (checkoutUrl.isEmpty) {
        throw const PremiumCheckoutException(
          'O checkout nao retornou uma URL valida.',
        );
      }

      _observability.trackEvent(
        'premium.checkout_succeeded',
        attributes: <String, Object?>{
          'plan_code': plan.code,
        },
      );
      return checkoutUrl;
    } catch (error, stackTrace) {
      _observability.reportError(
        'premium.checkout_failed',
        error,
        stackTrace,
        attributes: <String, Object?>{
          'plan_code': plan.code,
        },
      );
      rethrow;
    }
  }
}

final premiumCheckoutCoordinatorProvider = Provider<PremiumCheckoutCoordinator>(
  (ref) => PremiumCheckoutCoordinator(
    ref.watch(billingRepositoryProvider),
    observability: ref.watch(appObservabilityProvider),
  ),
);

final premiumCheckoutAuthStateProvider = Provider<AuthState?>(
  (ref) => ref.watch(authStateNotifierProvider).valueOrNull,
);
