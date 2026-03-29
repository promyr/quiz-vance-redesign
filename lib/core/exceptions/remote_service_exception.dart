class RemoteServiceException implements Exception {
  const RemoteServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
