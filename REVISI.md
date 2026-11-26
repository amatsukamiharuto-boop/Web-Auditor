# Dokumen Revisi & Backlog — Web Auditor

> Dibuat: 2026-11-26
> Diperbarui: 2026-11-26
> Versi Aplikasi Saat Ini: 1.0.0+1

Dokumen ini mencatat semua perbaikan, fitur yang belum ada, dan peningkatan
yang akan dikerjakan pada update berikutnya. Centang item saat sudah selesai.

---

## 🔴 Prioritas Tinggi — Bug & Kelemahan Fungsional

- [ ] **[BUG] Audit tidak bisa dibatalkan saat proses berjalan**
  - Jika pengguna keluar/tutup halaman di tengah pemeriksaan 12 tautan
    (~8 detik × 3 batch), tidak ada mekanisme pembatalan.
  - Risiko: `setState() on unmounted widget` walau guard `if (!mounted)` ada.
  - Solusi: Tambahkan flag `bool _cancelled` di `_HomeScreenState` atau pakai
    `CancelToken` yang diteruskan ke `ErrorScanner._checkLinksInBatches()`.

- [ ] **[BUG] Validasi panjang URL maksimal belum ada**
  - `HttpFetcher.normalizeAndValidateUrl()` tidak membatasi panjang input.
  - URL > 2048 karakter berpotensi OOM pada beberapa kondisi HTTP.
  - Solusi: Tambahkan pengecekan `if (trimmed.length > 2048) throw FetchException(...)`.

- [ ] **[CARI TAHU] Apakah `flutter/services.dart` juga deprecated di Flutter 3.50?**
  - `report_screen.dart` masih menggunakan `import 'package:flutter/services.dart'`
    untuk `Clipboard`.
  - Akan ketahuan setelah build APK pertama yang berhasil.
  - Jika iya: ganti dengan import dari `package:material_ui/material_ui.dart`
    atau `package:flutter/services.dart` jika masih valid.

---

## 🟡 Prioritas Sedang — Fitur Missing & UX

- [ ] **[FITUR] Share laporan ke aplikasi lain**
  - Tambahkan package `share_plus: ^10.x.x` di `pubspec.yaml`.
  - Di `ReportScreen`, tambahkan tombol **Bagikan** di `AppBar` actions
    yang memanggil `Share.shareXFiles()` atau `Share.share(report.toMarkdown())`.
  - Memungkinkan pengguna berbagi laporan via WhatsApp, Telegram, Email, dll.

- [ ] **[FITUR] Tombol "Audit Ulang" di ReportScreen**
  - Saat ini untuk audit ulang URL yang sama, pengguna harus kembali ke Home
    secara manual lalu ketik URL lagi.
  - Tambahkan `IconButton` atau `FilledButton.tonal` di `AppBar` atau bawah
    layar `ReportScreen` bertuliskan **Audit Ulang**.
  - Aksi: `Navigator.of(context).pop()` lalu langsung trigger `_startAudit()`
    dengan URL yang sama via callback atau `Navigator.pushReplacement`.

- [ ] **[FITUR] Indikator latensi berwarna di chip**
  - Saat ini chip latensi selalu abu-abu netral.
  - Tambahkan logika warna berdasarkan nilai `latencyMs`:
    - 🟢 < 500 ms → `primaryContainer`
    - 🟡 500–1500 ms → `tertiaryContainer`
    - 🔴 > 1500 ms → `errorContainer`
  - Lokasi: `_ReportHeader` di `report_screen.dart` dan `_HistoryCard`
    di `home_screen.dart`.

- [ ] **[FITUR] Filter & Sort riwayat audit**
  - Riwayat saat ini hanya tersusun dari yang terbaru ke terlama.
  - Tambahkan opsi sort: Terbaru / Terlama / Skor AI Slop Tertinggi /
    Status HTTP Error.
  - Tambahkan filter: Hanya tampilkan yang ada temuan keamanan kritis.

- [ ] **[FITUR] Deteksi keamanan form lebih dalam di `SecurityScanner`**
  - Saat ini hanya cek atribut `action` mengarah ke `http://`.
  - Tambahkan deteksi:
    - `<input type="password">` dalam halaman HTTP (sangat kritis).
    - `<form method="get">` yang mengandung field sensitif.
    - `<form>` tanpa atribut `method` (default GET — data tampil di URL).
  - Tingkat severitas: `critical` untuk password di HTTP, `low` untuk GET form.

- [ ] **[FITUR] Buka URL temuan langsung di browser**
  - Tambahkan package `url_launcher: ^6.x.x`.
  - Di `_FindingCard`, jika `finding.target` adalah URL valid, tambahkan
    tombol ikon `open_in_new` di sudut kanan untuk membuka di browser.

- [ ] **[FITUR] Export laporan ke file `.md`**
  - Tambahkan package `path_provider` + `permission_handler` atau pakai
    `share_plus` dengan `XFile` untuk simpan laporan sebagai file Markdown
    di folder Downloads Android.

---

## 🟢 Prioritas Rendah — Enhancement & Polish

