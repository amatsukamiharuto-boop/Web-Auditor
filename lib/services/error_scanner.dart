import 'dart:async';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/audit_report.dart';
import 'http_fetcher.dart';

class LinkCheckResult {
  final String url;
  final int? statusCode;
  final String? errorMessage;

  const LinkCheckResult({
    required this.url,
    this.statusCode,
    this.errorMessage,
  });

  bool get isBroken =>
      errorMessage != null || (statusCode != null && statusCode! >= 400);
}

class ErrorScanOutput {
  final List<AuditFinding> findings;
  final String? pageTitle;
  final int checkedLinksCount;

  const ErrorScanOutput({
    required this.findings,
    required this.pageTitle,
    required this.checkedLinksCount,
  });
}

class ErrorScanner {
  static const int defaultMaxLinks = 12;
  static const Duration linkTimeout = Duration(seconds: 8);
  static const int _batchSize = 4;

  final http.Client _client;
  final bool _ownsClient;
  final int maxLinksToCheck;

  ErrorScanner({
    http.Client? client,
    this.maxLinksToCheck = defaultMaxLinks,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  Future<ErrorScanOutput> scan(FetchResult fetchResult) async {
    final findings = <AuditFinding>[];

    _checkMainHttpStatus(fetchResult.statusCode, fetchResult.finalUrl, findings);

    final document = html_parser.parse(fetchResult.body);
    final pageTitle = _checkMetaAndTitle(document, findings);
    _checkImages(document, findings);

    final baseUri = Uri.tryParse(fetchResult.finalUrl) ??
        Uri.parse(fetchResult.requestedUrl);
    final sampleLinks = _extractSampleLinks(document, baseUri);

    if (sampleLinks.isNotEmpty) {
      final linkResults = await _checkLinksInBatches(sampleLinks);
      for (final result in linkResults) {
        if (!result.isBroken) continue;
        final isServerOrNetwork =
            result.errorMessage != null || (result.statusCode ?? 0) >= 500;
        findings.add(
          AuditFinding(
            title: result.statusCode != null
                ? 'Tautan Rusak (HTTP ${result.statusCode})'
                : 'Tautan Tidak Dapat Diakses',
            description: result.errorMessage ??
                'Tautan sampel mengembalikan kode status HTTP ${result.statusCode}.',
            severity: isServerOrNetwork
                ? FindingSeverity.high
                : FindingSeverity.medium,
            category: 'Tautan',
            target: result.url,
            recommendation:
                'Perbarui atau hapus tautan yang tidak lagi valid atau gagal dimuat.',
          ),
        );
      }
    }

    if (findings.isEmpty) {
      findings.add(
        AuditFinding(
          title: 'Halaman & Sampel Tautan Sehat',
          description:
              'Halaman merespons normal (HTTP ${fetchResult.statusCode}), tag dasar lengkap, dan ${sampleLinks.length} tautan sampel dapat diakses.',
          severity: FindingSeverity.info,
          category: 'Umum',
        ),
      );
    }

    return ErrorScanOutput(
      findings: findings,
      pageTitle: pageTitle,
      checkedLinksCount: sampleLinks.length,
    );
  }

  void _checkMainHttpStatus(
    int statusCode,
    String url,
    List<AuditFinding> findings,
  ) {
    if (statusCode >= 500) {
      findings.add(
        AuditFinding(
          title: 'Kesalahan Server (HTTP $statusCode)',
          description:
              'Server gagal memproses permintaan dan mengembalikan status error 5xx.',
          severity: FindingSeverity.critical,
          category: 'HTTP',
          target: url,
          recommendation:
              'Periksa log backend dan kesehatan layanan server Anda.',
        ),
      );
    } else if (statusCode >= 400) {
      findings.add(
        AuditFinding(
          title: 'Halaman Error (HTTP $statusCode)',
          description:
              'Halaman tidak dapat dimuat dengan benar dan mengembalikan status klien 4xx.',
          severity: FindingSeverity.high,
          category: 'HTTP',
          target: url,
          recommendation:
              'Pastikan URL benar, halaman tersedia, dan izin akses sudah sesuai.',
        ),
      );
    } else if (statusCode >= 300) {
      findings.add(
        AuditFinding(
          title: 'Redirect Belum Selesai (HTTP $statusCode)',
          description:
              'Halaman masih mengembalikan status pengalihan setelah batas redirect maksimal tercapai.',
          severity: FindingSeverity.medium,
          category: 'HTTP',
          target: url,
          recommendation:
              'Periksa konfigurasi redirect agar tidak terjadi rantai redirect panjang atau loop.',
        ),
      );
    }
  }

  String? _checkMetaAndTitle(
    dom.Document document,
    List<AuditFinding> findings,
  ) {
    final titleElement = document.querySelector('title');
    final titleText = titleElement?.text.trim();

    if (titleText == null || titleText.isEmpty) {
      findings.add(
        const AuditFinding(
          title: 'Tag <title> Hilang atau Kosong',
          description:
              'Dokumen HTML tidak memiliki elemen <title> yang terisi.',
          severity: FindingSeverity.medium,
          category: 'Meta',
          recommendation:
              'Tambahkan tag <title> yang deskriptif di dalam <head> untuk SEO dan aksesibilitas.',
        ),
      );
    }

    final hasViewport = document.querySelectorAll('meta').any((meta) {
      final name = meta.attributes['name']?.trim().toLowerCase();
      final content = meta.attributes['content']?.trim();
      return name == 'viewport' && content != null && content.isNotEmpty;
    });

    if (!hasViewport) {
      findings.add(
        const AuditFinding(
          title: 'Tag <meta name="viewport"> Tidak Ditemukan',
          description:
              'Halaman belum mendefinisikan meta viewport sehingga tampilan di perangkat mobile berisiko tidak responsif.',
          severity: FindingSeverity.medium,
          category: 'Meta',
          recommendation:
              'Tambahkan <meta name="viewport" content="width=device-width, initial-scale=1.0"> di <head>.',
        ),
      );
    }

    return (titleText != null && titleText.isNotEmpty) ? titleText : null;
  }

  void _checkImages(dom.Document document, List<AuditFinding> findings) {
    final images = document.querySelectorAll('img');
    if (images.isEmpty) return;

    final invalidSrcExamples = <String>[];
    int missingSrcCount = 0;
    final missingAltExamples = <String>[];
    int missingAltCount = 0;

    for (final img in images) {
      final src = (img.attributes['src'] ?? img.attributes['data-src'])?.trim();
      final isInvalidSrc = src == null ||
          src.isEmpty ||
          src == '#' ||
          src.toLowerCase().startsWith('javascript:') ||
          Uri.tryParse(src) == null;

      if (isInvalidSrc) {
        missingSrcCount++;
        if (invalidSrcExamples.length < 3) {
          invalidSrcExamples.add(src == null || src.isEmpty ? '(kosong)' : src);
        }
      }

      final alt = img.attributes['alt']?.trim();
      if (alt == null || alt.isEmpty) {
        missingAltCount++;
        if (missingAltExamples.length < 3) {
          missingAltExamples.add(src ?? '(tanpa src)');
        }
      }
    }

    if (missingSrcCount > 0) {
      findings.add(
        AuditFinding(
          title: '$missingSrcCount Gambar Tanpa Sumber (src) Valid',
          description:
              'Ditemukan elemen <img> yang tidak memiliki atribut src valid sehingga gagal ditampilkan.',
          severity: FindingSeverity.medium,
          category: 'Gambar',
          target: invalidSrcExamples.join(', '),
          recommendation:
              'Pastikan seluruh elemen <img> memiliki atribut src atau URL gambar yang valid.',
        ),
      );
    }

    if (missingAltCount > 0) {
      findings.add(
        AuditFinding(
          title: '$missingAltCount Gambar Tanpa Atribut alt',
          description:
              'Ditemukan elemen <img> yang tidak memiliki teks alternatif (alt) untuk aksesibilitas dan fallback.',
          severity: FindingSeverity.low,
          category: 'Gambar',
          target: missingAltExamples.join(', '),
          recommendation:
              'Tambahkan deskripsi singkat pada atribut alt (atau alt="" khusus untuk gambar dekoratif).',
        ),
      );
    }
  }

  List<Uri> _extractSampleLinks(dom.Document document, Uri baseUri) {
    final seen = <String>{};
    final result = <Uri>[];

    for (final anchor in document.querySelectorAll('a[href]')) {
      final rawHref = anchor.attributes['href']?.trim();
      if (rawHref == null || rawHref.isEmpty) continue;

      final lower = rawHref.toLowerCase();
      if (lower.startsWith('#') ||
          lower.startsWith('mailto:') ||
          lower.startsWith('tel:') ||
          lower.startsWith('sms:') ||
          lower.startsWith('javascript:') ||
          lower.startsWith('data:')) {
        continue;
      }

      Uri? resolved;
      try {
        resolved = baseUri.resolve(rawHref);
      } catch (_) {
        continue;
      }

      if ((resolved.scheme != 'http' && resolved.scheme != 'https') ||
          resolved.host.isEmpty) {
        continue;
      }

      final cleanUri = resolved.removeFragment();
      final key = cleanUri.toString();
      if (seen.add(key)) {
        result.add(cleanUri);
        if (result.length >= maxLinksToCheck) {
          break;
        }
      }
    }

    return result;
  }

  Future<List<LinkCheckResult>> _checkLinksInBatches(List<Uri> links) async {
    final results = <LinkCheckResult>[];
    for (var i = 0; i < links.length; i += _batchSize) {
      final end =
          (i + _batchSize < links.length) ? i + _batchSize : links.length;
      final batch = links.sublist(i, end);
      final batchResults = await Future.wait(batch.map(_checkSingleLink));
      results.addAll(batchResults);
    }
    return results;
  }

  Future<LinkCheckResult> _checkSingleLink(Uri uri) async {
    try {
      final headStatus = await _sendLinkRequest('HEAD', uri);
      if (headStatus == 405 || headStatus == 501) {
        final getStatus = await _sendLinkRequest('GET', uri);
        return LinkCheckResult(url: uri.toString(), statusCode: getStatus);
      }
      return LinkCheckResult(url: uri.toString(), statusCode: headStatus);
    } on TimeoutException {
      return LinkCheckResult(
        url: uri.toString(),
        errorMessage: 'Koneksi timeout saat memeriksa tautan.',
      );
    } on HandshakeException {
      return LinkCheckResult(
        url: uri.toString(),
        errorMessage: 'Sertifikat SSL/TLS tautan tidak valid.',
      );
    } on SocketException {
      return LinkCheckResult(
        url: uri.toString(),
        errorMessage: 'Domain atau server tautan tidak dapat dijangkau.',
      );
    } on http.ClientException catch (e) {
      return LinkCheckResult(
        url: uri.toString(),
        errorMessage: 'Gagal memeriksa tautan (${e.message}).',
      );
    } catch (_) {
      return LinkCheckResult(
        url: uri.toString(),
        errorMessage: 'Tautan gagal dimuat.',
      );
    }
  }

  Future<int> _sendLinkRequest(String method, Uri uri) async {
    final request = http.Request(method, uri)
      ..followRedirects = true
      ..maxRedirects = 3
      ..headers['User-Agent'] = 'WebAuditor/1.0 (Android Client)';

    final response = await _client.send(request).timeout(linkTimeout);
    // Cancel/drain stream promptly to avoid downloading large payloads.
    await response.stream.drain<void>().timeout(const Duration(seconds: 3));
    return response.statusCode;
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
