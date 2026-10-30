import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/features/annotations/application/annotation_session.dart';
import 'package:venera_next/features/annotations/data/annotation_repository.dart';
import 'package:venera_next/features/annotations/domain/annotation.dart';
import 'package:venera_next/features/annotations/domain/geometry.dart';

void main() {
  late Directory directory;
  late String path;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('comicnotes-store-');
    path = '${directory.path}/annotations.db';
  });
  tearDown(() => directory.deleteSync(recursive: true));

  AnnotationSession session(
    AnnotationRepository store, [
    String key = 'local:1:version-a',
  ]) => AnnotationSession.persistent(store, libraryKey: key, title: '同名漫画');
  PageAnchor page(
    AnnotationSession s, {
    int number = 1,
    String identity = 'one/001.png',
  }) => s.anchor(
    chapterId: 'one',
    imageNumber: number,
    width: 1000,
    height: 2000,
    sourceIdentity: identity,
    assetUri: 'file:///missing/$identity',
  );

  test(
    'a stale reader cannot silently resurrect another reader\'s deletion',
    () {
      final store = AnnotationRepository.open(path);
      try {
        final first = session(store);
        final note = first.add(page(first), AnnotationKind.pageNote, '原批注');
        final stale = session(store);
        first.remove(note.id);
        expect(() => stale.update(note.id, '迟到修改'), throwsStateError);
        expect(store.list(first.documentId), isEmpty);
        expect(stale.all.single.text, '原批注');
      } finally {
        store.close();
      }
    },
  );

  test(
    'tags survive reopening and failed tag writes roll back the whole edit',
    () {
      var store = AnnotationRepository.open(path);
      try {
        final first = session(store);
        final note = first.add(
          page(first),
          AnnotationKind.pageNote,
          'Keep body',
        );
        first.setTags(note.id, [' 构图 ', '人物', '构图', '']);
        expect(first.all.single.tags, ['人物', '构图']);
        first.update(note.id, 'Edited body');
        store.close();
        store = AnnotationRepository.open(path);
        final reopened = session(store);
        expect(reopened.all.single.tags, ['人物', '构图']);
        expect(reopened.all.single.text, 'Edited body');
        store.db.execute(
          "CREATE TRIGGER fail_tag BEFORE INSERT ON annotation_tags BEGIN SELECT RAISE(ABORT,'disk write test'); END",
        );
        expect(
          () => reopened.setTags(note.id, ['新标签']),
          throwsA(isA<SqliteException>()),
        );
        expect(reopened.all.single.tags, ['人物', '构图']);
        expect(store.list(reopened.documentId).single.tags, ['人物', '构图']);
        expect(
          store.list(reopened.documentId).single.updatedAt,
          reopened.all.single.updatedAt,
        );
        expect(
          () => reopened.setTags(note.id, ['a' * 65]),
          throwsArgumentError,
        );
        expect(
          () => reopened.setTags(note.id, ['bad\ncontrol']),
          throwsArgumentError,
        );
        store.db.execute('DROP TRIGGER fail_tag');
        final stale = session(store);
        reopened.remove(note.id);
        expect(() => stale.setTags(note.id, ['迟到']), throwsStateError);
        expect(store.list(reopened.documentId), isEmpty);
      } finally {
        store.close();
      }
    },
  );

  test(
    'foreign-key activation cannot be silently skipped inside a transaction',
    () {
      final db = sqlite3.open(path)..execute('BEGIN');
      try {
        expect(() => AnnotationRepository(db), throwsStateError);
        expect(db.userVersion, 0);
        db.execute('ROLLBACK');
      } finally {
        db.dispose();
      }
    },
  );

  test(
    'committed notes and all stable IDs recover after reopening database',
    () {
      var store = AnnotationRepository.open(path);
      final a = session(store), p = page(a);
      final note = a.add(
        p,
        AnnotationKind.region,
        '永久笔记',
        rect: ContentRect(0.1, 0.2, 0.5, 0.7),
      );
      final docId = a.documentId, pageId = p.pageId, id = note.id;
      store.close();
      store = AnnotationRepository.open(path);
      try {
        final b = session(store), restored = page(b);
        expect(b.documentId, docId);
        expect(restored.pageId, pageId);
        final value = b.forPage(restored).single;
        expect(value.id, id);
        expect(value.text, '永久笔记');
        expect(value.rect!.toJson(), note.rect!.toJson());
        expect(value.createdAt, note.createdAt);
        b.update(id, '编辑后');
        expect(store.list(docId).single.text, '编辑后');
        b.remove(id);
        expect(store.list(docId), isEmpty);
        expect(
          store.db
              .select('SELECT deleted_at FROM annotations')
              .single['deleted_at'],
          isNotNull,
        );
        expect(store.db.userVersion, 2);
      } finally {
        store.close();
      }
    },
  );

  test('schema v1 upgrades to v2 without changing stored IDs or notes', () {
    var store = AnnotationRepository.open(path);
    final first = session(store),
        item = first.add(page(first), AnnotationKind.pageNote, '升级后保留');
    store.db.execute('ALTER TABLE source_documents DROP COLUMN source_size');
    store.db.userVersion = 1;
    store.close();
    store = AnnotationRepository.open(path);
    try {
      final restored = session(store);
      expect(store.db.userVersion, 2);
      expect(restored.documentId, first.documentId);
      expect(restored.all.single.id, item.id);
      expect(restored.all.single.text, '升级后保留');
      expect(restored.sourceDocument!.source, isNull);
    } finally {
      store.close();
    }
  });

  test(
    'refreshing source order updates working and exported anchors without changing note identity',
    () {
      final store = AnnotationRepository.open(path);
      try {
        final original = session(store), source = page(original);
        final note = original.add(source, AnnotationKind.pageNote, '原笔记');
        final reordered = page(original, number: 3);
        expect(reordered.pageId, source.pageId);
        expect(original.all.single.anchor.sourceImageNumber, 3);
        expect(original.all.single.id, note.id);
        expect(original.all.single.createdAt, note.createdAt);
        expect(original.all.single.toJson()['sourceImageNumber'], 3);
        expect(
          store.list(original.documentId).single.anchor.sourceImageNumber,
          3,
        );
      } finally {
        store.close();
      }
    },
  );
  test(
    'same title and reused library ID with another version do not merge',
    () {
      final store = AnnotationRepository.open(path);
      try {
        final a = session(store),
            b = session(store, 'local:2:version-a'),
            c = session(store, 'local:1:version-b');
        a.add(page(a), AnnotationKind.bookmark, '版本一');
        expect({a.documentId, b.documentId, c.documentId}, hasLength(3));
        expect(b.all, isEmpty);
        expect(c.all, isEmpty);
      } finally {
        store.close();
      }
    },
  );
  test('source identity survives reordering and storage-root relocation', () {
    final store = AnnotationRepository.open(path);
    try {
      final a = AnnotationSession.persistent(
        store,
        libraryKey: 'book',
        title: 'Book',
        sourceIdentityOf: (uri) => Uri.parse(uri).path.split('/').last,
      );
      final first = a.anchor(
        chapterId: 'one',
        imageNumber: 1,
        width: 100,
        height: 200,
        sourceIdentity: 'file:///old/001.png',
      );
      a.add(first, AnnotationKind.pageNote, '定位');
      final b = AnnotationSession.persistent(
        store,
        libraryKey: 'book',
        title: 'Renamed',
        sourceIdentityOf: (uri) => Uri.parse(uri).path.split('/').last,
      );
      final relocated = b.anchor(
        chapterId: 'one',
        imageNumber: 3,
        width: 100,
        height: 200,
        sourceIdentity: 'file:///new/001.png',
      );
      expect(first.pageId, relocated.pageId);
      expect(b.forPage(relocated).single.text, '定位');
      expect(
        store.db
            .select('SELECT display_cache_uri FROM source_pages')
            .single['display_cache_uri'],
        'file:///new/001.png',
      );
    } finally {
      store.close();
    }
  });
  test('missing source files never erase persisted annotations', () {
    final store = AnnotationRepository.open(path);
    try {
      final a = session(store);
      a.add(page(a), AnnotationKind.pageNote, '来源可以失联');
      final b = session(store);
      expect(b.all.single.text, '来源可以失联');
      expect(File('/missing/one/001.png').existsSync(), isFalse);
      expect(b.forPage(page(b)), hasLength(1));
    } finally {
      store.close();
    }
  });
  test(
    'changed source dimensions are rejected without losing previous notes',
    () {
      final store = AnnotationRepository.open(path);
      try {
        final a = session(store), p = page(a);
        a.add(p, AnnotationKind.bookmark, '保留');
        expect(
          () => a.anchor(
            chapterId: 'one',
            imageNumber: 1,
            width: 200,
            height: 400,
            sourceIdentity: 'one/001.png',
          ),
          throwsStateError,
        );
        expect(store.list(a.documentId).single.text, '保留');
      } finally {
        store.close();
      }
    },
  );
  test(
    '30 notes commit independently and recover with edits and tombstones',
    () {
      final store = AnnotationRepository.open(path);
      try {
        final a = session(store), p = page(a);
        final notes = List.generate(
          30,
          (i) => a.add(p, AnnotationKind.pageNote, '笔记 $i'),
        );
        for (final note in notes.take(5)) {
          a.update(note.id, '已编辑');
        }
        a.remove(notes.last.id);
        final b = session(store);
        expect(b.all, hasLength(29));
        expect(b.all.where((n) => n.text == '已编辑'), hasLength(5));
        expect(
          b.all.map((n) => n.id).toSet(),
          containsAll(notes.take(29).map((n) => n.id)),
        );
      } finally {
        store.close();
      }
    },
  );
  test('cross-document/page writes fail before changing session memory', () {
    final store = AnnotationRepository.open(path);
    try {
      final a = session(store), b = session(store, 'another');
      final p = page(a), q = page(b);
      final invalid = PageAnchor(
        documentId: a.documentId,
        pageId: q.pageId,
        chapterId: 'one',
        sourceImageNumber: 1,
        sourceWidth: 1000,
        sourceHeight: 2000,
      );
      expect(
        () => a.add(invalid, AnnotationKind.pageNote, '错误页'),
        throwsA(isA<SqliteException>()),
      );
      expect(a.all, isEmpty);
      expect(store.list(a.documentId), isEmpty);
      final note = a.add(p, AnnotationKind.pageNote, '原页');
      expect(
        () => store.put(
          Annotation(
            id: note.id,
            anchor: q,
            kind: AnnotationKind.pageNote,
            text: '非法移动',
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
          ),
        ),
        throwsArgumentError,
      );
      expect(store.list(a.documentId).single.text, '原页');
    } finally {
      store.close();
    }
  });
  test('failed UPDATE and DELETE preserve the in-memory working set', () {
    final store = AnnotationRepository.open(path);
    try {
      final a = session(store),
          note = a.add(page(a), AnnotationKind.pageNote, '原文字');
      store.db.execute(
        "CREATE TRIGGER fail_update BEFORE UPDATE ON annotations BEGIN SELECT RAISE(ABORT,'disk failure'); END",
      );
      expect(() => a.update(note.id, '新文字'), throwsA(isA<SqliteException>()));
      expect(a.all.single.text, '原文字');
      expect(() => a.remove(note.id), throwsA(isA<SqliteException>()));
      expect(a.all.single.id, note.id);
    } finally {
      store.close();
    }
  });
  test('newer schemas are rejected untouched', () {
    final db = sqlite3.open(path)..userVersion = 99;
    try {
      expect(() => AnnotationRepository(db), throwsStateError);
      expect(db.userVersion, 99);
      expect(
        db.select("SELECT name FROM sqlite_master WHERE type='table'"),
        isEmpty,
      );
    } finally {
      db.dispose();
    }
  });
  test('failed migration rolls back schema and version as one transaction', () {
    final db = sqlite3.open(path)
      ..execute('CREATE TABLE source_pages(existing TEXT)');
    try {
      expect(() => AnnotationRepository(db), throwsA(isA<SqliteException>()));
      expect(db.userVersion, 0);
      expect(
        db
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map((r) => r['name']),
        ['source_pages'],
      );
    } finally {
      db.dispose();
    }
  });
  test('SQL constraints reject out-of-bounds persisted rectangles', () {
    final store = AnnotationRepository.open(path);
    try {
      final a = session(store), p = page(a);
      expect(
        () => store.db.execute(
          '''INSERT INTO annotations(annotation_id,document_id,page_id,kind,x0,y0,x1,y1,note_text,created_at,updated_at)
        VALUES('invalid',?,?,'region',-0.1,0,0.5,1,'',0,0)''',
          [a.documentId, p.pageId],
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(a.all, isEmpty);
    } finally {
      store.close();
    }
  });
  test(
    'returning to an existing session refreshes changes and deletions from another reader',
    () {
      final store = AnnotationRepository.open(path);
      try {
        final first = session(store), p = page(first);
        final note = first.add(p, AnnotationKind.pageNote, '初始笔记');
        final second = session(store);
        first.selectedId = note.id;
        second.update(note.id, '另一阅读器更新');
        first.refresh();
        expect(first.all.single.text, '另一阅读器更新');
        expect(first.selectedId, note.id);
        second.remove(note.id);
        first.refresh();
        expect(first.all, isEmpty);
        expect(first.selectedId, isNull);
      } finally {
        store.close();
      }
    },
  );
}
