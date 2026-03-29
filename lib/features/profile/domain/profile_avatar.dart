import 'dart:convert';
import 'dart:typed_data';

Uint8List? decodeProfileAvatarBytes(String? avatarUrl) {
  if (avatarUrl == null || avatarUrl.isEmpty) {
    return null;
  }

  if (!avatarUrl.startsWith('data:image/')) {
    return null;
  }

  final commaIndex = avatarUrl.indexOf(',');
  if (commaIndex <= 0 || commaIndex == avatarUrl.length - 1) {
    return null;
  }

  try {
    return base64Decode(avatarUrl.substring(commaIndex + 1));
  } catch (_) {
    return null;
  }
}

bool isRemoteProfileAvatar(String? avatarUrl) {
  if (avatarUrl == null || avatarUrl.isEmpty) {
    return false;
  }

  final normalized = avatarUrl.trim().toLowerCase();
  return normalized.startsWith('http://') || normalized.startsWith('https://');
}

String buildProfileAvatarDataUri({
  required Uint8List bytes,
  required String fileName,
}) {
  final lowerName = fileName.toLowerCase();
  final mimeType = switch (true) {
    _ when lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg') =>
      'image/jpeg',
    _ when lowerName.endsWith('.webp') => 'image/webp',
    _ when lowerName.endsWith('.gif') => 'image/gif',
    _ => 'image/png',
  };
  return 'data:$mimeType;base64,${base64Encode(bytes)}';
}
