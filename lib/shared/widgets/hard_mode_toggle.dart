import 'package:flutter/material.dart';

/// Difficulty is chosen for this session only; mixed is the initial state.
class HardModeToggle extends StatelessWidget {
  const HardModeToggle({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: enabled,
      onChanged: onChanged,
      title: const Text('Modo difícil'),
      subtitle: Text(
          enabled ? 'Somente questões difíceis' : 'Questões médias e difíceis'),
    );
  }
}
