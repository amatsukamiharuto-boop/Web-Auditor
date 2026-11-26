import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/audit_report.dart';

class ReportScreen extends StatelessWidget {
  final AuditReport report;

  const ReportScreen({
    super.key,
    required this.report,
  });

  Future<void> _copyReport(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: report.toMarkdown()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Laporan Markdown disalin ke clipboard.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Hasil Audit'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonalIcon(
                onPressed: () => _copyReport(context),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Salin Laporan'),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            _ReportHeader(report: report),
            Material(
              color: colorScheme.surface,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(
                    text: 'Error & Tautan (${report.errorIssueCount})',
                  ),
                  Tab(
                    text: 'Keamanan Dasar (${report.securityIssueCount})',
                  ),
                  Tab(
                    text: 'Indikasi AI Slop (${report.aiSlopResult.score})',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                children: [
                  _FindingsTab(
                    findings: report.errorFindings,
                    emptyMessage:
                        'Tidak ada temuan error halaman atau tautan rusak.',
                  ),
                  _FindingsTab(
                    findings: report.securityFindings,
                    emptyMessage:
                        'Tidak ada temuan keamanan dasar pada pemeriksaan pasif.',
                  ),
                  _AiSlopTab(result: report.aiSlopResult),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportHeader extends StatelessWidget {
  final AuditReport report;

  const _ReportHeader({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusOk = report.statusCode >= 200 && report.statusCode < 400;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report.pageTitle != null && report.pageTitle!.isNotEmpty) ...[
            Text(
              report.pageTitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
          ],
          SelectableText(
            report.finalUrl,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (report.finalUrl != report.url) ...[
            const SizedBox(height: 2),
            Text(
              'Dari: ${report.url}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _InfoChip(
                icon: statusOk
                    ? Icons.check_circle_outline_rounded
                    : Icons.warning_amber_rounded,
                label: 'HTTP ${report.statusCode}',
                background: statusOk
                    ? colorScheme.primaryContainer
                    : colorScheme.errorContainer,
                foreground: statusOk
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onErrorContainer,
              ),
              _InfoChip(
                icon: Icons.speed_rounded,
                label: '${report.latencyMs} ms',
                background: colorScheme.surfaceContainerHighest,
                foreground: colorScheme.onSurfaceVariant,
              ),
              _InfoChip(
                icon: Icons.link_rounded,
                label: '${report.checkedLinksCount} tautan dicek',
                background: colorScheme.surfaceContainerHighest,
                foreground: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _FindingsTab extends StatelessWidget {
  final List<AuditFinding> findings;
  final String emptyMessage;

  const _FindingsTab({
    required this.findings,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (findings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: findings.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _FindingCard(finding: findings[index]);
      },
    );
  }
}

class _FindingCard extends StatelessWidget {
  final AuditFinding finding;

  const _FindingCard({required this.finding});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final palette = _severityPalette(finding.severity, colorScheme);

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: palette.background,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    finding.severity.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: palette.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    finding.category,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              finding.title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              finding.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (finding.target != null && finding.target!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  finding.target!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
            if (finding.recommendation != null &&
                finding.recommendation!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      finding.recommendation!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  _SeverityPalette _severityPalette(
    FindingSeverity severity,
    ColorScheme scheme,
  ) {
    switch (severity) {
      case FindingSeverity.critical:
      case FindingSeverity.high:
        return _SeverityPalette(
          background: scheme.errorContainer,
          foreground: scheme.onErrorContainer,
        );
      case FindingSeverity.medium:
        return _SeverityPalette(
          background: scheme.tertiaryContainer,
          foreground: scheme.onTertiaryContainer,
        );
      case FindingSeverity.low:
        return _SeverityPalette(
          background: scheme.secondaryContainer,
          foreground: scheme.onSecondaryContainer,
        );
      case FindingSeverity.info:
        return _SeverityPalette(
          background: scheme.primaryContainer,
          foreground: scheme.onPrimaryContainer,
        );
    }
  }
}

class _SeverityPalette {
  final Color background;
  final Color foreground;

  const _SeverityPalette({
    required this.background,
    required this.foreground,
  });
}

class _AiSlopTab extends StatelessWidget {
  final AiSlopResult result;

  const _AiSlopTab({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final Color scoreColor;
    if (result.score >= 60) {
      scoreColor = colorScheme.error;
    } else if (result.score >= 30) {
      scoreColor = colorScheme.tertiary;
    } else {
      scoreColor = colorScheme.primary;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Skor Indikasi AI Slop',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${result.score}/100',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: scoreColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: result.score / 100,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(6),
                  color: scoreColor,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    result.levelLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  result.summary,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _InfoChip(
                      icon: Icons.article_outlined,
                      label: '${result.wordCount} kata terbaca',
                      background: colorScheme.surfaceContainerHighest,
                      foreground: colorScheme.onSurfaceVariant,
                    ),
                    _InfoChip(
                      icon: Icons.pie_chart_outline_rounded,
                      label:
                          'Substantif ${(result.substantiveRatio * 100).toStringAsFixed(0)}%',
                      background: colorScheme.surfaceContainerHighest,
                      foreground: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Indikator Terdeteksi (${result.indicators.length})',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (result.indicators.isEmpty)
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Tidak ditemukan sinyal AI Slop yang signifikan pada halaman ini.',
              ),
            ),
          )
        else
          ...result.indicators.map(
            (indicator) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              indicator.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '+${indicator.scoreContribution}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onTertiaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        indicator.detail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (indicator.examples.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: indicator.examples
                              .map(
                                (ex) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    ex,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
