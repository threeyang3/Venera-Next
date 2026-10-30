import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/foundation/sqlite_transaction.dart';
import '../application/annotation_export_service.dart';
import '../application/annotation_restore_service.dart';
import 'annotation_repository.dart';

const _columns = <String, List<String>>{
  'source_documents': [
    'document_id',
    'library_key',
    'title',
    'kind',
    'source_uri',
    'source_hash',
    'source_status',
    'created_at',
    'updated_at',
    'source_size',
  ],
  'source_pages': [
    'page_id',
    'document_id',
    'chapter_id',
    'source_identity',
    'source_image_number',
    'source_width',
    'source_height',
    'display_cache_uri',
    'source_locator_json',
  ],
  'annotations': [
    'annotation_id',
    'document_id',
    'page_id',
    'kind',
    'x0',
    'y0',
    'x1',
    'y1',
    'note_text',
    'created_at',
    'updated_at',
    'deleted_at',
    'schema_version',
  ],
  'annotation_tags': ['annotation_id', 'tag'],
  'export_manifests': [
    'export_id',
    'document_id',
    'destination_key',
    'last_exported_at',
    'managed_block_hashes_json',
  ],
};

/// Copies into a private snapshot before validating. Only fixed-column values
/// cross into our own schema; imported SQLite schema and triggers never execute.
Future<AnnotationRestorePreview> prepareAnnotationRestore({
  required String backupDirectory,
  required String databasePath,
  bool Function()? isCancelled,
}) async {
  void check() {
    if (isCancelled?.call() ?? false) throw const AnnotationExportCancelled();
  }

  check();
  final manifestFile = File(p.join(backupDirectory, 'backup.json'));
  if (await manifestFile.length() > 65536) {
    throw const FormatException('备份清单过大');
  }
  final manifest = jsonDecode(await manifestFile.readAsString());
  if (manifest is! Map ||
      manifest['format'] != 'comicnotes-sqlite-backup' ||
      manifest['formatVersion'] != 1 ||
      manifest['database'] != 'annotations.db' ||
      ![1, 2].contains(manifest['schemaVersion']) ||
      manifest['includesImages'] != false) {
    throw const FormatException('不支持的批注备份格式');
  }
  final input = File(p.join(backupDirectory, 'annotations.db'));
  if (await input.length() > 256 * 1024 * 1024) {
    throw const FormatException('备份数据库超过 256 MiB');
  }
  final stage = await Directory.systemTemp.createTemp('comicnotes-restore-');
  Database? source;
  AnnotationRepository? clean;
  try {
    final snapshot = await input.copy(p.join(stage.path, 'input.db'));
    if (await snapshot.length() > 256 * 1024 * 1024) {
      throw const FormatException('备份数据库超过 256 MiB');
    }
    check();
    if ((await sha256.bind(snapshot.openRead()).first).toString() !=
        manifest['sha256']) {
      throw const FormatException('备份数据库哈希不匹配');
    }
    source = sqlite3.open(snapshot.path, mode: OpenMode.readOnly);
    source.execute('PRAGMA trusted_schema=OFF');
    if (source.userVersion != manifest['schemaVersion'] ||
        source
            .select(
              "SELECT name FROM sqlite_master WHERE type IN ('view','trigger')",
            )
            .isNotEmpty ||
        source.select('PRAGMA integrity_check').single.values.single != 'ok' ||
        source.select('PRAGMA foreign_key_check').isNotEmpty) {
      throw const FormatException('备份数据库校验失败');
    }
    clean = AnnotationRepository.open(p.join(stage.path, 'validated.db'));
    runSqliteTransaction(clean.db, () {
      for (final entry in _columns.entries) {
        final columns = entry.value;
        final select = columns
            .map(
              (c) => c == 'source_size' && source!.userVersion == 1
                  ? 'NULL AS source_size'
                  : c,
            )
            .join(',');
        for (final row in source!.select('SELECT $select FROM ${entry.key}')) {
          for (final column in columns.where(
            (c) => c.endsWith('_id') && c != 'chapter_id',
          )) {
            if (!RegExp(
              r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
            ).hasMatch(row[column] as String)) {
              throw const FormatException('备份包含无效 UUID');
            }
          }
          for (final column in columns.where((c) => c.endsWith('_json'))) {
            if (jsonDecode(row[column] as String) is! Map) {
              throw const FormatException('备份包含无效来源映射');
            }
          }
          for (final column in columns.where(
            (c) => [
              'source_width',
              'source_height',
              'x0',
              'y0',
              'x1',
              'y1',
            ].contains(c),
          )) {
            final value = row[column];
            if (value != null && (value is! num || !value.isFinite)) {
              throw const FormatException('备份包含无效页面坐标');
            }
          }
          _insert(clean!.db, entry.key, columns, [
            for (final c in columns) row[c],
          ]);
        }
      }
    });
    final docs = clean.documents();
    final count =
        clean.db
                .select(
                  'SELECT COUNT(*) n FROM annotations WHERE deleted_at IS NULL',
                )
                .single['n']
            as int;
    if (docs.length != manifest['documentCount'] ||
        count != manifest['annotationCount']) {
      throw const FormatException('备份清单记录数不匹配');
    }
    check();
    final target = AnnotationRepository.open(databasePath);
    late int existing;
    try {
      existing = docs
          .where(
            (d) => target.db.select(
              'SELECT 1 FROM source_documents WHERE document_id=?',
              [d.documentId],
            ).isNotEmpty,
          )
          .length;
    } finally {
      target.close();
    }
    final result = _PreparedRestore(
      stage,
      clean,
      databasePath,
      docs.length,
      count,
      existing,
    );
    clean = null;
    return result;
  } catch (_) {
    source?.dispose();
    source = null;
    clean?.close();
    await stage.delete(recursive: true);
    rethrow;
  } finally {
    source?.dispose();
  }
}

