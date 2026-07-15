import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/core/config/app_config.dart';

void main() {
  test('default app version matches pubspec release version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*([^+\s]+)', multiLine: true)
        .firstMatch(pubspec)!
        .group(1);

    expect(AppConfig.appVersion, version);
  });

  test('Android release requires signing and enables shrinking', () {
    final gradle = File('android/app/build.gradle').readAsStringSync();

    expect(gradle, contains('Release signing credentials are required'));
    expect(gradle, isNot(contains('signingConfigs.debug')));
    expect(gradle, contains('minifyEnabled true'));
    expect(gradle, contains('shrinkResources true'));
    expect(gradle, contains('proguard-android-optimize.txt'));
  });

  test('CI derives and passes APP_VERSION to release builds', () {
    final githubActions =
        File('.github/workflows/build.yml').readAsStringSync();
    final codemagic = File('codemagic.yaml').readAsStringSync();

    expect(githubActions, contains('APP_VERSION='));
    expect(githubActions, contains('--dart-define=APP_VERSION='));
    expect(codemagic, contains('APP_VERSION='));
    expect(codemagic, contains('--dart-define=APP_VERSION='));
  });
}
