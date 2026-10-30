import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';
import 'package:venera_next/foundation/sqlite_connection.dart';
import 'package:venera_next/foundation/sqlite_transaction.dart';
import '../application/annotation_store.dart';
import '../domain/annotation.dart';
import '../domain/geometry.dart';
import '../domain/source_document.dart';

/// A separate database: removing a local comic never cascades into its notes.
class AnnotationRepository implements AnnotationStore {
  AnnotationRepository(this.db, {this.ownsConnection = false}) {
    _migrate();
  }
  final Database db;
  final bool ownsConnection;
  bool _closed = false;

  factory AnnotationRepository.open(String path) {
    final db = openSqliteDatabase(path);
    try {
      return AnnotationRepository(db, ownsConnection: true);
    } catch (_) {
      db.dispose();
      rethrow;
    }
  }

  void _migrate() {
    db.execute('PRAGMA foreign_keys = ON');
    if (db.select('PRAGMA foreign_keys').single.values.single != 1) {
      throw StateError(
        'Annotation foreign-key constraints must be enabled before entering a transaction',
      );
    }
    final version = db.userVersion;
    if (version > 2) {
      throw StateError(
        'Annotation database version $version is newer than this app',
      );
    }
    if (version == 2) return;
    runSqliteTransaction(db, () {
      if (version == 0) {
        db.execute('''
        CREATE TABLE source_documents (
          document_id TEXT PRIMARY KEY NOT NULL,
          library_key TEXT UNIQUE NOT NULL,
          title TEXT NOT NULL,
          kind TEXT NOT NULL DEFAULT 'local',
          source_uri TEXT,
          source_hash TEXT,
          source_status TEXT NOT NULL DEFAULT 'available',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
        CREATE TABLE source_pages (
          page_id TEXT PRIMARY KEY NOT NULL,
          document_id TEXT NOT NULL REFERENCES source_documents(document_id),
          chapter_id TEXT NOT NULL,
          source_identity TEXT NOT NULL,
          source_image_number INTEGER NOT NULL CHECK(source_image_number > 0),
          source_width REAL NOT NULL CHECK(source_width > 0),
          source_height REAL NOT NULL CHECK(source_height > 0),
          display_cache_uri TEXT,
          source_locator_json TEXT NOT NULL DEFAULT '{}',
          UNIQUE(document_id, chapter_id, source_identity),
          UNIQUE(page_id, document_id)
        );
        CREATE TABLE annotations (
          annotation_id TEXT PRIMARY KEY NOT NULL,
          document_id TEXT NOT NULL REFERENCES source_documents(document_id),
          page_id TEXT NOT NULL,
          kind TEXT NOT NULL CHECK(kind IN ('region','pageNote','bookmark')),
          x0 REAL, y0 REAL, x1 REAL, y1 REAL,
          note_text TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          deleted_at INTEGER,
          schema_version INTEGER NOT NULL DEFAULT 1 CHECK(schema_version = 1),
          FOREIGN KEY(page_id, document_id) REFERENCES source_pages(page_id, document_id),
          CHECK((kind = 'region' AND x0 IS NOT NULL AND y0 IS NOT NULL AND x1 IS NOT NULL AND y1 IS NOT NULL AND
            x0 >= 0 AND y0 >= 0 AND x0 < x1 AND y0 < y1 AND x1 <= 1 AND y1 <= 1) OR
            (kind != 'region' AND x0 IS NULL AND y0 IS NULL AND x1 IS NULL AND y1 IS NULL))
        );
        CREATE INDEX annotations_by_document ON annotations(document_id, deleted_at, created_at);
        CREATE INDEX annotations_by_page ON annotations(page_id, deleted_at);
        CREATE TABLE annotation_tags (
          annotation_id TEXT NOT NULL REFERENCES annotations(annotation_id),
          tag TEXT NOT NULL,
          PRIMARY KEY(annotation_id, tag)
        );
        CREATE TABLE export_manifests (
          export_id TEXT PRIMARY KEY NOT NULL,
          document_id TEXT NOT NULL REFERENCES source_documents(document_id),
          destination_key TEXT NOT NULL,
          last_exported_at INTEGER NOT NULL,
          managed_block_hashes_json TEXT NOT NULL DEFAULT '{}'
        );
      ''');
      }
      db.execute('ALTER TABLE source_documents ADD COLUMN source_size INTEGER');
      db.userVersion = 2;
    }, immediate: true);
  }

