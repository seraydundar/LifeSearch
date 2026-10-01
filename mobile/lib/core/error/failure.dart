/// Base type for expected, user-facing failures surfaced by repositories.
sealed class Failure {
  const Failure(this.message);

  final String message;

  // Without this, error.toString() prints "Instance of 'AuthFailure'" instead of the message.
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
