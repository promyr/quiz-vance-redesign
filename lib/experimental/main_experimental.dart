import 'package:flutter/material.dart';

import 'experimental_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const QuizVanceExperimentalApp(
      variant: 'tech',
      title: 'Quiz Vance Experimental',
    ),
  );
}