  void _check() {
    if (_closed) throw StateError('Annotation store is closed');
  }

  @override
  String openDocument({
    required String libraryKey,
    required String title,
    AnnotationDocumentSource? source,
  }) {
    _check();
    if (libraryKey.isEmpty) throw ArgumentError('Empty library identity');
    return runSqliteTransaction(db, () {
      final now = DateTime.now().toUtc().microsecondsSinceEpoch;
      db.execute(
        '''INSERT INTO source_documents(document_id,library_key,title,created_at,updated_at,kind,source_uri,source_hash,source_size,source_status)
        VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(library_key) DO UPDATE SET title=excluded.title, updated_at=excluded.updated_at,
        kind=CASE WHEN source_documents.source_hash IS NULL THEN excluded.kind ELSE source_documents.kind END,
        source_uri=COALESCE(source_documents.source_uri,excluded.source_uri),
        source_hash=COALESCE(source_documents.source_hash,excluded.source_hash),source_size=COALESCE(source_documents.source_size,excluded.source_size)''',
        [
          const Uuid().v4(),
          libraryKey,
          title,
          now,
          now,
          source?.kind ?? 'localCache',
          source?.uri,
          source?.sha256,
          source?.size,
          source == null ? 'unlinked' : 'available',
        ],
      );
      return db.select(
            'SELECT document_id FROM source_documents WHERE library_key=?',
            [libraryKey],
          ).single['document_id']
          as String;
    }, immediate: true);
  }

  @override
  PageAnchor resolvePage({
    required String documentId,
    required String chapterId,
    required String sourceIdentity,
    required int imageNumber,
    required double width,
    required double height,
    String? assetUri,
    Map<String, Object?>? locator,
  }) {
    _check();
    if (sourceIdentity.isEmpty ||
        imageNumber < 1 ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0) {
      throw ArgumentError('Invalid source page');
    }
    return runSqliteTransaction(db, () {
      final rows = db.select(
        'SELECT * FROM source_pages WHERE document_id=? AND chapter_id=? AND source_identity=?',
        [documentId, chapterId, sourceIdentity],
      );
      if (rows.isNotEmpty) {
        final row = rows.single;
        if ((row['source_width'] as num).toDouble() != width ||
            (row['source_height'] as num).toDouble() != height) {
          throw StateError(
            'Source image dimensions changed; existing annotations need relinking',
          );
        }
        db.execute(
          'UPDATE source_pages SET source_image_number=?,display_cache_uri=COALESCE(?,display_cache_uri) WHERE page_id=?',
          [imageNumber, assetUri, row['page_id']],
        );
        return _anchor(row, imageNumber: imageNumber);
      }
      final id = const Uuid().v4();
      db.execute(
        '''INSERT INTO source_pages(page_id,document_id,chapter_id,source_identity,source_image_number,source_width,source_height,display_cache_uri,source_locator_json)
        VALUES(?,?,?,?,?,?,?,?,?)''',
        [
          id,
          documentId,
          chapterId,
          sourceIdentity,
          imageNumber,
          width,
          height,
          assetUri,
          jsonEncode(
            locator ?? {'kind': 'localCache', 'identity': sourceIdentity},
          ),
        ],
      );
      return PageAnchor(
        documentId: documentId,
        pageId: id,
        chapterId: chapterId,
        sourceImageNumber: imageNumber,
        sourceWidth: width,
        sourceHeight: height,
      );
    }, immediate: true);
  }

  @override
  AnnotationSourcePage? sourcePage(String documentId, String pageId) {
    _check();
    final rows = db.select(
      'SELECT * FROM source_pages WHERE document_id=? AND page_id=?',
      [documentId, pageId],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final raw = jsonDecode(row['source_locator_json'] as String);
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid source page locator');
    }
    return AnnotationSourcePage(
      anchor: _anchor(row),
      sourceIdentity: row['source_identity'] as String,
      assetUri: row['display_cache_uri'] as String?,
      locator: Map<String, Object?>.unmodifiable(raw),
    );
  }

