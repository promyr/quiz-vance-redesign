import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppPressable extends StatelessWidget {
  const AppPressable({
    super.key,
    required this.onPressed,
    required this.child,
    this.semanticLabel,
    this.semanticHint,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.onTapDown,
    this.onTapUp,
    this.onTapCancel,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final String? semanticLabel;
  final String? semanticHint;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;
  final GestureTapDownCallback? onTapDown;
  final GestureTapUpCallback? onTapUp;
  final GestureTapCancelCallback? onTapCancel;

  bool get _isEnabled => enabled && onPressed != null;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: _isEnabled,
      focusable: _isEnabled,
      label: semanticLabel,
      hint: semanticHint,
      onTap: _isEnabled ? onPressed : null,
      child: ExcludeSemantics(
        child: FocusableActionDetector(
          enabled: _isEnabled,
          focusNode: focusNode,
          autofocus: autofocus,
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                onPressed?.call();
                return null;
              },
            ),
          },
          child: MouseRegion(
            cursor: _isEnabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _isEnabled ? onPressed : null,
              onTapDown: _isEnabled ? onTapDown : null,
              onTapUp: _isEnabled ? onTapUp : null,
              onTapCancel: _isEnabled ? onTapCancel : null,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
