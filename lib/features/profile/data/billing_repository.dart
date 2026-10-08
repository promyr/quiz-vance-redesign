import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/storage/local_storage.dart';
import '../../../shared/providers/auth_provider.dart';

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
    if (priceCents <= 0) return 'Grat\u00eds';
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
  const BillingRepository(this._client, {LocalStorage? storage})
      : _storage = storage;

  final ApiClient _client;
  final LocalStorage? _storage;

  LocalStorage get _effectiveStorage => _storage ?? LocalStorage.instance;

  Future<List<BillingPlan>> getPlans() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.billingPlans);
      final payload = response.data as Map<String, dynamic>? ?? const {};
      final plansJson = payload['plans'] as List<dynamic>? ?? const [];
      if (plansJson.isNotEmpty) {
        final list = plansJson
            .map((item) => BillingPlan.fromJson(item as Map<String, dynamic>))
            .toList();
        return list.map((plan) {
          if (plan.priceCents > 0) {
            return BillingPlan(
              code: plan.code,
              name: 'Quiz Vance Premium',
              priceCents: 1490,
              currency: 'BRL',
              features: _defaultPlans.first.features,
            );
          }
          return plan;
        }).toList();
      }
      return _defaultPlans;
    } catch (_) {
      return _defaultPlans;
    }
  }

  static const _defaultPlans = <BillingPlan>[
    BillingPlan(
      code: 'premium_30',
      name: 'Quiz Vance Premium',
      priceCents: 1490,
      currency: 'BRL',
      features: [
        'Quizzes e questões ilimitadas com IA',
        'Simulados completos com gabarito comentado',
        'Revisão de questões erradas',
        'Plano de estudo semanal personalizado',
        'Correção de respostas abertas e dissertativas',
      ],
    ),
    BillingPlan(
      code: 'free',
      name: 'Plano Gratuito',
      priceCents: 0,
      currency: 'BRL',
      features: [
        'Até 10 questões por vez',
        'Histórico básico de estudo',
      ],
    ),
  ];

  Future<BillingStatus> getStatus() async {
    String? raw;
    try {
      final cachedUserRaw = await _effectiveStorage.getCacheValue('auth_user_cache', scoped: false);
      final cachedUserRawOld = await _effectiveStorage.getCacheValue('auth_user', scoped: false);
      raw = cachedUserRaw ?? cachedUserRawOld;
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          final role = (decoded['role'] as String?)?.trim().toLowerCase() ?? '';
          if (role == 'admin') {
            return const BillingStatus(
              planCode: 'premium',
              isPremium: true,
            );
          }
        } catch (_) {}
      }
    } catch (_) {}

    try {
      final response = await _client.dio.get(ApiEndpoints.billingStatus);
      final json = response.data as Map<String, dynamic>;
      final role = (json['role'] as String?)?.trim().toLowerCase() ?? '';
      final isPremium = json['is_premium'] == true ||
          json['premium_active'] == true ||
          json['plan_type'] == 'premium' ||
          json['plan_code'] == 'premium' ||
          role == 'admin' ||
          json['is_admin'] == true;
      return BillingStatus(
        planCode:
            isPremium ? 'premium' : (json['plan_code']?.toString() ?? 'free'),
        isPremium: isPremium,
        premiumUntil: json['premium_until']?.toString(),
      );
    } on DioException catch (error) {
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          final role = (decoded['role'] as String?)?.trim().toLowerCase() ?? '';
          if (role == 'admin') {
            return const BillingStatus(
              planCode: 'premium',
              isPremium: true,
            );
          }
        } catch (_) {}
      }
      throw buildRemoteServiceException(
        error,
        fallback: 'Não foi possível verificar o status do plano.',
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
        fallback:
            'Não foi possível iniciar o checkout. Tente novamente.',
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

final billingStatusProvider = FutureProvider.autoDispose<BillingStatus>((ref) async {
  final authState = ref.watch(authStateNotifierProvider).valueOrNull;
  if (authState?.isAdmin == true || authState?.isPremium == true) {
    return const BillingStatus(
      planCode: 'premium',
      isPremium: true,
    );
  }
  return ref.watch(billingRepositoryProvider).getStatus();
});
