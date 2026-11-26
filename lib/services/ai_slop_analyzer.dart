import 'dart:math' as math;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/audit_report.dart';

class AiSlopAnalyzer {
  static const List<String> _clichePhrases = [
    // English AI clichés
    'delve into',
    'in today\'s fast-paced world',
    'fast-paced digital world',
    'ever-evolving landscape',
    'game-changer',
    'game changer',
    'tapestry',
    'testament to',
    'unlock the power',
    'unlock your potential',
    'elevate your',
    'seamless experience',
    'cutting-edge solution',
    'revolutionize',
    'comprehensive guide',
    'navigating the complexities',
    'it\'s important to note',
    'it is important to note',
    'in conclusion',
    'moreover',
    'furthermore',
    'foster innovation',
    'leverage the power',
    'unleash the power',
    'without further ado',
    'whether you\'re a beginner or',
    'bridge the gap',
    'embark on a journey',
    // Indonesian AI clichés
    'di era digital yang serba cepat',
    'tidak dapat dipungkiri',
    'tak dapat dipungkiri',
    'membuka potensi penuh',
    'solusi inovatif',
    'mengubah permainan',
    'lanskap yang terus berkembang',
    'panduan lengkap',
    'selangkah lebih maju',
    'pengalaman yang mulus',
    'tanpa hambatan',
    'tak tertandingi',
    'dirancang khusus untuk',
    'secara keseluruhan',
    'pada akhirnya',
    'kesimpulannya',
    'lebih lanjut',
    'selain itu',
    'penting untuk dicatat',
    'mari kita selami',
    'tingkatkan produktivitas anda',
  ];

  static final List<_PlaceholderRule> _placeholderRules = [
    _PlaceholderRule('Lorem ipsum', RegExp(r'\blorem\s+ipsum\b', caseSensitive: false)),
    _PlaceholderRule('Dolor sit amet', RegExp(r'\bdolor\s+sit\s+amet\b', caseSensitive: false)),
    _PlaceholderRule('TODO / FIXME', RegExp(r'\b(todo|fixme|tbd)\b', caseSensitive: false)),
    _PlaceholderRule('Template [insert ...]', RegExp(r'\[(insert|your|masukkan|nama|isi)[^\]]{1,40}\]', caseSensitive: false)),
    _PlaceholderRule('Variabel {{...}}', RegExp(r'\{\{[^}]{1,40}\}\}')),
    _PlaceholderRule('Coming soon', RegExp(r'\bcoming\s+soon\b', caseSensitive: false)),
  ];

  AiSlopResult analyze(String htmlBody) {
    final document = html_parser.parse(htmlBody);
    final totalVisibleText = _extractText(document.body, stripChrome: false);
    final substantiveText = _extractText(document.body, stripChrome: true);

    final totalWords = _tokenizeWords(totalVisibleText);
    final substantiveWords = _tokenizeWords(substantiveText);

    final analysisText =
        substantiveWords.length >= 20 ? substantiveText : totalVisibleText;
    final analysisWords =
        substantiveWords.length >= 20 ? substantiveWords : totalWords;

    final substantiveRatio = totalWords.isEmpty
        ? 0.0
        : (substantiveWords.length / totalWords.length).clamp(0.0, 1.0);

    final indicators = <AiSlopIndicator>[];
    int totalScore = 0;

    // 1. Placeholder detection (even on short pages)
    final placeholderResult = _evaluatePlaceholders(totalVisibleText);
    if (placeholderResult != null) {
      indicators.add(placeholderResult);
      totalScore += placeholderResult.scoreContribution;
    }

    if (analysisWords.length < 15) {
      final finalScore = totalScore.clamp(0, 100);
      return AiSlopResult(
        score: finalScore,
        summary: finalScore > 0
            ? 'Teks halaman sangat minim tetapi ditemukan indikasi teks placeholder.'
            : 'Konten teks terlalu sedikit (${analysisWords.length} kata) untuk menyimpulkan pola AI Slop secara mendalam.',
        indicators: indicators,
        wordCount: totalWords.length,
        substantiveRatio: substantiveRatio,
      );
    }

    // 2. Cliché & repetitive generic phrases (max 35)
    final clicheResult = _evaluateCliches(analysisText, analysisWords.length);
    if (clicheResult != null) {
      indicators.add(clicheResult);
      totalScore += clicheResult.scoreContribution;
    }

    // 3. Uniform sentence & heading patterns (max 25)
    final patternResult = _evaluateUniformPatterns(document, analysisText);
    if (patternResult != null) {
      indicators.add(patternResult);
      totalScore += patternResult.scoreContribution;
    }

    // 4. Substantive ratio & lexical diversity (max 15)
    final densityResult = _evaluateContentQuality(
      totalWords: totalWords,
      substantiveWords: substantiveWords,
      substantiveRatio: substantiveRatio,
    );
    if (densityResult != null) {
      indicators.add(densityResult);
      totalScore += densityResult.scoreContribution;
    }

    final clampedScore = totalScore.clamp(0, 100);
    final summary = _buildSummary(clampedScore, indicators);

    return AiSlopResult(
      score: clampedScore,
      summary: summary,
      indicators: indicators,
      wordCount: totalWords.length,
      substantiveRatio: substantiveRatio,
    );
  }

