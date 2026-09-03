/// Base type for expected, user-facing failures surfaced by repositories.
///
/// Controllers catch exceptions from data sources and translate them into
/// a `Failure` so the UI always has a stable, human-readable `message` to
/// show — instead of leaking raw platform/SDK exceptions.
sealed class Failure {
  const Failure(this.message);

  final String message;

  // Every call site that renders an error does `error.toString()` (e.g.
  // `context.showErrorSnackBar(error.toString())`) — without this override
  // that prints "Instance of 'AuthFailure'" instead of the actual message.
  @override
  String toString() => message;
}

class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message);
}