  @override
  AnnotationSourceDocument document(String documentId) {
    _check();
    final row = db.select(
      'SELECT * FROM source_documents WHERE document_id=?',
      [documentId],
    ).single;
    final hash = row['source_hash'] as String?;
    return AnnotationSourceDocument(
      documentId: documentId,
      title: row['title'] as String,
      libraryKey: row['library_key'] as String,
      status: row['source_status'] as String,
      source: hash == null
          ? null
          : AnnotationDocumentSource(
              kind: row['kind'] as String,
              uri: row['source_uri'] as String,
              sha256: hash,
              size: row['source_size'] as int,
            ),
    );
  }

  @override
  void setSourceStatus(String documentId, String status) {
    _check();
    if (!{
      'available',
      'missing',
      'changed',
      'unlinked',
      'relink_required',
    }.contains(status)) {
      throw ArgumentError('Invalid source status');
    }
    db.execute(
      'UPDATE source_documents SET source_status=?,updated_at=? WHERE document_id=?',
      [status, DateTime.now().toUtc().microsecondsSinceEpoch, documentId],
    );
  }

  @override
  void relocateSource(String documentId, AnnotationDocumentSource source) {
    _check();
    final uri = Uri.tryParse(source.uri);
    if (uri == null ||
        uri.scheme != 'file' ||
        (uri.host.isNotEmpty && uri.host != 'localhost') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError('Only local original files can be relocated');
    }
    runSqliteTransaction(db, () {
      final current = document(documentId).source;
      if (current == null ||
          current.kind != source.kind ||
          current.sha256 != source.sha256 ||
          current.size != source.size) {
        throw StateError(
          'Original identity differs; annotations were not relinked',
        );
      }
      db.execute(
        '''UPDATE source_documents SET source_uri=?,source_status='available',updated_at=?
        WHERE document_id=?''',
        [source.uri, DateTime.now().toUtc().microsecondsSinceEpoch, documentId],
      );
    }, immediate: true);
  }

  List<AnnotationSourceDocument> documents() {
    _check();
    return db
        .select('SELECT document_id FROM source_documents ORDER BY created_at')
        .map((row) => document(row['document_id'] as String))
        .toList();
  }

  List<AnnotationSourcePage> pages(String documentId) {
    _check();
    return db
        .select(
          'SELECT page_id FROM source_pages WHERE document_id=? ORDER BY page_id',
          [documentId],
        )
        .map((row) => sourcePage(documentId, row['page_id'] as String)!)
        .toList();
  }

  /// Recover the original document UUID into an empty, reimported library slot.
  /// No notes are merged or deleted, including tombstones in the new slot.
  void recoverDocument({
    required AnnotationSourceDocument previous,
    required AnnotationSourceDocument replacement,
    required List<AnnotationSourcePage> expectedPages,
    required Map<String, AnnotationSourcePage> resolvedPages,
  }) {
    _check();
    runSqliteTransaction(db, () {
      final old = document(previous.documentId),
          target = document(replacement.documentId);
      bool sameSource(
        AnnotationDocumentSource? a,
        AnnotationDocumentSource? b,
      ) =>
          a != null &&
          b != null &&
          a.kind == b.kind &&
          a.sha256 == b.sha256 &&
          a.size == b.size;
      if (old.documentId == target.documentId ||
          old.libraryKey != previous.libraryKey ||
          target.libraryKey != replacement.libraryKey ||
          !sameSource(old.source, previous.source) ||
          !sameSource(target.source, replacement.source) ||
          !sameSource(old.source, target.source)) {
        throw StateError('来源身份或书库绑定已变化，请重新查找旧批注');
      }
      if (db.select('SELECT 1 FROM annotations WHERE document_id=? LIMIT 1', [
        target.documentId,
      ]).isNotEmpty) {
        throw StateError('当前导入已有批注或删除记录，不会覆盖或合并');
      }
      final current = pages(old.documentId);
      if (current.length != expectedPages.length ||
          resolvedPages.length != current.length) {
        throw StateError('来源页集合已变化');
      }
      final expected = {
        for (final page in expectedPages) page.anchor.pageId: page,
      };
      for (final page in current) {
        final before = expected[page.anchor.pageId],
            after = resolvedPages[page.anchor.pageId];
        if (before == null ||
            after == null ||
            page.sourceIdentity != before.sourceIdentity ||
            page.anchor.chapterId != before.anchor.chapterId ||
            page.anchor.sourceWidth != before.anchor.sourceWidth ||
            page.anchor.sourceHeight != before.anchor.sourceHeight ||
            jsonEncode(page.locator) != jsonEncode(before.locator) ||
            after.anchor.documentId != old.documentId ||
            after.anchor.pageId != page.anchor.pageId ||
            after.sourceIdentity != page.sourceIdentity ||
            after.anchor.chapterId != page.anchor.chapterId ||
            after.anchor.sourceWidth != page.anchor.sourceWidth ||
            after.anchor.sourceHeight != page.anchor.sourceHeight) {
          throw StateError('来源页映射已变化，未恢复旧批注');
        }
      }
      db.execute('DELETE FROM source_pages WHERE document_id=?', [
        target.documentId,
      ]);
      db.execute('DELETE FROM export_manifests WHERE document_id=?', [
        target.documentId,
      ]);
      db.execute('DELETE FROM source_documents WHERE document_id=?', [
        target.documentId,
      ]);
      db.execute(
        '''UPDATE source_documents SET library_key=?,title=?,source_uri=?,source_status='available',updated_at=? WHERE document_id=?''',
        [
          target.libraryKey,
          target.title,
          target.source!.uri,
          DateTime.now().toUtc().microsecondsSinceEpoch,
          old.documentId,
        ],
      );
      for (final page in resolvedPages.values) {
        db.execute(
          '''UPDATE source_pages SET source_image_number=?,display_cache_uri=?,source_locator_json=? WHERE document_id=? AND page_id=?''',
          [
            page.anchor.sourceImageNumber,
            page.assetUri,
            jsonEncode(page.locator),
            old.documentId,
            page.anchor.pageId,
          ],
        );
      }
    }, immediate: true);
  }

