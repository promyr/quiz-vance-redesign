import 'package:flutter/material.dart';

class StorageRecoveryApp extends StatefulWidget {
  const StorageRecoveryApp({
    super.key,
    required this.onRetry,
    required this.onRecovered,
  });

  final Future<void> Function() onRetry;
  final Future<void> Function() onRecovered;

  @override
  State<StorageRecoveryApp> createState() => _StorageRecoveryAppState();
}

class _StorageRecoveryAppState extends State<StorageRecoveryApp> {
  var _retrying = false;
  var _failedAgain = false;

  Future<void> _retry() async {
    setState(() {
      _retrying = true;
      _failedAgain = false;
    });
    try {
      await widget.onRetry();
      await widget.onRecovered();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _retrying = false;
        _failedAgain = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.security_rounded,
                    color: Color(0xFFF59E0B),
                    size: 52,
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Não foi possível abrir seus dados com segurança',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _failedAgain
                        ? 'A recuperação ainda não foi possível. Reinicie o aparelho e tente novamente.'
                        : 'Nenhum dado foi apagado. Tente novamente antes de usar o aplicativo.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _retrying ? null : _retry,
                    icon: _retrying
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label:
                        Text(_retrying ? 'Verificando...' : 'Tentar novamente'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
