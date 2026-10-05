// Dev-only: lets the *web* build reach Unstop, which sends no CORS headers.
// Phones don't need this. Run:  dart run tool/cors_proxy.dart
// then build web with:          --dart-define=UNSTOP_BASE=http://localhost:8787
import 'dart:io';

Future<void> main() async {
  final client = HttpClient();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8787);
  stdout.writeln('CORS proxy for unstop.com on http://localhost:8787');
  await for (final req in server) {
    req.response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Headers', '*');
    if (req.method == 'OPTIONS') {
      await req.response.close();
      continue;
    }
    try {
      final up = await client.getUrl(Uri.https('unstop.com', req.uri.path, req.uri.queryParameters));
      final res = await up.close();
      req.response.statusCode = res.statusCode;
      req.response.headers.contentType = res.headers.contentType;
      await res.pipe(req.response);
    } catch (e) {
      req.response
        ..statusCode = 502
        ..write('$e');
      await req.response.close();
    }
  }
}
