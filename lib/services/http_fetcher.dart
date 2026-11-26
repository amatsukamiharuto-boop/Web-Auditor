import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class FetchException implements Exception {
  final String message;

  const FetchException(this.message);

  @override
  String toString() => message;
}

class FetchResult {
  final String requestedUrl;
  final String finalUrl;
  final int statusCode;
  final int latencyMs;
  final Map<String, String> headers;
  final List<String> setCookieHeaders;
  final String body;
  final int redirectCount;

  const FetchResult({
    required this.requestedUrl,
    required this.finalUrl,
    required this.statusCode,
    required this.latencyMs,
    required this.headers,
    required this.setCookieHeaders,
    required this.body,
    required this.redirectCount,
  });
}

class HttpFetcher {
  static const Duration defaultTimeout = Duration(seconds: 15);
  static const int maxRedirects = 5;
  static const String _userAgent = 'WebAuditor/1.0 (Android Client)';

  final http.Client _client;
  final bool _ownsClient;

  HttpFetcher({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  /// Normalizes user input into a valid HTTP/HTTPS [Uri].
  /// Automatically prepends `https://` when no scheme is provided.
  static Uri normalizeAndValidateUrl(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      throw const FetchException('Masukkan URL website terlebih dahulu.');
    }
    if (trimmed.contains(RegExp(r'\s'))) {
      throw const FetchException(
        'Format URL tidak valid: URL tidak boleh mengandung spasi.',
      );
    }

    final schemeMatch = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):\/\/').firstMatch(trimmed);
    final String normalized;
    if (schemeMatch == null) {
      if (trimmed.contains(':') &&
          RegExp(r'^(javascript|data|mailto|tel|ftp):', caseSensitive: false)
              .hasMatch(trimmed)) {
        throw const FetchException(
          'Skema URL tidak didukung. Gunakan protokol http:// atau https://.',
        );
      }
      normalized = 'https://$trimmed';
    } else {
      final scheme = schemeMatch.group(1)!.toLowerCase();
      if (scheme != 'http' && scheme != 'https') {
        throw const FetchException(
          'Skema URL tidak didukung. Gunakan protokol http:// atau https://.',
        );
      }
      normalized = trimmed;
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
      throw const FetchException(
        'Format URL tidak valid. Contoh yang benar: https://example.com',
      );
    }

    final host = uri.host;
    final isLocalhost = host.toLowerCase() == 'localhost';
    final hasDot = host.contains('.');
    final isIpv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host);
    if (!isLocalhost && !hasDot && !isIpv4) {
      throw const FetchException(
        'Nama domain tidak valid. Pastikan Anda memasukkan domain lengkap seperti example.com.',
      );
    }

    return uri;
  }

  Future<FetchResult> fetch(String rawUrl) async {
    final initialUri = normalizeAndValidateUrl(rawUrl);
    final stopwatch = Stopwatch()..start();

    Uri currentUri = initialUri;
    int redirectCount = 0;
    final collectedCookies = <String>[];

    try {
      while (true) {
        final request = http.Request('GET', currentUri)
          ..followRedirects = false
          ..headers.addAll({
            'User-Agent': _userAgent,
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7',
          });

        final streamedResponse = await _client.send(request).timeout(defaultTimeout);
        final normalizedHeaders = <String, String>{};
        streamedResponse.headers.forEach((key, value) {
          normalizedHeaders[key.toLowerCase()] = value;
        });

        final rawSetCookie = normalizedHeaders['set-cookie'];
        if (rawSetCookie != null && rawSetCookie.trim().isNotEmpty) {
          collectedCookies.addAll(splitSetCookieHeader(rawSetCookie));
        }

        final statusCode = streamedResponse.statusCode;
        final location = normalizedHeaders['location'];

        if (_isRedirectStatus(statusCode) &&
            location != null &&
            location.trim().isNotEmpty &&
            redirectCount < maxRedirects) {
          // Drain stream safely before following redirect.
          await streamedResponse.stream.drain<void>().timeout(defaultTimeout);
          final nextUri = currentUri.resolve(location.trim());
          if (nextUri.scheme != 'http' && nextUri.scheme != 'https') {
            throw const FetchException(
              'Situs mengalihkan ke protokol yang tidak didukung.',
            );
          }
          currentUri = nextUri;
          redirectCount++;
          continue;
        }

        final bytes = await streamedResponse.stream
            .toBytes()
            .timeout(defaultTimeout);
        stopwatch.stop();

        final body = utf8.decode(bytes, allowMalformed: true);
        return FetchResult(
          requestedUrl: initialUri.toString(),
          finalUrl: currentUri.toString(),
          statusCode: statusCode,
          latencyMs: stopwatch.elapsedMilliseconds,
          headers: normalizedHeaders,
          setCookieHeaders: collectedCookies,
          body: body,
          redirectCount: redirectCount,
        );
      }
    } on FetchException {
      rethrow;
    } on TimeoutException {
      throw const FetchException(
        'Permintaan habis waktu (timeout 15 detik). Server terlalu lama merespons.',
      );
    } on HandshakeException {
      throw const FetchException(
        'Koneksi SSL/TLS gagal. Sertifikat keamanan situs mungkin tidak valid atau kedaluwarsa.',
      );
    } on SocketException catch (e) {
      throw FetchException(
        'Gagal terhubung ke server (${e.osError?.message ?? 'koneksi terputus'}). '
        'Periksa koneksi internet atau alamat domain.',
      );
    } on http.ClientException catch (e) {
      throw FetchException(
        'Gagal memuat halaman dari server: ${e.message}.',
      );
    } on FormatException {
      throw const FetchException(
        'Respons atau format URL dari server tidak dapat diproses.',
      );
    } catch (_) {
      throw const FetchException(
        'Terjadi kesalahan tak terduga saat mengakses website.',
      );
    }
  }

  /// Splits concatenated `Set-Cookie` header values while preserving commas inside `Expires=`.
  static List<String> splitSetCookieHeader(String rawHeader) {
    final parts = rawHeader.split(RegExp(r',\s*(?=[^;,=\s]+=)'));
    return parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  }

  static bool _isRedirectStatus(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
