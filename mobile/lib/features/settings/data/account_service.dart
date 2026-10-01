import 'package:dio/dio.dart';

import '../../../core/error/failure.dart';

/// The only Settings action routed through the backend, not straight to Supabase — deleting `auth.users` needs the service_role key.
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