  AiSlopIndicator? _evaluatePlaceholders(String text) {
    final matchedLabels = <String>[];
    final examples = <String>[];
    int hitCount = 0;

    for (final rule in _placeholderRules) {
      final matches = rule.pattern.allMatches(text).toList();
      if (matches.isNotEmpty) {
        matchedLabels.add(rule.label);
        hitCount += matches.length;
        for (final m in matches.take(2)) {
          final snippet = m.group(0)?.trim();
          if (snippet != null &&
              snippet.isNotEmpty &&
              !examples.contains(snippet)) {
            examples.add(snippet);
          }
        }
      }
    }

    if (hitCount == 0) return null;

    final points = (10 + (hitCount * 4)).clamp(10, 25);
    return AiSlopIndicator(
      title: 'Teks Placeholder / Template Terdeteksi',
      detail:
          'Ditemukan $hitCount kemunculan placeholder (${matchedLabels.join(', ')}) yang menandakan konten belum selesai disunting.',
      scoreContribution: points,
      examples: examples.take(5).toList(),
    );
  }

  AiSlopIndicator? _evaluateCliches(String text, int wordCount) {
    final lower = text.toLowerCase();
    final matched = <String>[];
    int totalOccurrences = 0;

    for (final phrase in _clichePhrases) {
      final regex = RegExp(
        '(?<![a-z0-9])${RegExp.escape(phrase)}(?![a-z0-9])',
        caseSensitive: false,
      );
      final matches = regex.allMatches(lower).length;
      if (matches > 0) {
        matched.add(phrase);
        totalOccurrences += matches;
      }
    }

    if (matched.isEmpty) return null;

    final densityPer100 = (totalOccurrences / math.max(wordCount, 1)) * 100;
    final rawPoints = (matched.length * 4) +
        (totalOccurrences > matched.length ? 4 : 0) +
        (densityPer100 >= 1.5 ? 7 : (densityPer100 >= 0.7 ? 3 : 0));
    final points = rawPoints.clamp(4, 35);

    return AiSlopIndicator(
      title: 'Frasa Klise & Generik Berulang',
      detail:
          'Ditemukan ${matched.length} frasa klise khas generasi teks AI ($totalOccurrences total kemunculan).',
      scoreContribution: points,
      examples: matched.take(5).toList(),
    );
  }

