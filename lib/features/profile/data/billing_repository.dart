import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_error_message.dart';

class BillingPlan {
  const BillingPlan({
    required this.code,
    required this.name,
    required this.priceCents,
    required this.currency,
    required this.features,
  });

  factory BillingPlan.fromJson(Map<String, dynamic> json) {
    return BillingPlan(
      code: json['code']?.toString() ?? 'free',
      name: json['name']?.toString() ?? 'Plano',
      priceCents: (json['price_cents'] as num?)?.toInt() ?? 0,
      currency: json['currency']?.toString() ?? 'BRL',
      features: (json['features'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
    );
  }

  final String code;
  final String name;
  final int priceCents;
  final String currency;
  final List<String> features;

  String get formattedPrice {
    if (priceCents <= 0) return 'Grátis';
    return 'R\$ ${(priceCents / 100).toStringAsFixed(2).replaceAll('.', ',')}';
  }
}

class BillingStatus {
  const BillingStatus({
    required this.planCode,
    required this.isPremium,
    this.premiumUntil,
  });

  factory BillingStatus.fromJson(Map<String, dynamic> json) {
    return BillingStatus(
      planCode: json['plan_code']?.toString() ?? 'free',
      isPremium: json['is_premium'] as bool? ??
          json['premium_active'] as bool? ??
          false,
      premiumUntil: json['premium_until']?.toString(),
    );
  }

  final String planCode;
  final bool isPremium;
  final String? premiumUntil;
}

class CheckoutStartResult {
  const CheckoutStartResult({
    required this.checkoutUrl,
    required this.checkoutId,
  });

  factory CheckoutStartResult.fromJson(Map<String, dynamic> json) {
    return CheckoutStartResult(
      checkoutUrl: json['checkout_url']?.toString() ?? '',
      checkoutId: json['checkout_id']?.toString() ?? '',
    );
  }

  final String checkoutUrl;
  final String checkoutId;
}

class BillingRepository {
  const BillingRepository(this._client);

  final ApiClient _client;

  Future<List<BillingPlan>> getPlans() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.billingPlans);
      final payload = response.data as Map<String, dynamic>? ?? const {};
      final plans = payload['plans'] as List<dynamic>? ?? const [];
      return plans
          .map((item) => BillingPlan.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw buildRemoteServiceException(
        error,
        fallback: 'Não foi possível carregar os planos. Tente novamente.',
        connectivityFallback:
            'Não foi possível conectar ao servidor de planos. Verifique sua conexão e tente novamente.',
      );
    }
  }

  Future<BillingStatus> getStatus() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.billingStatus);
      return BillingStatus.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (error) {
      throw buildRemoteServiceException(
        error,
        fallback: 'Não foi possível verificar o status do plano.',
        connectivityFallback:
            'Não foi possível conectar ao servidor de assinatura. Verifique sua conexão e tente novamente.',
      );
    }
  }

  Future<CheckoutStartResult> startCheckout({
    required String userId,
    required String name,
    required String email,
    String planCode = 'premium_30',
    String provider = 'mercadopago',
  }) async {
    try {
      final response = await _client.dio.post(
        ApiEndpoints.billingCheckoutStart,
        data: {
          'user_id': userId,
          if (int.tryParse(userId) != null)
            'user_numeric_id': int.parse(userId),
          'plan_code': planCode,
          'provider': provider,
          'name': name,
          'email': email,
          'email_id': email,
        },
      );
      return CheckoutStartResult.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw buildRemoteServiceException(
        error,
        fallback: 'Não foi possível iniciar o checkout. Tente novamente.',
        connectivityFallback:
            'Não foi possível conectar ao checkout agora. Verifique sua conexão e tente novamente.',
      );
    }
  }
}

final billingRepositoryProvider = Provider<BillingRepository>(
  (ref) => BillingRepository(ref.watch(apiClientProvider)),
);

final billingPlansProvider =
    FutureProvider.autoDispose<List<BillingPlan>>((ref) {
  return ref.watch(billingRepositoryProvider).getPlans();
});

final billingStatusProvider = FutureProvider.autoDispose<BillingStatus>((ref) {
  return ref.watch(billingRepositoryProvider).getStatus();
});
