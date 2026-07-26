import 'package:flutter/material.dart';

import 'presentation/experimental_shell_screen.dart';
import 'theme/experimental_theme.dart';

class QuizVanceExperimentalApp extends StatelessWidget {
  const QuizVanceExperimentalApp({
    super.key,
    required this.variant,
    required this.title,
  });

  final String variant;
  final String title;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      theme: buildExperimentalTheme(variant: variant),
      home: ExperimentalShellScreen(variant: variant),
    );
  }
}