  AiSlopIndicator? _evaluateUniformPatterns(
    dom.Document document,
    String text,
  ) {
    int points = 0;
    final reasons = <String>[];
    final examples = <String>[];

    final sentences = text
        .split(RegExp(r'[.!?]+'))
        .map((s) => s.trim())
        .where((s) => _tokenizeWords(s).length >= 4)
        .toList();

    if (sentences.length >= 6) {
      final lengths =
          sentences.map((s) => _tokenizeWords(s).length.toDouble()).toList();
      final mean = lengths.reduce((a, b) => a + b) / lengths.length;
      final variance = lengths
              .map((l) => math.pow(l - mean, 2))
              .reduce((a, b) => a + b) /
          lengths.length;
      final stdDev = math.sqrt(variance);
      final cv = mean > 0 ? stdDev / mean : 1.0;

      if (cv < 0.28) {
        points += 12;
        reasons.add(
          'variasi panjang kalimat sangat seragam (CV ${cv.toStringAsFixed(2)})',
        );
      } else if (cv < 0.36) {
        points += 6;
        reasons.add(
          'ritme panjang kalimat cenderung seragam (CV ${cv.toStringAsFixed(2)})',
        );
      }

      // Check repeated sentence openers
      final starterCounts = <String, int>{};
      for (final s in sentences) {
        final words = _tokenizeWords(s);
        if (words.length >= 2) {
          final opener = '${words[0]} ${words[1]}';
          starterCounts[opener] = (starterCounts[opener] ?? 0) + 1;
        }
      }
      final repeatedStarters = starterCounts.entries
          .where((e) => e.value >= 3)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      if (repeatedStarters.isNotEmpty) {
        points += 6;
        final top = repeatedStarters.first;
        reasons.add('pembuka kalimat berulang ("${top.key}" ${top.value}x)');
        examples.add('${top.key}... (${top.value}x)');
      }
    }

    // Check heading uniformity (h2 / h3)
    final headings = document
        .querySelectorAll('h2, h3')
        .map((h) => h.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (headings.length >= 4) {
      final numberedCount = headings
          .where((h) => RegExp(r'^\d+[\.\)]\s+').hasMatch(h))
          .length;
      final colonSplitCount =
          headings.where((h) => RegExp(r'^[^:]{3,40}:\s+\S+').hasMatch(h)).length;

      if (numberedCount >= headings.length * 0.6 ||
          colonSplitCount >= headings.length * 0.6) {
        points += 7;
        reasons.add('pola heading h2/h3 sangat seragam (${headings.length} heading)');
        examples.addAll(headings.take(2));
      }
    }

    if (points == 0) return null;

    return AiSlopIndicator(
      title: 'Pola Kalimat & Struktur Heading Seragam',
      detail: 'Terdeteksi ${reasons.join('; ')}.',
      scoreContribution: points.clamp(1, 25),
      examples: examples.take(4).toList(),
    );
  }

  AiSlopIndicator? _evaluateContentQuality({
    required List<String> totalWords,
    required List<String> substantiveWords,
    required double substantiveRatio,
  }) {
    int points = 0;
    final reasons = <String>[];

    if (totalWords.length >= 40 && substantiveRatio < 0.35) {
      points += 8;
      reasons.add(
        'rasio konten substantif rendah (${(substantiveRatio * 100).toStringAsFixed(0)}% dibanding boilerplate)',
      );
    }

    if (substantiveWords.length >= 60) {
      final uniqueWords = substantiveWords.toSet().length;
      final ttr = uniqueWords / substantiveWords.length;
      if (ttr < 0.34) {
        points += 7;
        reasons.add(
          'keragaman kosakata rendah (TTR ${(ttr * 100).toStringAsFixed(0)}%)',
        );
      }
    }

    if (points == 0) return null;

    return AiSlopIndicator(
      title: 'Rasio Konten Substantif & Keragaman Kata Rendah',
      detail: 'Terdeteksi ${reasons.join(' dan ')}.',
      scoreContribution: points.clamp(1, 15),
    );
  }

  String _buildSummary(int score, List<AiSlopIndicator> indicators) {
    if (score >= 60) {
      return 'Halaman menunjukkan indikasi AI Slop yang kuat (${indicators.length} indikator terdeteksi). Disarankan meninjau ulang orisinalitas dan penyuntingan konten.';
    }
    if (score >= 30) {
      return 'Halaman memiliki indikasi sedang pola penulisan generik atau template. Sebagian bagian masih dapat ditingkatkan agar lebih spesifik.';
    }
    if (indicators.isEmpty) {
      return 'Tidak ditemukan indikasi kuat AI Slop. Struktur kalimat, variasi kata, dan konten tampak natural.';
    }
    return 'Indikasi AI Slop rendah. Hanya ditemukan sedikit sinyal ringan yang belum cukup menyimpulkan konten generik.';
  }

  String _extractText(dom.Element? root, {required bool stripChrome}) {
    if (root == null) return '';
    final cloned = root.clone(true);
    const alwaysIgnored = ['script', 'style', 'noscript', 'svg', 'template'];
    const chromeTags = ['nav', 'header', 'footer', 'aside'];

    final selector = stripChrome
        ? [...alwaysIgnored, ...chromeTags].join(', ')
        : alwaysIgnored.join(', ');

    for (final el in cloned.querySelectorAll(selector)) {
      el.remove();
    }

    return cloned.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<String> _tokenizeWords(String text) {
    return RegExp(r"[a-zA-Z0-9\u00C0-\u024F']+")
        .allMatches(text.toLowerCase())
        .map((m) => m.group(0)!)
        .where((w) => w.isNotEmpty)
        .toList();
  }
}

class _PlaceholderRule {
  final String label;
  final RegExp pattern;

  const _PlaceholderRule(this.label, this.pattern);
}
