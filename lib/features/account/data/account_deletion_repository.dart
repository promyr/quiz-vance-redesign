import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_error_message.dart';

class DeleteAccountRequest {
  const DeleteAccountRequest({
    required this.currentPassword,
    required this.confirmationText,
  });

  final String currentPassword;
  final String confirmationText;

  Map<String, dynamic> toJson() => {
        'current_password': currentPassword,
        'confirmation_text': confirmationText,
      };
}

class AccountDeletionRepository {
  const AccountDeletionRepository(this._client);

  final ApiClient _client;

  Future<void> deleteAccount(DeleteAccountRequest request) async {
    try {
      await _client.dio.delete(
        ApiEndpoints.userAccount,
        data: request.toJson(),
      );
    } on DioException catch (error) {
      throw buildRemoteServiceException(
        error,
        fallback: 'Nao foi possivel excluir a conta.',
        connectivityFallback:
            'Nao foi possivel conectar ao servico de exclusao de conta.',
      );
    }
  }
}

final accountDeletionRepositoryProvider = Provider<AccountDeletionRepository>(
  (ref) => AccountDeletionRepository(ref.watch(apiClientProvider)),
);
