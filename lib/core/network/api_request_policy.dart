import 'api_endpoints.dart';

const _publicPaths = <String>{
  ApiEndpoints.login,
  ApiEndpoints.register,
  ApiEndpoints.refreshToken,
  ApiEndpoints.passwordResetRequest,
  ApiEndpoints.passwordResetConfirm,
  ApiEndpoints.appUpdate,
};

bool isPublicApiPath(String path) {
  final normalized = Uri.tryParse(path)?.path ?? path;
  return _publicPaths.contains(normalized);
}

bool isIdempotentMethod(String method) {
  return const {'GET', 'HEAD', 'OPTIONS'}.contains(method.toUpperCase());
}

bool isRetryableStatus(int? statusCode) {
  return statusCode == 408 ||
      statusCode == 429 ||
      (statusCode != null && statusCode >= 500 && statusCode <= 599);
}

bool isLongRunningApiPath(String path) {
  final normalized = Uri.tryParse(path)?.path ?? path;
  return const <String>{
    ApiEndpoints.quizGenerate,
    ApiEndpoints.simuladoGenerate,
    ApiEndpoints.quizOpenGenerate,
    ApiEndpoints.quizOpenGrade,
    ApiEndpoints.libraryGeneratePackage,
    ApiEndpoints.studyPlanGenerate,
  }.contains(normalized);
}
