import 'package:dio/dio.dart';

import '../../../core/error/failure.dart';

/// Calls the backend's `DELETE /account/` (requirements doc, section
/// 49-52) — the only Settings action that goes through the backend
/// rather than straight to Supabase, since deleting the `auth.users` row
/// needs the service_role key, which only the backend ever holds.
class AccountService {
  AccountService(this._dio);

  final Dio? _dio;

  Future<void> deleteAccount() async {
    final dio = _dio;
    if (dio == null) {
      throw const UnexpectedFailure(
        'Hesap silme şu anda kullanılamıyor. Backend bağlantısı ayarlanmamış.',
      );
    }
    try {
      await dio.delete('/account/');
    } on DioException catch (e) {
      final detail = e.response?.data is Map ? e.response?.data['detail'] : null;
      throw UnexpectedFailure(
        detail as String? ?? 'Hesap silinemedi. Lütfen tekrar dene.',
      );
    }
  }
}
