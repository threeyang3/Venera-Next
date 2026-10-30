import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';
import '../application/annotation_export_service.dart'
    show AnnotationExportCancelled;

/// SQLite's backup API includes committed WAL pages, all documents and source
/// locators. Copying the live database file alone would miss those writes.
Future<String> backupAnnotationDatabase({
  required String databasePath,
  required String destination,
  bool Function()? isCancelled,
}) async {
  void check() {
    if (isCancelled?.call() ?? false) throw const AnnotationExportCancelled();
  }

  check();
  if (!File(databasePath).existsSync()) throw StateError('批注数据库尚未建立');
  final root = Directory(destination);
  final staging = await root.createTemp('.comicnotes-backup-');
  var published = false;
  try {
    final target = p.join(staging.path, 'annotations.db');
    final metadata = await _snapshot(databasePath, target);
    check();
    final digest = (await sha256.bind(File(target).openRead()).first)
        .toString();
    await File(p.join(staging.path, 'backup.json')).writeAsString(
      jsonEncode({
        'format': 'comicnotes-sqlite-backup',
        'formatVersion': 1,
        ...metadata,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'database': 'annotations.db',
        'sha256': digest,
        'includesImages': false,
      }),
      flush: true,
    );
    check();
    final output = p.join(root.path, 'ComicNotes-backup-${const Uuid().v4()}');
    await staging.rename(output);
    published = true;
    return output;
  } finally {
    if (!published && await staging.exists()) {
      await staging.delete(recursive: true);
    }
  }
}

// This isolate closure may capture only these paths, never the cancellation
// callback or its reader/database state.
Future<Map<String, Object?>> _snapshot(
  String databasePath,
  String target,
) => Isolate.run(() async {
  // SQLite may need to create WAL shared-memory files even for this read-only
  // operation. readWrite never creates a missing source database.
  final source = sqlite3.open(databasePath, mode: OpenMode.readWrite);
  try {
    if (source.userVersion < 1 || source.userVersion > 2) {
      throw StateError('不支持的批注数据库版本');
    }
    final copy = sqlite3.open(target);
    try {
      await source.backup(copy, nPage: 64).drain<void>();
      if (copy.select('PRAGMA integrity_check').single.values.single != 'ok' ||
          copy.select('PRAGMA foreign_key_check').isNotEmpty) {
        throw StateError('备份数据库校验失败');
      }
      return <String, Object?>{
        'schemaVersion': copy.userVersion,
        'documentCount': copy
            .select('SELECT COUNT(*) AS n FROM source_documents')
            .single['n'],
        'annotationCount': copy
            .select(
              'SELECT COUNT(*) AS n FROM annotations WHERE deleted_at IS NULL',
            )
            .single['n'],
      };
    } finally {
      copy.dispose();
    }
  } finally {
    source.dispose();
  }
});
