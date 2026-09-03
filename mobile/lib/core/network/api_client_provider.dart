import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/env.dart';
import 'supabase_client_provider.dart';

/// Dio client for the LifeSearch AI Service (backend/). `null` when
/// `BACKEND_URL` isn't configured — callers treat that the same as any
/// other "AI processing unavailable" failure.
final apiClientProvider = Provider<Dio?>((ref) {
  final baseUrl = Env.backendUrl;
  if (baseUrl == null) return null;

  final dio = Dio(BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 5)));

  // Every backend request is scoped by the caller's own Supabase session
  // (see backend/app/core/security.py) — never an admin/service key.
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = ref.read(supabaseClientProvider).auth.currentSession?.accessToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ),
  );

  return dio;
});
