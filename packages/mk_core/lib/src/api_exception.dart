/// A standardized error from the Mukafaah API (RFC 9457 problem details) or the network.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.status,
    this.message,
    this.retryAfterSec,
  });

  /// Stable machine code, e.g. INSUFFICIENT_BALANCE, OTP_INVALID, NETWORK.
  final String code;
  final int status;
  final String? message;
  final int? retryAfterSec;

  bool get isNetwork => code == 'NETWORK' || code == 'TIMEOUT';
  bool get isUnauthorized => status == 401;

  @override
  String toString() => 'ApiException($status $code ${message ?? ''})';
}
