import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web_auditor/models/audit_report.dart';
import 'package:web_auditor/services/ai_slop_analyzer.dart';
import 'package:web_auditor/services/audit_orchestrator.dart';
import 'package:web_auditor/services/error_scanner.dart';
import 'package:web_auditor/services/http_fetcher.dart';
import 'package:web_auditor/services/security_scanner.dart';

void main() {
  group('HttpFetcher', () {
    test('menambahkan https:// otomatis jika skema tidak ada', () {
      final uri = HttpFetcher.normalizeAndValidateUrl('example.com/path');
      expect(uri.scheme, 'https');
      expect(uri.host, 'example.com');
      expect(uri.path, '/path');
    });

    test('menolak input kosong dan skema tidak didukung', () {
      expect(
        () => HttpFetcher.normalizeAndValidateUrl('   '),
        throwsA(isA<FetchException>()),
      );
      expect(
        () => HttpFetcher.normalizeAndValidateUrl('ftp://example.com'),
        throwsA(isA<FetchException>()),
      );
    });

    test('memecah header Set-Cookie tanpa merusak koma pada Expires', () {
      const raw =
          'session=abc123; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/; HttpOnly, '
          'prefs=dark; Path=/; Secure; SameSite=Lax';
      final cookies = HttpFetcher.splitSetCookieHeader(raw);
      expect(cookies, hasLength(2));
      expect(cookies.first, startsWith('session=abc123'));
      expect(cookies.last, startsWith('prefs=dark'));
    });
  });

  group('ErrorScanner', () {
    test('mendeteksi meta hilang, img rusak/tanpa alt, dan membatasi sampel link',
        () async {
      final linksHtml = List.generate(
        20,
        (i) => '<a href="https://example.com/page-$i">Link $i</a>',
      ).join('\n');

      final html = '''
        <html>
          <head></head>
          <body>
            <img src="">
            <img src="https://example.com/logo.png">
            $linksHtml
          </body>
        </html>
      ''';

      int linkRequests = 0;
      final mockClient = MockClient((request) async {
        linkRequests++;
        if (request.url.path == '/page-0') {
          return http.Response('', 404);
        }
        return http.Response('', 200);
      });

      final scanner = ErrorScanner(client: mockClient, maxLinksToCheck: 12);
      final result = await scanner.scan(
        FetchResult(
          requestedUrl: 'https://example.com',
          finalUrl: 'https://example.com',
          statusCode: 200,
          latencyMs: 120,
          headers: const {},
          setCookieHeaders: const [],
          body: html,
          redirectCount: 0,
        ),
      );

      expect(result.checkedLinksCount, 12);
      expect(linkRequests, 12);
      expect(
        result.findings.any((f) => f.title.contains('<title>')),
        isTrue,
      );
      expect(
        result.findings.any((f) => f.title.contains('viewport')),
        isTrue,
      );
      expect(
        result.findings.any((f) => f.title.contains('404')),
        isTrue,
      );
    });
  });

  group('SecurityScanner', () {
    test('mendeteksi HTTP, header hilang, form http, dan cookie tidak aman',
        () {
      const html = '''
        <html>
          <body>
            <form action="http://example.com/login" method="post"></form>
          </body>
        </html>
      ''';

      final scanner = SecurityScanner();
      final findings = scanner.scan(
        const FetchResult(
          requestedUrl: 'http://example.com',
          finalUrl: 'http://example.com',
          statusCode: 200,
          latencyMs: 90,
          headers: {},
          setCookieHeaders: ['sid=xyz; Path=/'],
          body: html,
          redirectCount: 0,
        ),
      );

      expect(
        findings.any((f) => f.severity == FindingSeverity.critical),
        isTrue,
      );
      expect(
        findings.any((f) => f.category == 'Header'),
        isTrue,
      );
      expect(
        findings.any((f) => f.category == 'Form'),
        isTrue,
      );
      expect(
        findings.any((f) => f.category == 'Cookie'),
        isTrue,
      );
    });
  });

  group('AiSlopAnalyzer', () {
    test('memberikan skor tinggi pada teks penuh klise dan placeholder', () {
      const slopHtml = '''
        <html>
          <body>
            <main>
              <h1>1. Panduan Lengkap Masa Depan</h1>
              <h2>1. Membuka Potensi Penuh</h2>
              <h2>2. Solusi Inovatif</h2>
              <h2>3. Mengubah Permainan</h2>
              <h2>4. Kesimpulannya</h2>
              <p>
                Di era digital yang serba cepat, tidak dapat dipungkiri bahwa
                teknologi ini merupakan solusi inovatif dan game-changer yang
                membawa pengalaman yang mulus tanpa hambatan.
              </p>
              <p>
                Moreover, it is important to note that we must delve into this
                comprehensive guide to unlock the power of seamless innovation.
                Lorem ipsum dolor sit amet, [insert company name] TODO.
              </p>
            </main>
          </body>
        </html>
      ''';

      final analyzer = AiSlopAnalyzer();
      final result = analyzer.analyze(slopHtml);

      expect(result.score, greaterThanOrEqualTo(40));
      expect(result.indicators, isNotEmpty);
    });
  });

  group('AuditOrchestrator & AuditReport', () {
    test('menjalankan audit lengkap dan mendukung serialisasi JSON & Markdown',
        () async {
      const pageHtml = '''
        <!doctype html>
        <html>
          <head>
            <title>Situs Resmi Contoh</title>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
          </head>
          <body>
            <main>
              <p>
                Catatan rilis versi dua mencakup perbaikan memori pada modul
                jaringan serta penambahan uji regresi otomatis untuk parser URL.
              </p>
            </main>
          </body>
        </html>
      ''';

      final mockClient = MockClient((request) async {
        return http.Response(
          pageHtml,
          200,
          headers: {
            'strict-transport-security': 'max-age=31536000',
            'content-security-policy': "default-src 'self'",
            'x-frame-options': 'DENY',
            'x-content-type-options': 'nosniff',
            'referrer-policy': 'strict-origin-when-cross-origin',
          },
        );
      });

      final orchestrator = AuditOrchestrator(
        httpFetcher: HttpFetcher(client: mockClient),
        errorScanner: ErrorScanner(client: mockClient),
      );

      final report = await orchestrator.runAudit('example.com');
      expect(report.finalUrl, 'https://example.com');
      expect(report.statusCode, 200);
      expect(report.pageTitle, 'Situs Resmi Contoh');

      final roundTrip = AuditReport.fromJsonString(report.toJsonString());
      expect(roundTrip.finalUrl, report.finalUrl);
      expect(roundTrip.aiSlopResult.score, report.aiSlopResult.score);
      expect(report.toMarkdown(), contains('# Laporan Audit Web Auditor'));
    });
  });
}
