import 'package:html/parser.dart' as html_parser;

import '../models/audit_report.dart';
import 'http_fetcher.dart';

class SecurityScanner {
  List<AuditFinding> scan(FetchResult fetchResult) {
    final findings = <AuditFinding>[];
    final finalUri = Uri.tryParse(fetchResult.finalUrl) ??
        Uri.parse(fetchResult.requestedUrl);
    final isHttps = finalUri.scheme.toLowerCase() == 'https';

    _checkHttps(fetchResult, isHttps, findings);
    _checkSecurityHeaders(fetchResult.headers, isHttps, findings);
    _checkInsecureForms(fetchResult.body, finalUri, isHttps, findings);
    _checkSetCookieAttributes(fetchResult.setCookieHeaders, isHttps, findings);

    return findings;
  }

  void _checkHttps(
    FetchResult fetchResult,
    bool isHttps,
    List<AuditFinding> findings,
  ) {
    if (!isHttps) {
      findings.add(
        AuditFinding(
          title: 'Website Tidak Menggunakan HTTPS',
          description:
              'Halaman akhir diakses melalui HTTP tidak terenkripsi sehingga lalu lintas rentan disadap atau dimodifikasi.',
          severity: FindingSeverity.critical,
          category: 'Protokol',
          target: fetchResult.finalUrl,
          recommendation:
              'Pasang sertifikat SSL/TLS dan aktifkan pengalihan otomatis dari HTTP ke HTTPS.',
        ),
      );
    } else {
      findings.add(
        AuditFinding(
          title: 'Koneksi Terenkripsi HTTPS Aktif',
          description:
              'Halaman disajikan menggunakan protokol HTTPS.',
          severity: FindingSeverity.info,
          category: 'Protokol',
          target: fetchResult.finalUrl,
        ),
      );
    }
  }

  void _checkSecurityHeaders(
    Map<String, String> headers,
    bool isHttps,
    List<AuditFinding> findings,
  ) {
    final hsts = headers['strict-transport-security'];
    if (isHttps && (hsts == null || hsts.trim().isEmpty)) {
      findings.add(
        const AuditFinding(
          title: 'Header Strict-Transport-Security (HSTS) Tidak Ada',
          description:
              'Browser tidak dipaksa menggunakan HTTPS secara persisten sehingga berisiko terkena serangan SSL stripping.',
          severity: FindingSeverity.medium,
          category: 'Header',
          target: 'Strict-Transport-Security',
          recommendation:
              'Tambahkan header Strict-Transport-Security: max-age=31536000; includeSubDomains.',
        ),
      );
    }

    final csp = headers['content-security-policy'];
    if (csp == null || csp.trim().isEmpty) {
      findings.add(
        const AuditFinding(
          title: 'Header Content-Security-Policy (CSP) Tidak Ada',
          description:
              'Situs belum mendefinisikan kebijakan sumber daya untuk membantu memitigasi serangan XSS dan injeksi skrip.',
          severity: FindingSeverity.medium,
          category: 'Header',
          target: 'Content-Security-Policy',
          recommendation:
              'Terapkan header Content-Security-Policy sesuai kebutuhan aset dan skrip situs.',
        ),
      );
    }

    final xFrameOptions = headers['x-frame-options'];
    final hasFrameAncestors =
        csp != null && csp.toLowerCase().contains('frame-ancestors');
    if ((xFrameOptions == null || xFrameOptions.trim().isEmpty) &&
        !hasFrameAncestors) {
      findings.add(
        const AuditFinding(
          title: 'Proteksi Clickjacking Tidak Ditemukan',
          description:
              'Header X-Frame-Options maupun direktif CSP frame-ancestors tidak ditemukan, sehingga halaman berpotensi disematkan dalam iframe pihak lain.',
          severity: FindingSeverity.medium,
          category: 'Header',
          target: 'X-Frame-Options',
          recommendation:
              'Tambahkan X-Frame-Options: SAMEORIGIN (atau DENY) serta direktif CSP frame-ancestors.',
        ),
      );
    }

    final xContentType = headers['x-content-type-options']?.trim().toLowerCase();
    if (xContentType != 'nosniff') {
      findings.add(
        const AuditFinding(
          title: 'Header X-Content-Type-Options Tidak Bernilai nosniff',
          description:
              'Tanpa nosniff, browser dapat melakukan MIME-type sniffing pada aset yang berpotensi memicu eksekusi konten tak diinginkan.',
          severity: FindingSeverity.low,
          category: 'Header',
          target: 'X-Content-Type-Options',
          recommendation: 'Atur header X-Content-Type-Options: nosniff.',
        ),
      );
    }

    final referrerPolicy = headers['referrer-policy'];
    if (referrerPolicy == null || referrerPolicy.trim().isEmpty) {
      findings.add(
        const AuditFinding(
          title: 'Header Referrer-Policy Tidak Ada',
          description:
              'Kebijakan pengiriman informasi Referer ke situs eksternal belum diatur secara eksplisit.',
          severity: FindingSeverity.low,
          category: 'Header',
          target: 'Referrer-Policy',
          recommendation:
              'Tambahkan Referrer-Policy: strict-origin-when-cross-origin.',
        ),
      );
    }
  }

