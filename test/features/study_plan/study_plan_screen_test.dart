import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quiz_vance_flutter/features/study_plan/presentation/study_plan_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('study plan date helpers', () {
    test('formatStudyPlanDate returns dd/MM/yyyy', () {
      expect(
        formatStudyPlanDate(DateTime(2027, 4, 5)),
        '05/04/2027',
      );
    });

    test('parseStudyPlanDateOrNull parses a valid date', () {
      final parsed = parseStudyPlanDateOrNull('25/03/2026');

      expect(parsed, isNotNull);
      expect(parsed!.day, 25);
      expect(parsed.month, 3);
      expect(parsed.year, 2026);
    });

    test('parseStudyPlanDateOrNull rejects invalid dates', () {
      expect(parseStudyPlanDateOrNull('31/02/2026'), isNull);
      expect(parseStudyPlanDateOrNull('2204'), isNull);
      expect(parseStudyPlanDateOrNull('2026-03-25'), isNull);
    });
  });

  testWidgets('date field is readOnly and uses picker flow', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: StudyPlanScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('studyPlanDateField')),
        matching: find.byType(EditableText),
      ),
    );

    expect(editable.readOnly, isTrue);
    expect(find.text('DD/MM/AAAA'), findsOneWidget);
  });
}
