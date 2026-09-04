import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final networkStatusNotifierProvider =
    StateNotifierProvider<NetworkStatusNotifier, bool>((ref) {
  return NetworkStatusNotifier();
});

class NetworkStatusNotifier extends StateNotifier<bool> {
  NetworkStatusNotifier() : super(true) {
    _initCheck();
  }

  Timer? _timer;

  void _initCheck() {
    checkConnection();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => checkConnection());
  }

  Future<void> checkConnection() async {
    try {
      final result = await InternetAddress.lookup('dns.google')
          .timeout(const Duration(seconds: 4));
      final online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      if (mounted && state != online) {
        state = online;
      }
    } catch (_) {
      if (mounted && state != false) {
        state = false;
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
