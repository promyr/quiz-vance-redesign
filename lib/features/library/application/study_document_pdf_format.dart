const _pdfSignature = <int>[0x25, 0x50, 0x44, 0x46, 0x2D];

/// Reconhece `%PDF-` nos primeiros 1024 bytes.
///
/// Alguns provedores Android inserem um pequeno prefixo antes do cabeçalho,
/// portanto a assinatura não precisa começar no byte zero.
bool hasPdfSignature(List<int> bytes) {
  final limit = bytes.length < 1024 ? bytes.length : 1024;
  for (var start = 0; start <= limit - _pdfSignature.length; start++) {
    var matches = true;
    for (var index = 0; index < _pdfSignature.length; index++) {
      if (bytes[start + index] != _pdfSignature[index]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}
