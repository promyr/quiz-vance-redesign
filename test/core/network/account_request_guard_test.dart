import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/shared/application/account_scoped_preferences.dart';

class Client extends ApiClient {
  final token = Completer<String?>();
  @override
  Future<String?> getAccessToken() => token.future;
}

void main() {
  test('request cannot use a token loaded after account changed', () async {
    AccountScopedPreferences.instance.setActiveAccountId('alice');
    final client = Client();
    var forwarded = 0;
    client.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (options, handler) {
      forwarded++;
      handler.resolve(Response(requestOptions: options, data: {'ok': true}));
    }));
    final request = client.dio.post('/quiz/submit',
        options: Options(extra: {'expectedAccountId': 'alice'}));
    final assertion = expectLater(
        request,
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.cancel)));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    AccountScopedPreferences.instance.setActiveAccountId('bob');
    client.token.complete('test-token');
    await assertion;
    expect(forwarded, 0);
  });
}
