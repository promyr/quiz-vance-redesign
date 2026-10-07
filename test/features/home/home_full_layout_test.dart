import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quiz_vance_flutter/features/home/presentation/home_screen.dart';
import 'package:quiz_vance_flutter/features/study_plan/data/study_plan_repository.dart';
import 'package:quiz_vance_flutter/shared/providers/user_provider.dart';
import 'package:quiz_vance_flutter/shared/providers/network_status_provider.dart';
import 'package:quiz_vance_flutter/features/profile/data/billing_repository.dart';
import 'package:quiz_vance_flutter/features/quiz/providers/quiz_do_dia_provider.dart';
import 'package:quiz_vance_flutter/features/error_notebook/providers/error_notebook_provider.dart';
import 'package:quiz_vance_flutter/features/error_notebook/domain/error_question.dart';

class _Stats extends UserStatsNotifier {
  _Stats(this.premium);
  final bool premium;
  @override
  Future<UserStats> build() async => UserStats(
      isPremium: premium,
      xp: 12850,
      level: 129,
      streak: 123,
      quizRestante: 10,
      quizLimite: 10);
}

class _Daily extends DailyChallengeNotifier {
  @override
  Future<DailyChallengeInfo> build() async => const DailyChallengeInfo(
      topic: 'Direito Constitucional e Direitos Fundamentais',
      dayName: 'Quarta-feira',
      bonusXp: 50,
      isCompletedToday: false);
}

class _Errors extends ErrorNotebookNotifier {
  @override
  Future<List<ErrorQuestion>> build() async => [];
}

class _Online extends NetworkStatusNotifier {
  @override
  Future<void> checkConnection() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('VisualTestFont');
    font.addFont(File(r'C:\Windows\Fonts\segoeui.ttf')
        .readAsBytes()
        .then((bytes) => ByteData.sublistView(bytes)));
    await font.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(File(
            r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf')
        .readAsBytes()
        .then((bytes) => ByteData.sublistView(bytes)));
    await icons.load();
  });
  for (final premium in [false, true]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('Home completa 320px fonte $scale premium $premium',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'premium_upsell_last_shown_date':
              DateTime.now().toIso8601String().substring(0, 10)
        });
        final boundary = GlobalKey();
        await tester.pumpWidget(ProviderScope(
            overrides: [
              activePlanProvider.overrideWith((ref) async => null),
              userStatsNotifierProvider.overrideWith(() => _Stats(premium)),
              billingStatusProvider.overrideWith((ref) async => BillingStatus(
                  planCode: premium ? 'premium' : 'free', isPremium: premium)),
              dailyChallengeNotifierProvider.overrideWith(_Daily.new),
              errorNotebookNotifierProvider.overrideWith(_Errors.new),
              networkStatusNotifierProvider.overrideWith((ref) => _Online()),
            ],
            child: MaterialApp(
                theme: ThemeData(fontFamily: 'VisualTestFont'),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!),
                home: RepaintBoundary(
                    key: boundary, child: const HomeScreen()))));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(tester.takeException(), isNull);
        if (premium && scale == 1.6) {
          final render = boundary.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await render.toImage(pixelRatio: 1);
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final screenshot = File('output_apk/home-layout-320-font160.png');
            await screenshot.parent.create(recursive: true);
            await screenshot.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        for (var step = 0; step < 7; step++) {
          await tester.drag(
              find.byType(CustomScrollView).first, const Offset(0, -350));
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
      });
    }
  }
}
