sealed class Result<T> {
  const Result();
  R when<R>({
    required R Function(T value) ok,
    required R Function(Object error, StackTrace? stack) err,
  });
}

class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
  @override
  R when<R>({
    required R Function(T value) ok,
    required R Function(Object error, StackTrace? stack) err,
  }) => ok(value);
}

class Err<T> extends Result<T> {
  final Object error;
  final StackTrace? stack;
  const Err(this.error, [this.stack]);
  @override
  R when<R>({
    required R Function(T value) ok,
    required R Function(Object error, StackTrace? stack) err,
  }) => err(error, stack);
}
