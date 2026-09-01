class Failure implements Exception {
  final String message;
  final Object? cause;
  const Failure(this.message, {this.cause});
  @override
  String toString() =>
      'Failure: $message${cause != null ? ' (cause: $cause)' : ''}';
}

class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}
