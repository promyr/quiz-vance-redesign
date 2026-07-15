import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_error_message.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.ok,
    required this.platform,
    this.latestVersion,
    this.minimumSupportedVersion,
    this.downloadUrl,
    this.releaseNotes,
    this.publishedAt,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    final publishedAt = json['published_at']?.toString();
    return AppUpdateInfo(
      ok: json['ok'] as bool? ?? true,
      platform: json['platform']?.toString() ?? 'android',
      latestVersion: json['latest_version']?.toString(),
      minimumSupportedVersion: json['minimum_supported_version']?.toString(),
      downloadUrl: json['download_url']?.toString(),
      releaseNotes: json['release_notes']?.toString(),
      publishedAt: publishedAt == null ? null : DateTime.tryParse(publishedAt),
    );
  }

  final bool ok;
  final String platform;
  final String? latestVersion;
  final String? minimumSupportedVersion;
  final String? downloadUrl;
  final String? releaseNotes;
  final DateTime? publishedAt;
}

class AppUpdateRepository {
  const AppUpdateRepository(this._client);

  final ApiClient _client;

  Future<AppUpdateInfo> getUpdateInfo({String platform = 'android'}) async {
    try {
      final response = await _client.dio.get(
        ApiEndpoints.appUpdate,
        queryParameters: {'platform': platform},
      );
      return AppUpdateInfo.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (error) {
      throw buildRemoteServiceException(
        error,
        fallback: 'Nao foi possivel verificar atualizacoes do aplicativo.',
        connectivityFallback:
            'Nao foi possivel conectar ao servico de atualizacoes.',
      );
    }
  }
}

final appUpdateRepositoryProvider = Provider<AppUpdateRepository>(
  (ref) => AppUpdateRepository(ref.watch(apiClientProvider)),
);
