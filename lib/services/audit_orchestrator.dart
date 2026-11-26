import '../models/audit_report.dart';
import 'ai_slop_analyzer.dart';
import 'error_scanner.dart';
import 'http_fetcher.dart';
import 'security_scanner.dart';

class AuditProgress {
  final int step;
  final int totalSteps;
  final String message;

  const AuditProgress({
    required this.step,
    required this.totalSteps,
    required this.message,
  });

  double get fraction => totalSteps > 0 ? step / totalSteps : 0.0;
}

class AuditOrchestrator {
  final HttpFetcher _httpFetcher;
  final ErrorScanner _errorScanner;
  final SecurityScanner _securityScanner;
  final AiSlopAnalyzer _aiSlopAnalyzer;

  AuditOrchestrator({
    HttpFetcher? httpFetcher,
    ErrorScanner? errorScanner,
    SecurityScanner? securityScanner,
    AiSlopAnalyzer? aiSlopAnalyzer,
  })  : _httpFetcher = httpFetcher ?? HttpFetcher(),
        _errorScanner = errorScanner ?? ErrorScanner(),
        _securityScanner = securityScanner ?? SecurityScanner(),
        _aiSlopAnalyzer = aiSlopAnalyzer ?? AiSlopAnalyzer();

  Future<AuditReport> runAudit(
    String rawUrl, {
    void Function(AuditProgress progress)? onProgress,
  }) async {
    const totalSteps = 4;

    onProgress?.call(
      const AuditProgress(
        step: 1,
        totalSteps: totalSteps,
        message: 'Mengambil halaman website...',
      ),
    );
    final fetchResult = await _httpFetcher.fetch(rawUrl);

    onProgress?.call(
      const AuditProgress(
        step: 2,
        totalSteps: totalSteps,
        message: 'Memeriksa error halaman & sampel tautan...',
      ),
    );
    final errorOutput = await _errorScanner.scan(fetchResult);

    onProgress?.call(
      const AuditProgress(
        step: 3,
        totalSteps: totalSteps,
        message: 'Memeriksa keamanan dasar (HTTPS, header, cookie)...',
      ),
    );
    final securityFindings = _securityScanner.scan(fetchResult);

    onProgress?.call(
      const AuditProgress(
        step: 4,
        totalSteps: totalSteps,
        message: 'Menganalisis indikasi AI Slop...',
      ),
    );
    final aiSlopResult = _aiSlopAnalyzer.analyze(fetchResult.body);

    return AuditReport(
      url: fetchResult.requestedUrl,
      finalUrl: fetchResult.finalUrl,
      statusCode: fetchResult.statusCode,
      latencyMs: fetchResult.latencyMs,
      pageTitle: errorOutput.pageTitle,
      checkedLinksCount: errorOutput.checkedLinksCount,
      errorFindings: errorOutput.findings,
      securityFindings: securityFindings,
      aiSlopResult: aiSlopResult,
      checkedAt: DateTime.now(),
    );
  }

  void dispose() {
    _httpFetcher.dispose();
    _errorScanner.dispose();
  }
}