  void _checkInsecureForms(
    String htmlBody,
    Uri baseUri,
    bool isHttps,
    List<AuditFinding> findings,
  ) {
    final document = html_parser.parse(htmlBody);
    final forms = document.querySelectorAll('form');
    if (forms.isEmpty) return;

    final insecureTargets = <String>[];
    for (final form in forms) {
      final rawAction = form.attributes['action']?.trim();
      if (rawAction == null || rawAction.isEmpty || rawAction == '#') {
        if (!isHttps) {
          insecureTargets.add(baseUri.toString());
        }
        continue;
      }

      if (rawAction.toLowerCase().startsWith('http://')) {
        insecureTargets.add(rawAction);
        continue;
      }

      final resolved = Uri.tryParse(rawAction);
      if (resolved != null && !resolved.hasScheme && !isHttps) {
        insecureTargets.add(baseUri.resolve(rawAction).toString());
      }
    }

    if (insecureTargets.isNotEmpty) {
      findings.add(
        AuditFinding(
          title: '${insecureTargets.length} Form Mengarah ke Endpoint HTTP',
          description:
              'Ditemukan tag <form> yang mengirimkan data ke URL http:// tidak terenkripsi.',
          severity: FindingSeverity.high,
          category: 'Form',
          target: insecureTargets.take(3).join(', '),
          recommendation:
              'Ubah atribut action pada semua <form> agar menggunakan endpoint https://.',
        ),
      );
    }
  }

  void _checkSetCookieAttributes(
    List<String> setCookieHeaders,
    bool isHttps,
    List<AuditFinding> findings,
  ) {
    if (setCookieHeaders.isEmpty) {
      findings.add(
        const AuditFinding(
          title: 'Tidak Ada Header Set-Cookie pada Respons Awal',
          description:
              'Server tidak menetapkan cookie pada permintaan GET awal halaman ini.',
          severity: FindingSeverity.info,
          category: 'Cookie',
        ),
      );
      return;
    }

    for (final rawCookie in setCookieHeaders) {
      final segments = rawCookie.split(';').map((s) => s.trim()).toList();
      if (segments.isEmpty) continue;

      final cookieName = segments.first.split('=').first.trim();
      final displayName = cookieName.isEmpty ? '(cookie)' : cookieName;
      final attrs = segments.skip(1).map((s) => s.toLowerCase()).toList();

      final hasSecure = attrs.any((a) => a == 'secure');
      final hasHttpOnly = attrs.any((a) => a == 'httponly');
      final hasSameSite = attrs.any((a) => a.startsWith('samesite='));

      final missingAttrs = <String>[];
      if (!hasSecure) missingAttrs.add('Secure');
      if (!hasHttpOnly) missingAttrs.add('HttpOnly');
      if (!hasSameSite) missingAttrs.add('SameSite');

      if (missingAttrs.isEmpty) continue;

      final isHighRisk = !hasSecure && isHttps;
      findings.add(
        AuditFinding(
          title: 'Cookie "$displayName" Kekurangan Atribut Keamanan',
          description:
              'Atribut ${missingAttrs.join(', ')} tidak ditemukan pada Set-Cookie.',
          severity:
              isHighRisk ? FindingSeverity.medium : FindingSeverity.low,
          category: 'Cookie',
          target: displayName,
          recommendation:
              'Tambahkan atribut Secure, HttpOnly, dan SameSite (Lax/Strict) pada cookie sensitif.',
        ),
      );
    }
  }
}
