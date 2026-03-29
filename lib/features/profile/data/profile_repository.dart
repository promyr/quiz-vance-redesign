import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
    this.planType = 'free',
  });

  factory UserProfile.fromJson(Map<String, dynamic> data) => UserProfile(
        id: (data['id'] as String?) ?? '',
        name: (data['name'] as String?) ?? 'Usuario',
        email: (data['email'] as String?) ?? '',
        avatarUrl: data['avatar_url'] as String?,
        planType: (data['plan_type'] as String?) ?? 'free',
      );

  final String id;
  final String name;
  final String email;
  final String? avatarUrl;
  final String planType;

  bool get isPremium => planType == 'premium';

  UserProfile copyWith({
    String? id,
    String? name,
    String? email,
    String? avatarUrl,
    String? planType,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      planType: planType ?? this.planType,
    );
  }
}

class ProfileRepository {
  const ProfileRepository(this._client);

  final ApiClient _client;

  Future<UserProfile> fetchProfile() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.userProfile);
      return UserProfile.fromJson(response.data as Map<String, dynamic>);
    } on DioException {
      return const UserProfile(id: '', name: 'Usuario', email: '');
    }
  }

  Future<void> updateProfile({String? name, String? avatarUrl}) async {
    final payload = <String, dynamic>{
      if (name != null && name.isNotEmpty) 'name': name,
      if (avatarUrl != null && avatarUrl.isNotEmpty) 'avatar_url': avatarUrl,
    };
    if (payload.isEmpty) {
      return;
    }

    try {
      await _client.dio.post(ApiEndpoints.userUpdateProfile, data: payload);
    } on DioException {
      // Update remoto do perfil e best-effort.
    }
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(apiClientProvider)),
);
