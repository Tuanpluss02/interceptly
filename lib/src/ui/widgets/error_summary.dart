String summarizeRequestError({
  String? errorType,
  String? errorMessage,
}) {
  final source = '${errorType ?? ''} ${errorMessage ?? ''}'.toLowerCase();

  bool hasAny(List<String> terms) => terms.any(source.contains);

  if (hasAny([
    'timeout',
    'timed out',
    'timeoutexception',
    'connection timeout',
    'receive timeout',
    'send timeout',
    'sockettimeout',
    'nsurlerrortimedout',
    'errno = 110',
    'etimedout',
  ])) {
    return 'Timed out';
  }

  if (hasAny([
    'failed host lookup',
    'name or service not known',
    'nodename nor servname',
    'no address associated with hostname',
    'dns',
    'host lookup',
    'nsurlerrorcannotfindhost',
    'nsurlerrordnslookupfailed',
    'unable to resolve host',
    'enotfound',
    'gaierror',
  ])) {
    return 'Host unreachable';
  }

  if (hasAny([
    'network is unreachable',
    'network unreachable',
    'networkrequestfailed',
    'offline',
    'no internet',
    'internet unavailable',
    'software caused connection abort',
    'errno = 101',
    'enetunreach',
    'ehostunreach',
    'nsurlerrornotconnectedtointernet',
    'nsurlerrornetworkconnectionlost',
  ])) {
    return 'No internet';
  }

  if (hasAny([
    'connection refused',
    'connection reset',
    'broken pipe',
    'econnrefused',
    'econnreset',
    'connection closed before full header was received',
    'connection terminated during handshake',
    'errno = 111',
    'errno = 104',
    'connection closed',
    'socketexception: write failed',
    'socketexception: connection failed',
    'failed to connect',
    'cannot assign requested address',
  ])) {
    return 'Server unreachable';
  }

  if (hasAny([
    'ssl',
    'tls',
    'certificate',
    'handshake',
    'certificateverifyfailed',
    'nsurlerrorsecureconnectionfailed',
    'nsurlerrorservercertificateuntrusted',
    'nsurlerrorservercertificatehasbaddate',
    'nsurlerrorservercertificatehasunknownroot',
    'sslpeerunverifiedexception',
    'cert_path_validator_exception',
  ])) {
    return 'SSL error';
  }

  if (hasAny([
    'cancelled',
    'canceled',
    'cancel',
    'aborted',
    'abort',
    'nsurlerrorcancelled',
    'dioexceptiontype.cancel',
    'request_cancelled',
  ])) {
    return 'Request cancelled';
  }

  return 'Request failed';
}
