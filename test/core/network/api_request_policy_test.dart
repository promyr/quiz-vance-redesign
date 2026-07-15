import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/core/network/api_request_policy.dart';

void main() {
  test('marks authentication and update routes as public', () {
    expect(isPublicApiPath('/auth/login'), isTrue);
    expect(isPublicApiPath('/app/update?platform=android'), isTrue);
    expect(isPublicApiPath('/user/stats'), isFalse);
  });

  test('retries only safe methods and transient statuses', () {
    expect(isIdempotentMethod('GET'), isTrue);
    expect(isIdempotentMethod('POST'), isFalse);
    expect(isRetryableStatus(429), isTrue);
    expect(isRetryableStatus(503), isTrue);
    expect(isRetryableStatus(400), isFalse);
  });

  test('identifies AI operations that need a longer timeout', () {
    expect(isLongRunningApiPath('/quiz/generate'), isTrue);
    expect(isLongRunningApiPath('/simulado/generate'), isTrue);
    expect(isLongRunningApiPath('/user/stats'), isFalse);
  });
}
