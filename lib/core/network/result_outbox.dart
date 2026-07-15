import 'dart:convert';

import 'package:dio/dio.dart';

import '../storage/local_storage.dart';

class PendingResultSubmission {
  const PendingResultSubmission({
    required this.id,
    required this.endpoint,
    required this.payload,
  });

  final String id;
  final String endpoint;
  final Map<String, dynamic> payload;
}

class ResultOutbox {
  ResultOutbox._();

  static final ResultOutbox instance = ResultOutbox._();

  Future<void> enqueue(PendingResultSubmission submission) {
    return LocalStorage.instance.upsertPendingResult(
      id: submission.id,
      endpoint: submission.endpoint,
      payload: submission.payload,
    );
  }

  Future<void> remove(String id) =>
      LocalStorage.instance.deletePendingResult(id);

  Future<void> flush(Dio dio) async {
    final pending = await LocalStorage.instance.listPendingResults();
    for (final row in pending) {
      final id = row['remote_id']?.toString() ?? '';
      if (id.isEmpty) continue;
      try {
        final data = jsonDecode(row['data_json']?.toString() ?? '{}');
        if (data is! Map<String, dynamic>) continue;
        final endpoint = data['endpoint']?.toString() ?? '';
        final payload = data['payload'];
        if (endpoint.isEmpty || payload is! Map<String, dynamic>) continue;
        await dio.post(
          endpoint,
          data: payload,
          options: Options(headers: {'Idempotency-Key': id}),
        );
        await remove(id);
      } on DioException {
        return;
      }
    }
  }
}