  /// Captures the exact records displayed by a manual page-mapping preview.
  /// The runtime must also prove the old library binding is no longer live.
  ManualAnnotationRecoveryPlan prepareManualRecovery({
    required String previousDocumentId,
    required String replacementDocumentId,
  }) {
    _check();
    return runSqliteTransaction(db, () {
      if (previousDocumentId == replacementDocumentId) {
        throw ArgumentError('Manual recovery needs two separate documents');
      }
      final previous = document(previousDocumentId);
      final replacement = document(replacementDocumentId);
      if (_hasAnyNotes(replacementDocumentId)) {
        throw StateError('当前漫画已有批注或删除记录，不会覆盖或合并');
      }
      final oldPages = pages(previousDocumentId),
          targetPages = pages(replacementDocumentId);
      if (oldPages.isEmpty ||
          targetPages.isEmpty ||
          !_hasAnyNotes(previousDocumentId)) {
        throw StateError('缺少可供预览的旧批注页或目标页');
      }
      return ManualAnnotationRecoveryPlan._(
        previous,
        replacement,
        List.unmodifiable(oldPages),
        List.unmodifiable(targetPages),
        _manualSnapshot(previousDocumentId),
        _manualSnapshot(replacementDocumentId),
      );
    });
  }

  bool _hasAnyNotes(String documentId) => db.select(
    'SELECT 1 FROM annotations WHERE document_id=? LIMIT 1',
    [documentId],
  ).isNotEmpty;

  String _manualSnapshot(String documentId) => jsonEncode([
    db
        .select('SELECT * FROM source_documents WHERE document_id=?', [
          documentId,
        ])
        .map((row) => Map<String, Object?>.from(row))
        .toList(),
    db
        .select(
          'SELECT * FROM source_pages WHERE document_id=? ORDER BY page_id',
          [documentId],
        )
        .map((row) => Map<String, Object?>.from(row))
        .toList(),
    db
        .select(
          'SELECT * FROM annotations WHERE document_id=? ORDER BY annotation_id',
          [documentId],
        )
        .map((row) => Map<String, Object?>.from(row))
        .toList(),
    db
        .select(
          'SELECT t.* FROM annotation_tags t JOIN annotations a USING(annotation_id) WHERE a.document_id=? ORDER BY t.annotation_id,t.tag',
          [documentId],
        )
        .map((row) => Map<String, Object?>.from(row))
        .toList(),
    db
        .select(
          'SELECT * FROM export_manifests WHERE document_id=? ORDER BY export_id',
          [documentId],
        )
        .map((row) => Map<String, Object?>.from(row))
        .toList(),
  ]);

