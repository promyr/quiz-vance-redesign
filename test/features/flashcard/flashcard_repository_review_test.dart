import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/network/api_endpoints.dart';
import 'package:quiz_vance_flutter/core/storage/local_storage.dart';
import 'package:quiz_vance_flutter/features/flashcard/data/flashcard_repository.dart';
import 'package:quiz_vance_flutter/features/flashcard/domain/flashcard_model.dart';
import 'package:quiz_vance_flutter/shared/application/account_scoped_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends Mock implements ApiClient {}

class _Dio extends Mock implements Dio {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  setUp(() async {
    tempDir =
        await Directory.systemTemp.createTemp('flashcard_review_contract_');
    await LocalStorage.instance
        .configureForTesting(databasePath: path.join(tempDir.path, 'cards.db'));
    SharedPreferences.setMockInitialValues({});
    AccountScopedPreferences.instance.setActiveAccountId('student');
    await LocalStorage.instance.init();
    LocalStorage.instance.setActiveAccountId('student');
  });
  tearDown(() async {
    await LocalStorage.instance.resetForTesting();
    await tempDir.delete(recursive: true);
  });
  test(
      'review returns updated card for the next cycle and keeps stable sync identity',
      () async {
    final api = _Api();
    final dio = _Dio();
    when(() => api.dio).thenReturn(dio);
    final payloads = <Map<String, dynamic>>[];
    when(() => dio.post(ApiEndpoints.flashcardsReview,
        data: any(named: 'data'),
        options: any(named: 'options'))).thenAnswer((invocation) async {
      payloads.add(
          Map<String, dynamic>.from(invocation.namedArguments[#data] as Map));
      return Response(
          requestOptions: RequestOptions(path: ApiEndpoints.flashcardsReview),
          data: {'xp_earned': 5});
    });
    final created = DateTime.utc(2026, 1, 10);
    final id = await LocalStorage.instance.upsertFlashcard({
      'front': 'Question',
      'back': 'Answer',
      'due_date': '2026-01-10',
      'created_at': created.toIso8601String()
    });
    final card = Flashcard(
        id: id,
        front: 'Question',
        back: 'Answer',
        dueDate: created,
        createdAt: created);
    final repo = FlashcardRepository(api);
    final dynamic first =
        await (repo as dynamic).review(card: card, grade: FsrsGrade.good);
    expect(first, isA<Flashcard>());
    final firstCard = first as Flashcard;
    expect(firstCard.repetitions, 1);
    final dynamic second =
        await (repo as dynamic).review(card: firstCard, grade: FsrsGrade.good);
    expect((second as Flashcard).intervalDays, 6);
    expect(second.repetitions, 2);
    expect(payloads[0]['flashcard_id'], payloads[1]['flashcard_id']);
    expect(payloads[1]['repetitions'], 1);
    final stored = (await LocalStorage.instance.getReviewFlashcards()).single;
    expect(stored['interval_days'], 6);
    expect(stored['repetitions'], 2);
  });
}
