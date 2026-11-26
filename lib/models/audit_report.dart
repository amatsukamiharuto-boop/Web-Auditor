import 'dart:convert';

enum FindingSeverity {
  info,
  low,
  medium,
  high,
  critical;

  String get label {
    switch (this) {
      case FindingSeverity.info:
        return 'Info';
      case FindingSeverity.low:
        return 'Rendah';
      case FindingSeverity.medium:
        return 'Sedang';
      case FindingSeverity.high:
        return 'Tinggi';
      case FindingSeverity.critical:
        return 'Kritis';
    }
  }

  static FindingSeverity fromName(String? value) {
    return FindingSeverity.values.firstWhere(
      (e) => e.name == value,
      orElse: () => FindingSeverity.info,
    );
  }
}

class AuditFinding {
  final String title;
  final String description;
  final FindingSeverity severity;
  final String category;
  final String? target;
  final String? recommendation;

  const AuditFinding({
    required this.title,
    required this.description,
    required this.severity,
    required this.category,
    this.target,
    this.recommendation,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'severity': severity.name,
      'category': category,
      'target': target,
      'recommendation': recommendation,
    };
  }

  factory AuditFinding.fromJson(Map<String, dynamic> json) {
    return AuditFinding(
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      severity: FindingSeverity.fromName(json['severity'] as String?),
      category: json['category'] as String? ?? 'Umum',
      target: json['target'] as String?,
      recommendation: json['recommendation'] as String?,
    );
  }
}

class AiSlopIndicator {
  final String title;
  final String detail;
  final int scoreContribution;
  final List<String> examples;

  const AiSlopIndicator({
    required this.title,
    required this.detail,
    required this.scoreContribution,
    this.examples = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'detail': detail,
      'scoreContribution': scoreContribution,
      'examples': examples,
    };
  }

  factory AiSlopIndicator.fromJson(Map<String, dynamic> json) {
    final rawExamples = json['examples'] as List<dynamic>? ?? const [];
    return AiSlopIndicator(
      title: json['title'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      scoreContribution: (json['scoreContribution'] as num?)?.toInt() ?? 0,
      examples: rawExamples.map((e) => e.toString()).toList(),
    );
  }
}

class AiSlopResult {
  final int score;
  final String summary;
  final List<AiSlopIndicator> indicators;
  final int wordCount;
  final double substantiveRatio;

  const AiSlopResult({
    required this.score,
    required this.summary,
    required this.indicators,
    this.wordCount = 0,
    this.substantiveRatio = 0.0,
  });

  String get levelLabel {
    if (score >= 60) return 'Indikasi Tinggi';
    if (score >= 30) return 'Indikasi Sedang';
    return 'Indikasi Rendah';
  }

  Map<String, dynamic> toJson() {
    return {
      'score': score,
      'summary': summary,
      'indicators': indicators.map((e) => e.toJson()).toList(),
      'wordCount': wordCount,
      'substantiveRatio': substantiveRatio,
    };
  }

