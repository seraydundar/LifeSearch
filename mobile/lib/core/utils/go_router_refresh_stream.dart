import 'dart:async';

import 'package:flutter/foundation.dart';

/// Bridges a `Stream` (here: Supabase's auth state changes) to go_router's
/// `Listenable`-based `refreshListenable`, so the router re-evaluates its
/// `redirect` callback whenever the user signs in/out.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
