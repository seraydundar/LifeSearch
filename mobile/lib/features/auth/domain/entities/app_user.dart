import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_user.freezed.dart';

/// The authenticated user, as far as the rest of the app needs to know.
///
/// Deliberately minimal — a thin domain entity, not a raw Supabase `User`.
/// Nothing outside `features/auth/data` should import the Supabase SDK.
@freezed
sealed class AppUser with _$AppUser {
  const factory AppUser({
    required String id,
    required String email,
  }) = _AppUser;
}
