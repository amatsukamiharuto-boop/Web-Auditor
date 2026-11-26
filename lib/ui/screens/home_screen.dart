import 'package:material_ui/material_ui.dart';

import '../../models/audit_report.dart';
import '../../services/audit_orchestrator.dart';
import '../../services/history_storage.dart';
import '../../services/http_fetcher.dart';
import 'report_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _urlController = TextEditingController();
  final AuditOrchestrator _orchestrator = AuditOrchestrator();
  final HistoryStorage _historyStorage = HistoryStorage();

  List<AuditReport> _history = const [];
  bool _isLoadingHistory = true;
  bool _isAuditing = false;
  AuditProgress? _progress;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _orchestrator.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final items = await _historyStorage.loadHistory();
    if (!mounted) return;
    setState(() {
      _history = items;
      _isLoadingHistory = false;
    });
  }

  Future<void> _startAudit() async {
    if (_isAuditing) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isAuditing = true;
      _errorMessage = null;
      _progress = const AuditProgress(
        step: 1,
        totalSteps: 4,
        message: 'Memvalidasi URL...',
      );
    });

    try {
      final report = await _orchestrator.runAudit(
        _urlController.text,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _progress = progress;
          });
        },
      );

      final updatedHistory = await _historyStorage.saveReport(report);
      if (!mounted) return;

      setState(() {
        _history = updatedHistory;
        _isAuditing = false;
        _progress = null;
      });

      _openReport(report);
    } on FetchException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isAuditing = false;
        _progress = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Gagal menjalankan audit. Periksa URL dan koneksi internet Anda.';
        _isAuditing = false;
        _progress = null;
      });
    }
  }

  void _openReport(AuditReport report) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportScreen(report: report),
      ),
    );
  }

  Future<void> _deleteHistoryItem(int index) async {
    final updated = await _historyStorage.deleteAt(index);
    if (!mounted) return;
    setState(() {
      _history = updated;
    });
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Semua Riwayat?'),
        content: const Text(
          'Seluruh riwayat hasil audit yang tersimpan di perangkat akan dihapus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _historyStorage.clearHistory();
      if (!mounted) return;
      setState(() {
        _history = const [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Web Auditor'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.travel_explore_rounded,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Audit Website Instan',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Cek error halaman & tautan, keamanan pasif, serta indikasi AI Slop langsung dari perangkat Anda.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _urlController,
                      enabled: !_isAuditing,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      autocorrect: false,
                      onSubmitted: (_) => _startAudit(),
                      onChanged: (_) {
                        if (_errorMessage != null) {
                          setState(() => _errorMessage = null);
                        } else {
                          setState(() {});
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'URL Website',
                        hintText: 'contoh: example.com atau https://example.com',
                        prefixIcon: const Icon(Icons.link_rounded),
                        suffixIcon: _urlController.text.isNotEmpty && !_isAuditing
                            ? IconButton(
                                tooltip: 'Bersihkan',
                                onPressed: () {
                                  _urlController.clear();
                                  setState(() => _errorMessage = null);
                                },
                                icon: const Icon(Icons.clear_rounded),
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 20,
                              color: colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_isAuditing && _progress != null) ...[
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: _progress!.fraction,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Langkah ${_progress!.step}/${_progress!.totalSteps}: ${_progress!.message}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _isAuditing ? null : _startAudit,
                      icon: _isAuditing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow_rounded),
                      label: Text(
                        _isAuditing ? 'Sedang Mengaudit...' : 'Mulai Audit',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Riwayat Audit',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_history.isNotEmpty)
                  TextButton.icon(
                    onPressed: _isAuditing ? null : _confirmClearHistory,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('Hapus Semua'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_isLoadingHistory)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_history.isEmpty)
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLowest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 36,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Belum ada riwayat audit',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Masukkan URL di atas lalu tekan Mulai Audit untuk melihat laporan pertama Anda.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...List.generate(_history.length, (index) {
                final item = _history[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _HistoryCard(
                    report: item,
                    onTap: () => _openReport(item),
                    onDelete: () => _deleteHistoryItem(index),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final AuditReport report;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _HistoryCard({
    required this.report,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusOk = report.statusCode >= 200 && report.statusCode < 400;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.pageTitle?.isNotEmpty == true
                          ? report.pageTitle!
                          : report.finalUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      report.finalUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _MiniTag(
                          label: 'HTTP ${report.statusCode}',
                          background: statusOk
                              ? colorScheme.primaryContainer
                              : colorScheme.errorContainer,
                          foreground: statusOk
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onErrorContainer,
                        ),
                        _MiniTag(
                          label: '${report.latencyMs} ms',
                          background: colorScheme.surfaceContainerHighest,
                          foreground: colorScheme.onSurfaceVariant,
                        ),
                        _MiniTag(
                          label: 'AI Slop ${report.aiSlopResult.score}/100',
                          background: colorScheme.secondaryContainer,
                          foreground: colorScheme.onSecondaryContainer,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatTimestamp(report.checkedAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Hapus riwayat',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _MiniTag extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _MiniTag({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
