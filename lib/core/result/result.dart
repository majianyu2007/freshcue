import '../errors/app_failure.dart';

/// 轻量 Result 类型：成功携带值，失败携带 [AppFailure]。
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;

  T get value => (this as Ok<T>).data;

  AppFailure get failure => (this as Err<T>).error;

  R when<R>({
    required R Function(T value) ok,
    required R Function(AppFailure failure) err,
  }) =>
      switch (this) {
        Ok<T>(:final data) => ok(data),
        Err<T>(:final error) => err(error),
      };
}

class Ok<T> extends Result<T> {
  const Ok(this.data);
  final T data;
}

class Err<T> extends Result<T> {
  const Err(this.error);
  final AppFailure error;
}
