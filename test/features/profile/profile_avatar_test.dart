import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/profile/domain/profile_avatar.dart';

void main() {
  group('profile avatar helpers', () {
    test('decodeProfileAvatarBytes returns bytes from data uri', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final dataUri = 'data:image/png;base64,${base64Encode(bytes)}';

      expect(decodeProfileAvatarBytes(dataUri), equals(bytes));
    });

    test('decodeProfileAvatarBytes ignores regular urls', () {
      expect(
        decodeProfileAvatarBytes('https://cdn.quizvance.app/avatar.png'),
        isNull,
      );
    });

    test('isRemoteProfileAvatar detects remote http urls', () {
      expect(isRemoteProfileAvatar('https://cdn.quizvance.app/avatar.png'),
          isTrue);
      expect(
          isRemoteProfileAvatar('http://cdn.quizvance.app/avatar.png'), isTrue);
      expect(isRemoteProfileAvatar('data:image/png;base64,abc'), isFalse);
    });

    test('buildProfileAvatarDataUri uses mime type from file extension', () {
      final result = buildProfileAvatarDataUri(
        bytes: Uint8List.fromList([9, 8, 7]),
        fileName: 'foto.jpg',
      );

      expect(result.startsWith('data:image/jpeg;base64,'), isTrue);
    });
  });
}