void _insert(
  Database db,
  String table,
  List<String> columns,
  List<Object?> values,
) {
  db.execute(
    'INSERT INTO $table(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')})',
    values,
  );
}

class _PreparedRestore implements AnnotationRestorePreview {
  _PreparedRestore(
    this.stage,
    this.source,
    this.databasePath,
    this.documentCount,
    this.annotationCount,
    this.existingDocumentCount,
  );
  final Directory stage;
  final AnnotationRepository source;
  final String databasePath;
  @override
  final int documentCount, annotationCount, existingDocumentCount;
  bool _disposed = false;
  bool _applied = false;

  @override
  Future<AnnotationRestoreResult> restore({
    bool Function()? isCancelled,
  }) async {
    if (_disposed || _applied) throw StateError('恢复预览已关闭或已使用');
    void check() {
      if (isCancelled?.call() ?? false) throw const AnnotationExportCancelled();
    }

    check();
    final target = AnnotationRepository.open(databasePath);
    try {
      final result = runSqliteTransaction(target.db, () {
        final imported = <String>{};
        var skipped = 0;
        for (final row in source.db.select('SELECT * FROM source_documents')) {
          check();
          final id = row['document_id'] as String;
          if (target.db.select(
            'SELECT 1 FROM source_documents WHERE document_id=?',
            [id],
          ).isNotEmpty) {
            skipped++;
            continue;
          }
          imported.add(id);
          final values = [
            for (final c in _columns['source_documents']!) row[c],
          ];
          // Installation-local IDs must never accidentally attach restored notes
          // to a different book. Exact-source recovery binds these orphan IDs.
          values[1] = 'restored:$id';
          values[6] = 'relink_required';
          _insert(
            target.db,
            'source_documents',
            _columns['source_documents']!,
            values,
          );
        }
        for (final entry in _columns.entries.where(
          (e) => e.key != 'source_documents',
        )) {
          final rows = entry.key == 'annotation_tags'
              ? source.db.select(
                  'SELECT t.*, a.document_id FROM annotation_tags t JOIN annotations a USING(annotation_id)',
                )
              : source.db.select('SELECT * FROM ${entry.key}');
          for (final row in rows) {
            check();
            if (!imported.contains(row['document_id'])) continue;
            _insert(target.db, entry.key, entry.value, [
              for (final c in entry.value)
                c == 'display_cache_uri' ? null : row[c],
            ]);
          }
        }
        check();
        return AnnotationRestoreResult(imported.length, skipped);
      }, immediate: true);
      _applied = true;
      return result;
    } finally {
      target.close();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    source.close();
    await stage.delete(recursive: true);
  }
}