  /// Explicit one-to-one remapping after a user has compared both page sets.
  /// This is not evidence that two sources have identical bytes. Changed page
  /// dimensions require a separate coordinate review, never implicit scaling.
  void applyManualRecovery({
    required ManualAnnotationRecoveryPlan plan,
    required Map<String, String> pageMapping,
  }) {
    _check();
    runSqliteTransaction(db, () {
      final oldId = plan.previous.documentId,
          targetId = plan.replacement.documentId;
      if (_manualSnapshot(oldId) != plan._previousSnapshot ||
          _manualSnapshot(targetId) != plan._replacementSnapshot ||
          _hasAnyNotes(targetId)) {
        throw StateError('预览后文档、批注或目标页发生变化，请重新预览');
      }
      final oldPages = {
        for (final page in pages(oldId)) page.anchor.pageId: page,
      };
      final targets = {
        for (final page in pages(targetId)) page.anchor.pageId: page,
      };
      if (pageMapping.length != oldPages.length ||
          !pageMapping.keys.every(oldPages.containsKey) ||
          pageMapping.values.toSet().length != oldPages.length) {
        throw ArgumentError('必须逐页指定唯一目标，不能遗漏或合并旧页');
      }
      for (final entry in pageMapping.entries) {
        final before = oldPages[entry.key]!, after = targets[entry.value];
        if (after == null ||
            before.anchor.sourceWidth != after.anchor.sourceWidth ||
            before.anchor.sourceHeight != after.anchor.sourceHeight ||
            after.assetUri == null) {
          throw StateError('目标页不存在、失联或自然尺寸不同，需要另行核对坐标');
        }
      }
      // Retire all old unique identity keys first, allowing explicit page swaps.
      for (final page in oldPages.values) {
        db.execute(
          'UPDATE source_pages SET source_identity=? WHERE page_id=? AND document_id=?',
          ['manual-staging:${const Uuid().v4()}', page.anchor.pageId, oldId],
        );
      }
      for (final entry in pageMapping.entries) {
        final before = oldPages[entry.key]!, after = targets[entry.value]!;
        db.execute(
          '''UPDATE source_pages SET chapter_id=?,source_identity=?,source_image_number=?,display_cache_uri=?,source_locator_json=?
          WHERE document_id=? AND page_id=?''',
          [
            after.anchor.chapterId,
            after.sourceIdentity,
            after.anchor.sourceImageNumber,
            after.assetUri,
            jsonEncode({
              ...after.locator,
              'manualMapping': {
                'previousSourceIdentity': before.sourceIdentity,
                'previousChapterId': before.anchor.chapterId,
                'previousLocator': before.locator,
                if (plan.previous.source case final source?)
                  'previousDocumentSource': {
                    'kind': source.kind,
                    'uri': source.uri,
                    'sha256': source.sha256,
                    'size': source.size,
                  },
                'confirmedAt': DateTime.now().toUtc().toIso8601String(),
              },
            }),
            oldId,
            before.anchor.pageId,
          ],
        );
      }
      db.execute('DELETE FROM source_pages WHERE document_id=?', [targetId]);
      db.execute('DELETE FROM export_manifests WHERE document_id=?', [
        targetId,
      ]);
      db.execute('DELETE FROM source_documents WHERE document_id=?', [
        targetId,
      ]);
      final target = plan.replacement;
      db.execute(
        '''UPDATE source_documents SET library_key=?,title=?,kind=?,source_uri=?,source_hash=?,source_size=?,source_status=?,updated_at=?
        WHERE document_id=?''',
        [
          target.libraryKey,
          target.title,
          target.source?.kind ?? 'local',
          target.source?.uri,
          target.source?.sha256,
          target.source?.size,
          target.source == null ? 'unlinked' : target.status,
          DateTime.now().toUtc().microsecondsSinceEpoch,
          oldId,
        ],
      );
    }, immediate: true);
  }

  PageAnchor _anchor(Row row, {int? imageNumber}) => PageAnchor(
    documentId: row['document_id'] as String,
    pageId: row['page_id'] as String,
    chapterId: row['chapter_id'] as String,
    sourceImageNumber: imageNumber ?? row['source_image_number'] as int,
    sourceWidth: (row['source_width'] as num).toDouble(),
    sourceHeight: (row['source_height'] as num).toDouble(),
  );

