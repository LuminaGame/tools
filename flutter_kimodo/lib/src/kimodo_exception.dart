/// A kimodo call failed: the runtime could not be loaded, a model could not
/// be read, or a generation was refused. [message] is kimodo's own reason
/// with the context flutter_kimodo adds.
class KimodoException implements Exception {
  final String message;
  const KimodoException(this.message);

  @override
  String toString() => 'KimodoException: $message';
}