- [ ] **[UI] App Icon custom Web Auditor**
  - Saat ini ikon masih mipmap default Flutter (dari template CI).
  - Buat ikon dengan warna biru (`#1565C0`) dan simbol kaca pembesar + rantai.
  - Gunakan `flutter_launcher_icons: ^0.14.x` untuk generate semua ukuran
    mipmap otomatis dari satu file PNG 1024×1024.
  - Tambahkan ke `pubspec.yaml`:
    ```yaml
    dev_dependencies:
      flutter_launcher_icons: ^0.14.1
    flutter_launcher_icons:
      android: true
      image_path: "assets/icon/icon.png"
    ```

- [ ] **[UI] Splash screen native**
  - Saat ini tidak ada splash screen, langsung masuk `HomeScreen`.
  - Gunakan `flutter_native_splash: ^2.x.x` dengan warna latar `#1565C0`
    dan ikon putih Web Auditor.

- [ ] **[UI] Halaman About / Info Versi**
  - Tambahkan menu di `AppBar` → ikon `info_outline` → bottom sheet atau dialog
    yang menampilkan nama app, versi (`package_info_plus`), dan link ke repo GitHub.

- [ ] **[ANALYZER] Dukungan konten multibahasa**
  - Tokenizer di `AiSlopAnalyzer._tokenizeWords()` saat ini hanya menangkap
    karakter Latin & aksen (`[a-zA-Z0-9\u00C0-\u024F']`).
  - Website berbahasa Arab, CJK, Thai, dll. akan salah hitung `wordCount`.
  - Tambahkan unicode word boundary yang lebih luas atau gunakan whitespace
    tokenization sebagai fallback jika karakter non-Latin mendominasi.

- [ ] **[ANALYZER] Tambah lebih banyak frasa klise AI**
  - Daftar `_clichePhrases` saat ini: 42 frasa (21 EN, 21 ID).
  - Tambahkan frasa baru yang sering muncul: "as an AI language model",
    "certainly!", "absolutely!", "of course!", "I'd be happy to",
    "it's worth noting", "dive deep into", dll.

- [ ] **[INFRA] README.md belum ada**
  - Buat `README.md` di root project dengan:
    - Deskripsi singkat aplikasi.
    - Screenshot UI (setelah APK berhasil diinstal).
    - Cara build (prasyarat Flutter, `flutter pub get`, `flutter build apk`).
    - Daftar fitur.
    - Badge GitHub Actions build status.

- [ ] **[INFRA] `dev_dependencies: http` eksplisit untuk test**
  - File `test/web_auditor_test.dart` menggunakan `MockClient` dari `http/testing.dart`.
  - Tambahkan di `pubspec.yaml`:
    ```yaml
    dev_dependencies:
      http: ^1.2.2  # Eksplisit agar MockClient tersedia di test
    ```

- [ ] **[INFRA] Tambahkan `.github/ISSUE_TEMPLATE/` dan `CHANGELOG.md`**
  - Template issue untuk bug report dan feature request.
  - `CHANGELOG.md` untuk mencatat perubahan tiap versi.

---

## 📦 Dependensi yang Akan Ditambahkan

| Package | Keperluan | Prioritas | Versi Target |
|---|---|---|---|
| `share_plus` | Share laporan ke app lain | 🟡 Sedang | `^10.0.0` |
| `url_launcher` | Buka URL temuan di browser | 🟡 Sedang | `^6.3.0` |
| `flutter_launcher_icons` | Generate ikon app | 🟢 Rendah | `^0.14.1` |
| `flutter_native_splash` | Splash screen native | 🟢 Rendah | `^2.4.0` |
| `package_info_plus` | Versi app di halaman About | 🟢 Rendah | `^8.0.0` |

---

## ✅ Sudah Selesai (Versi 1.0.0+1)

- [x] Arsitektur modular `models/services/ui`
- [x] `HttpFetcher` — fetch HTTP + redirect + latensi + Set-Cookie
- [x] `ErrorScanner` — cek status HTTP, `<title>`, `<meta viewport>`, `<img>`, sampel 12 tautan
- [x] `SecurityScanner` — HTTPS, 5 security header, form ke HTTP, cookie attributes
- [x] `AiSlopAnalyzer` — skor 0–100, placeholder, frasa klise ID/EN, pola seragam, TTR
- [x] `AuditOrchestrator` — koordinasi semua scanner + progress callback
- [x] `HistoryStorage` — simpan/hapus riwayat via `shared_preferences` (maks 20)
- [x] `HomeScreen` — input URL, tombol Mulai Audit, progress bar, riwayat
- [x] `ReportScreen` — 3 tab Material 3, tombol Salin Laporan (Markdown)
- [x] `AuditReport.toMarkdown()` — export laporan teks lengkap
- [x] Unit test 5 grup (`HttpFetcher`, `ErrorScanner`, `SecurityScanner`, `AiSlopAnalyzer`, `AuditOrchestrator`)
- [x] `AndroidManifest.xml` — izin INTERNET, label "Web Auditor", minSdk 24
- [x] GitHub Actions — `flutter pub get` → `flutter analyze` → `flutter test` → build APK → upload artifact
- [x] Kotlin DSL Gradle (`settings.gradle.kts`, `build.gradle.kts`, `app/build.gradle.kts`)
- [x] Upgrade Gradle → 9.5.0, AGP → 9.3.1, Kotlin → 2.4.20 (sesuai Flutter 3.50.1)
- [x] Migrasi `flutter/material.dart` → `material_ui` (deprecated sejak Flutter 3.47)