  @override
  List<Annotation> list(String documentId) {
    _check();
    final tags = <String, List<String>>{};
    for (final row in db.select(
      '''SELECT t.annotation_id,t.tag FROM annotation_tags t
      JOIN annotations a ON a.annotation_id=t.annotation_id
      WHERE a.document_id=? AND a.deleted_at IS NULL ORDER BY t.tag''',
      [documentId],
    )) {
      tags
          .putIfAbsent(row['annotation_id'] as String, () => [])
          .add(row['tag'] as String);
    }
    return db
        .select(
          '''SELECT a.*,p.chapter_id,p.source_image_number,p.source_width,p.source_height
      FROM annotations a JOIN source_pages p ON a.page_id=p.page_id AND a.document_id=p.document_id
      WHERE a.document_id=? AND a.deleted_at IS NULL ORDER BY a.created_at,a.annotation_id''',
          [documentId],
        )
        .map(
          (row) => Annotation(
            id: row['annotation_id'] as String,
            anchor: _anchor(row),
            kind: AnnotationKind.values.byName(row['kind'] as String),
            rect: row['x0'] == null
                ? null
                : ContentRect(
                    (row['x0'] as num).toDouble(),
                    (row['y0'] as num).toDouble(),
                    (row['x1'] as num).toDouble(),
                    (row['y1'] as num).toDouble(),
                  ),
            text: row['note_text'] as String,
            tags: tags[row['annotation_id']] ?? const [],
            createdAt: DateTime.fromMicrosecondsSinceEpoch(
              row['created_at'] as int,
              isUtc: true,
            ),
            updatedAt: DateTime.fromMicrosecondsSinceEpoch(
              row['updated_at'] as int,
              isUtc: true,
            ),
          ),
        )
        .toList();
  }

  @override
  void put(Annotation note) {
    _check();
    runSqliteTransaction(db, () {
      final existing = db.select(
        'SELECT document_id,page_id,deleted_at FROM annotations WHERE annotation_id=?',
        [note.id],
      );
      if (existing.isNotEmpty &&
          (existing.single['document_id'] != note.anchor.documentId ||
              existing.single['page_id'] != note.anchor.pageId)) {
        throw ArgumentError(
          'An annotation cannot move to a different source page',
        );
      }
      if (existing.isNotEmpty && existing.single['deleted_at'] != null) {
        throw StateError('Annotation was deleted in another reader');
      }
      final r = note.rect;
      db.execute(
        '''INSERT INTO annotations(annotation_id,document_id,page_id,kind,x0,y0,x1,y1,note_text,created_at,updated_at)
        VALUES(?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(annotation_id) DO UPDATE SET
        kind=excluded.kind,x0=excluded.x0,y0=excluded.y0,x1=excluded.x1,y1=excluded.y1,note_text=excluded.note_text,
        updated_at=excluded.updated_at,deleted_at=NULL''',
        [
          note.id,
          note.anchor.documentId,
          note.anchor.pageId,
          note.kind.name,
          r?.x0,
          r?.y0,
          r?.x1,
          r?.y1,
          note.text,
          note.createdAt.microsecondsSinceEpoch,
          note.updatedAt.microsecondsSinceEpoch,
        ],
      );
      db.execute('DELETE FROM annotation_tags WHERE annotation_id=?', [
        note.id,
      ]);
      for (final tag in note.tags) {
        db.execute(
          'INSERT INTO annotation_tags(annotation_id,tag) VALUES(?,?)',
          [note.id, tag],
        );
      }
    }, immediate: true);
  }

  @override
  void remove(String documentId, String annotationId) {
    _check();
    db.execute(
      'UPDATE annotations SET deleted_at=?,updated_at=? WHERE document_id=? AND annotation_id=? AND deleted_at IS NULL',
      [
        DateTime.now().toUtc().microsecondsSinceEpoch,
        DateTime.now().toUtc().microsecondsSinceEpoch,
        documentId,
        annotationId,
      ],
    );
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    if (ownsConnection) db.dispose();
  }
}

/// Immutable storage snapshot for a pending, explicitly reviewed mapping.
/// Not serializable: a reopened session must prepare a fresh preview.
class ManualAnnotationRecoveryPlan {
  ManualAnnotationRecoveryPlan._(
    this.previous,
    this.replacement,
    this.previousPages,
    this.replacementPages,
    this._previousSnapshot,
    this._replacementSnapshot,
  );
  final AnnotationSourceDocument previous, replacement;
  final List<AnnotationSourcePage> previousPages, replacementPages;
  final String _previousSnapshot, _replacementSnapshot;
}
