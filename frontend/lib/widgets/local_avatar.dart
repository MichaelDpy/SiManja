import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Avatar lokal yang tahan file hilang / file korup / race (A1-11).
///
/// Perbaikan dari pola `existsSync` + `CircleAvatar(backgroundImage: FileImage)`:
/// `existsSync` **saja tidak cukup** — file bisa korup (decode gagal) atau
/// hilang **sesudah** pengecekan (file race). `CircleAvatar.backgroundImage`
/// **tidak punya `errorBuilder`**, dan `Image.file` membaca ulang dari disk
/// secara async. Widget ini membaca bytes **sekali secara aman**
/// ([readLocalImageBytes]) lalu memakai `Image.memory` dengan `errorBuilder`
/// agar decode failure / file missing → **ikon fallback** tanpa **error tak
/// tertangani**.
///
/// Tidak menghapus file asli; tidak menambah Storage/FCM; `photoPath` lokal
/// tidak disimpan ke Firestore.
class SafeLocalAvatar extends StatelessWidget {
  const SafeLocalAvatar({
    super.key,
    required this.imagePath,
    required this.radius,
    required this.fallbackIcon,
    required this.fallbackIconColor,
    required this.backgroundColor,
    this.fallbackIconSize,
    this.fit = BoxFit.cover,
  });

  final String? imagePath;
  final double radius;
  final IconData fallbackIcon;
  final Color fallbackIconColor;
  final Color backgroundColor;
  final double? fallbackIconSize;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final diameter = radius * 2;
    final bytes = readLocalImageBytes(imagePath);
    final fallbackSize = fallbackIconSize ?? radius;

    Widget fallback() =>
        Icon(fallbackIcon, color: fallbackIconColor, size: fallbackSize);

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: bytes == null
          ? fallback()
          : ClipOval(
              child: Image.memory(
                bytes,
                width: diameter,
                height: diameter,
                fit: fit,
                // Korup / hilang sesudah read / decode gagal → fallback;
                // tidak memancarkan error tak tertangani.
                errorBuilder: (context, error, stackTrace) => fallback(),
              ),
            ),
    );
  }
}

/// Kembalikan [File] bila [path] non-kosong & `existsSync`; `null` jika
/// hilang/error. **Pra-pemeriksaan saja.** **Tidak menghapus file.**
File? localImageFile(String? path) {
  if (path == null || path.trim().isEmpty) return null;
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    return file;
  } catch (_) {
    return null;
  }
}

/// Baca bytes file gambar secara aman.
///
/// `null` bila path kosong, file hilang, **atau hilang/dihapus SESUDAH
/// `existsSync`** (file race), atau tidak dapat dibaca. Bytes tetap diperiksa
/// ulang `existsSync` sebelum membaca. Korup → bytes dikembalikan tetapi
/// `Image.memory.errorBuilder` menangani decode. **Tidak menghapus file.**
Uint8List? readLocalImageBytes(String? path) {
  final file = localImageFile(path);
  if (file == null) return null;
  try {
    // File bisa hilang/dihapus SESUDAH exists-check (race) → throws → null.
    if (!file.existsSync()) return null;
    return file.readAsBytesSync();
  } catch (_) {
    return null;
  }
}
