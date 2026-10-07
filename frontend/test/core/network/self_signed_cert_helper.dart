import 'dart:io';

/// Самоподписанный сертификат для loopback-тестов.
///
/// Генерируется через openssl один раз на вызов (в setUpAll тестов);
/// openssl есть в dev-окружении. Возвращает пути и cleanup.
Future<({String cert, String key, Future<void> Function() dispose})>
createSelfSignedCert() async {
  final dir = await Directory.systemTemp.createTemp('flux_selfsigned');
  final result = await Process.run('openssl', [
    'req',
    '-x509',
    '-newkey',
    'rsa:2048',
    '-keyout',
    '${dir.path}/key.pem',
    '-out',
    '${dir.path}/cert.pem',
    '-days',
    '1',
    '-nodes',
    '-subj',
    '/CN=127.0.0.1',
    '-addext',
    'subjectAltName=IP:127.0.0.1',
  ]);
  if (result.exitCode != 0) {
    await dir.delete(recursive: true);
    throw StateError('openssl failed: ${result.stderr}');
  }
  return (
    cert: '${dir.path}/cert.pem',
    key: '${dir.path}/key.pem',
    dispose: () => dir.delete(recursive: true),
  );
}

/// HTTPS-сервер на loopback с выданным сертом, отвечающий 200 OK.
Future<HttpServer> bindSecureOk(String cert, String key) async {
  final context = SecurityContext()
    ..useCertificateChain(cert)
    ..usePrivateKey(key);
  final server = await HttpServer.bindSecure(
    InternetAddress.loopbackIPv4,
    0,
    context,
  );
  server.listen((request) async {
    request.response.statusCode = HttpStatus.ok;
    await request.response.close();
  });
  return server;
}