  factory AiSlopResult.fromJson(Map<String, dynamic> json) {
    final rawIndicators = json['indicators'] as List<dynamic>? ?? const [];
    return AiSlopResult(
      score: (json['score'] as num?)?.toInt().clamp(0, 100) ?? 0,
      summary: json['summary'] as String? ?? '',
      indicators: rawIndicators
          .whereType<Map<String, dynamic>>()
          .map(AiSlopIndicator.fromJson)
          .toList(),
      wordCount: (json['wordCount'] as num?)?.toInt() ?? 0,
      substantiveRatio: (json['substantiveRatio'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class AuditReport {
  final String url;
  final String finalUrl;
  final int statusCode;
  final int latencyMs;
  final String? pageTitle;
  final int checkedLinksCount;
  final List<AuditFinding> errorFindings;
  final List<AuditFinding> securityFindings;
  final AiSlopResult aiSlopResult;
  final DateTime checkedAt;

  const AuditReport({
    required this.url,
    required this.finalUrl,
    required this.statusCode,
    required this.latencyMs,
    this.pageTitle,
    this.checkedLinksCount = 0,
    required this.errorFindings,
    required this.securityFindings,
    required this.aiSlopResult,
    required this.checkedAt,
  });

  int get errorIssueCount =>
      errorFindings.where((f) => f.severity != FindingSeverity.info).length;

  int get securityIssueCount =>
      securityFindings.where((f) => f.severity != FindingSeverity.info).length;

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'finalUrl': finalUrl,
      'statusCode': statusCode,
      'latencyMs': latencyMs,
      'pageTitle': pageTitle,
      'checkedLinksCount': checkedLinksCount,
      'errorFindings': errorFindings.map((e) => e.toJson()).toList(),
      'securityFindings': securityFindings.map((e) => e.toJson()).toList(),
      'aiSlopResult': aiSlopResult.toJson(),
      'checkedAt': checkedAt.toIso8601String(),
    };
  }

  factory AuditReport.fromJson(Map<String, dynamic> json) {
    final rawErrors = json['errorFindings'] as List<dynamic>? ?? const [];
    final rawSecurity = json['securityFindings'] as List<dynamic>? ?? const [];
    final rawSlop = json['aiSlopResult'] as Map<String, dynamic>? ?? const {};

    return AuditReport(
      url: json['url'] as String? ?? '',
      finalUrl: json['finalUrl'] as String? ?? '',
      statusCode: (json['statusCode'] as num?)?.toInt() ?? 0,
      latencyMs: (json['latencyMs'] as num?)?.toInt() ?? 0,
      pageTitle: json['pageTitle'] as String?,
      checkedLinksCount: (json['checkedLinksCount'] as num?)?.toInt() ?? 0,
      errorFindings: rawErrors
          .whereType<Map<String, dynamic>>()
          .map(AuditFinding.fromJson)
          .toList(),
      securityFindings: rawSecurity
          .whereType<Map<String, dynamic>>()
          .map(AuditFinding.fromJson)
          .toList(),
      aiSlopResult: AiSlopResult.fromJson(rawSlop),
      checkedAt: DateTime.tryParse(json['checkedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  static AuditReport fromJsonString(String source) =>
      AuditReport.fromJson(jsonDecode(source) as Map<String, dynamic>);

  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln('# Laporan Audit Web Auditor');
    buffer.writeln();
    buffer.writeln('- **URL Input:** $url');
    if (finalUrl != url) {
      buffer.writeln('- **URL Akhir (Redirect):** $finalUrl');
    }
    if (pageTitle != null && pageTitle!.isNotEmpty) {
      buffer.writeln('- **Judul Halaman:** $pageTitle');
    }
    buffer.writeln('- **Status HTTP:** $statusCode');
    buffer.writeln('- **Latensi:** $latencyMs ms');
    buffer.writeln('- **Sampel Tautan Diperiksa:** $checkedLinksCount');
    buffer.writeln('- **Waktu Audit:** ${_formatDateTime(checkedAt)}');
    buffer.writeln();

    _appendFindingsSection(
      buffer,
      '## 1. Error & Tautan ($errorIssueCount temuan)',
      errorFindings,
    );
    _appendFindingsSection(
      buffer,
      '## 2. Keamanan Dasar ($securityIssueCount temuan)',
      securityFindings,
    );

    buffer.writeln(
      '## 3. Indikasi AI Slop (Skor: ${aiSlopResult.score}/100 - ${aiSlopResult.levelLabel})',
    );
    buffer.writeln();
    buffer.writeln(aiSlopResult.summary);
    buffer.writeln(
      '- **Jumlah Kata Terbaca:** ${aiSlopResult.wordCount}',
    );
    buffer.writeln(
      '- **Rasio Konten Substantif:** ${(aiSlopResult.substantiveRatio * 100).toStringAsFixed(0)}%',
    );
    if (aiSlopResult.indicators.isNotEmpty) {
      buffer.writeln();
      for (final indicator in aiSlopResult.indicators) {
        buffer.writeln(
          '- **${indicator.title}** (+${indicator.scoreContribution} poin): ${indicator.detail}',
        );
        if (indicator.examples.isNotEmpty) {
          buffer.writeln(
            '  - Contoh: ${indicator.examples.map((e) => '`$e`').join(', ')}',
          );
        }
      }
    }

    return buffer.toString().trim();
  }

  static void _appendFindingsSection(
    StringBuffer buffer,
    String heading,
    List<AuditFinding> findings,
  ) {
    buffer.writeln(heading);
    buffer.writeln();
    if (findings.isEmpty) {
      buffer.writeln('- Tidak ada temuan.');
      buffer.writeln();
      return;
    }
    for (final f in findings) {
      buffer.writeln('- **[${f.severity.label}] (${f.category}) ${f.title}**');
      buffer.writeln('  ${f.description}');
      if (f.target != null && f.target!.isNotEmpty) {
        buffer.writeln('  - Target: `${f.target}`');
      }
      if (f.recommendation != null && f.recommendation!.isNotEmpty) {
        buffer.writeln('  - Saran: ${f.recommendation}');
      }
    }
    buffer.writeln();
  }

  static String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}
