import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/exceptions/remote_service_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_error_message.dart';
import '../domain/activity_entry.dart';

class HistoryRepository {
  const HistoryRepository(this._client);

  final ApiClient _client;

  Future<List<ActivityEntry>> getHistory({int limit = 50}) async {
    try {
      final response = await _client.dio.get(
        ApiEndpoints.quizHistory,
        queryParameters: {'limit': limit},
      );
      final raw = response.data as Map<String, dynamic>?;
      final list = raw?['history'] as List<dynamic>? ?? [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(ActivityEntry.fromJson)
          .toList();
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? 0;
      final detail = extractApiErrorMessage(error.response?.data);

      if (statusCode >= 400 && statusCode < 500) {
        throw RemoteServiceException(detail ?? 'Erro $statusCode ao carregar histórico');
      }

      throw RemoteServiceException(
        'Não foi possível carregar o histórico. Verifique sua conexão e tente novamente.',
      );
    }
  }
}

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => HistoryRepository(ref.watch(apiClientProvider)),
);

final activityHistoryProvider =
    FutureProvider.autoDispose<List<ActivityEntry>>((ref) async {
  return ref.watch(historyRepositoryProvider).getHistory();
});
