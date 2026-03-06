// Script: convert_to_webp.dart
// Converts assets/images/fade-*.jpg -> fade-*.webp using the system 'cwebp' tool.

import 'dart:io';

void main() async {
  final dir = Directory('assets/images');
  if (!await dir.exists()) {
    print('assets/images directory not found');
    return;
  }

  // Check for cwebp availability
  var hasCwebp = true;
  try {
    final res = await Process.run('cwebp', ['-version']);
    if (res.exitCode != 0) {
      hasCwebp = false;
    }
  } catch (e) {
    hasCwebp = false;
  }

  if (!hasCwebp) {
    print('The `cwebp` tool is not available on PATH. Install it (e.g. `brew install webp`) or add it to PATH and retry.');
    // We continue because user may still want to create backups; but encoding will be skipped.
  }

  final backupDir = Directory('assets/backup_originals_${DateTime.now().toIso8601String().replaceAll(':', '-') }');
  await backupDir.create(recursive: true);
  print('Backup dir: ${backupDir.path}');

  final files = await dir
      .list()
      .where((e) => e is File && e.path.toLowerCase().contains('fade-') && (e.path.toLowerCase().endsWith('.jpg') || e.path.toLowerCase().endsWith('.jpeg') || e.path.toLowerCase().endsWith('.png')))
      .cast<File>()
      .toList();

  if (files.isEmpty) {
    print('No fade-* images found to convert.');
    return;
  }

  for (final f in files) {
    final baseName = f.uri.pathSegments.last;
    print('Processing: $baseName');
    // copy original to backup
    final backupFile = File('${backupDir.path}/$baseName');
    await f.copy(backupFile.path);

    final outPath = f.path.replaceFirst(RegExp(r'\.(jpg|jpeg|png)\$', caseSensitive: false), '.webp');

    if (!hasCwebp) {
      print('Skipping conversion for $baseName because cwebp is missing. Backup saved to ${backupFile.path}');
      continue;
    }

    // Run cwebp -q 80 input -o output
    try {
      final res = await Process.run('cwebp', ['-q', '80', f.path, '-o', outPath]);
      if (res.exitCode != 0) {
        print('cwebp failed for $baseName: ${res.stderr}\n${res.stdout}');
        continue;
      }
      print('Wrote $outPath');
    } catch (e) {
      print('Failed to run cwebp for $baseName: $e');
    }
  }

  print('Done.');
}
