import 'package:shared_preferences/shared_preferences.dart';

import '../models/audit_report.dart';

class HistoryStorage {
  static const String _historyKey = 'web_auditor_history_v1';
  static const int maxHistoryItems = 20;

  Future<List<AuditReport>> loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_historyKey) ?? const [];
      final reports = <AuditReport>[];
      for (final raw in rawList) {
        try {
          reports.add(AuditReport.fromJsonString(raw));
        } catch (_) {
          // Skip malformed entries without failing entire history load.
        }
      }
      return reports;
    } catch (_) {
      return [];
    }
  }

  Future<List<AuditReport>> saveReport(AuditReport report) async {
    final existing = await loadHistory();
    final updated = <AuditReport>[
      report,
      ...existing.where(
        (item) =>
            !(item.url == report.url &&
                item.checkedAt.isAtSameMomentAs(report.checkedAt)),
      ),
    ].take(maxHistoryItems).toList();

    await _persistList(updated);
    return updated;
  }

  Future<List<AuditReport>> deleteAt(int index) async {
    final existing = await loadHistory();
    if (index < 0 || index >= existing.length) return existing;
    final updated = [...existing]..removeAt(index);
    await _persistList(updated);
    return updated;
  }

  Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyKey);
    } catch (_) {
      // Ignore storage error gracefully.
    }
  }

  Future<void> _persistList(List<AuditReport> reports) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = reports.map((r) => r.toJsonString()).toList();
      await prefs.setStringList(_historyKey, encoded);
    } catch (_) {
      // Ignore storage error gracefully.
    }
  }
}
