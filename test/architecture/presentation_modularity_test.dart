import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('telas de entrada delegam secoes extensas para arquivos coesos', () {
    final profile =
        File('lib/features/profile/presentation/profile_screen.dart')
            .readAsLinesSync();
    final studyPlan =
        File('lib/features/study_plan/presentation/study_plan_screen.dart')
            .readAsLinesSync();
    final library =
        File('lib/features/library/presentation/library_screen.dart')
            .readAsLinesSync();
    final home = File('lib/features/home/presentation/home_screen.dart')
        .readAsLinesSync();
    final premium =
        File('lib/features/profile/presentation/premium_screen.dart')
            .readAsLinesSync();
    final quizSession =
        File('lib/features/quiz/presentation/quiz_session_screen.dart')
            .readAsLinesSync();
    final quizConfig =
        File('lib/features/quiz/presentation/quiz_config_screen.dart')
            .readAsLinesSync();
    final todayPlan =
        File('lib/features/study_plan/presentation/today_plan_screen.dart')
            .readAsLinesSync();
    final experimental =
        File('lib/experimental/presentation/experimental_shell_screen.dart')
            .readAsLinesSync();

    expect(profile.length, lessThan(500));
    expect(studyPlan.length, lessThan(1350));
    expect(library.length, lessThan(1000));
    expect(home.length, lessThan(500));
    expect(premium.length, lessThan(500));
    expect(quizSession.length, lessThan(900));
    expect(quizConfig.length, lessThan(800));
    expect(todayPlan.length, lessThan(750));
    expect(experimental.length, lessThan(250));
    expect(
      profile.join('\n'),
      allOf(
        contains("part 'profile_overview_sections.dart';"),
        contains("part 'profile_settings_sections.dart';"),
        contains("part 'profile_security_sheets.dart';"),
      ),
    );
    expect(studyPlan.join('\n'), contains("part 'study_plan_widgets.dart';"));
    expect(library.join('\n'), contains("part 'library_document_cards.dart';"));
    expect(
      home.join('\n'),
      allOf(
        contains("part 'home_progress_sections.dart';"),
        contains("part 'home_action_sections.dart';"),
      ),
    );
    expect(
      premium.join('\n'),
      contains("part 'premium_screen_sections.dart';"),
    );
    expect(
      quizSession.join('\n'),
      contains("part 'quiz_session_sections.dart';"),
    );
    expect(
      quizConfig.join('\n'),
      contains("part 'quiz_config_sections.dart';"),
    );
    expect(
      todayPlan.join('\n'),
      contains("part 'today_plan_sections.dart';"),
    );
    expect(
      experimental.join('\n'),
      contains("part 'experimental_shell_sections.dart';"),
    );
  });

  test('fontes nao contem marcadores de truncamento de ferramenta', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(sources, isNot(contains('tokens truncated')));
  });

  test('arquivos de secao permanecem pequenos e focados', () {
    const sectionFiles = <String>[
      'lib/features/home/presentation/home_action_sections.dart',
      'lib/features/home/presentation/home_progress_sections.dart',
      'lib/features/profile/presentation/profile_overview_sections.dart',
      'lib/features/profile/presentation/profile_settings_sections.dart',
      'lib/features/profile/presentation/profile_security_sheets.dart',
      'lib/features/profile/presentation/premium_screen_sections.dart',
      'lib/features/quiz/presentation/quiz_config_sections.dart',
      'lib/features/quiz/presentation/quiz_session_sections.dart',
      'lib/features/study_plan/presentation/today_plan_sections.dart',
      'lib/experimental/presentation/experimental_shell_sections.dart',
    ];

    for (final path in sectionFiles) {
      expect(
        File(path).readAsLinesSync().length,
        lessThan(900),
        reason: '$path voltou a concentrar responsabilidades demais',
      );
    }
  });
}
