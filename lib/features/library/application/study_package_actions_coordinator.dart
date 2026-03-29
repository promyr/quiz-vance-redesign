import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_storage.dart';
import '../domain/library_model.dart';

class StudyPackageSaveResult {
  const StudyPackageSaveResult({
    required this.savedCount,
  });

  final int savedCount;
}

class StudyPackageActionsCoordinator {
  StudyPackageActionsCoordinator({
    LocalStorage? storage,
  }) : _storage = storage ?? LocalStorage.instance;

  final LocalStorage _storage;

  Future<StudyPackageSaveResult> saveFlashcards({
    required StudyPackage package,
  }) async {
    final now = DateTime.now();
    for (final card in package.flashcards) {
      await _storage.upsertFlashcard({
        'remote_id': null,
        'front': card['front'] ?? '',
        'back': card['back'] ?? '',
        'topic': package.titulo,
        'interval_days': 1,
        'easiness': 2.5,
        'due_date': now.toIso8601String().substring(0, 10),
        'repetitions': 0,
        'last_reviewed': null,
        'synced': 0,
        'created_at': now.toIso8601String(),
      });
    }

    return StudyPackageSaveResult(savedCount: package.flashcards.length);
  }
}

final studyPackageActionsCoordinatorProvider =
    Provider<StudyPackageActionsCoordinator>(
  (ref) => StudyPackageActionsCoordinator(),
);
