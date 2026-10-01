import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_user.freezed.dart';

/// Thin domain entity — keep the Supabase SDK out of code outside `features/auth/data`.
@freezed
sealed class AppUser with _$AppUser {
  const factory AppUser({
    required String id,
    required String email,
  }) = _AppUser;
}
