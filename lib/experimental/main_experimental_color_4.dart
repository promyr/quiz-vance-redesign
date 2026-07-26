import 'package:flutter/material.dart';

import 'experimental_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const QuizVanceExperimentalApp(
      variant: '4',
      title: 'Quiz Vance Cor 4',
    ),
  );
}
