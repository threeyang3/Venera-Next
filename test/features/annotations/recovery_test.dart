import 'dart:io';
import 'dart:convert';
import 'package:venera_next/features/annotations/data/annotation_backup.dart';
import 'package:venera_next/features/annotations/data/annotation_restore.dart';
import 'package:archive/archive_io.dart' as archive;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/app_runtime/annotations.dart';
import 'package:venera_next/app_runtime/annotation_recovery.dart';
import 'package:venera_next/app_runtime/annotation_navigation.dart';
import 'package:venera_next/features/annotations/application/annotation_session.dart';
import 'package:venera_next/features/annotations/data/annotation_repository.dart';
import 'package:venera_next/features/annotations/domain/annotation.dart';
import 'package:venera_next/features/annotations/domain/geometry.dart';
import 'package:venera_next/features/local_comics/import_export/cbz.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/annotation_link_contract.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late File source;
  late LocalComic previous;
  late Annotation note;
  late String previousDocumentId;
  AnnotationSession open(LocalComic comic) => openLocalAnnotationSession(
    libraryKey: 'local:${comic.id}:${comic.createdAt.millisecondsSinceEpoch}',
    title: comic.title,
    sourceRoot: comic.baseDir,
  );
  setUp(() async {
    root = Directory.systemTemp.createTempSync('annotation-recovery-');
    App.dataPath = root.path;
    App.cachePath = (Directory(p.join(root.path, 'cache'))..createSync()).path;
    LocalManager.current?.dispose();
    await LocalManager(initializeSources: () async {}).init();
    final zip = archive.Archive();
    final bytes = image.encodePng(
      image.Image(width: 12, height: 16)..clear(image.ColorRgb8(12, 34, 56)),
    );
    zip.addFile(archive.ArchiveFile('pages/1.png', bytes.length, bytes));
    source = File(p.join(root.path, 'Book.cbz'))
      ..writeAsBytesSync(archive.ZipEncoder().encodeBytes(zip));
    previous = await CBZ.import(
      source,
      registerComic: (comic) => LocalManager().add(comic, comic.id),
    );
    final old = open(previous);
    final page = old.anchor(
      chapterId: '0',
      imageNumber: 1,
      width: 12,
      height: 16,
      sourceIdentity: 'file://${p.join(previous.baseDir, '1.png')}',
    );
    note = old.add(
      page,
      AnnotationKind.region,
      'Preserve original',
      rect: ContentRect(.1, .2, .8, .9),
    );
    old.setTags(note.id, ['构图']);
    previousDocumentId = old.documentId;
    old.close();
  });
  tearDown(() async {
    await LocalManager().pendingDownloadTaskWrites;
    LocalManager.current?.dispose();
    root.deleteSync(recursive: true);
  });
  Future<LocalComic> reimport() async {
    // Same public registration-removal operation; annotation DB is independent.
    LocalManager().remove(previous.id, previous.comicType);
    Directory(previous.baseDir).deleteSync(recursive: true);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    return CBZ.import(
      source,
      registerComic: (comic) => LocalManager().add(comic, comic.id),
    );
  }

  test(
    'manual mapping audit survives subsequent identical-source recovery',
    () async {
      final store = AnnotationRepository.open(
        p.join(App.dataPath, 'annotations.db'),
      );
      final page = store.pages(previousDocumentId).single;
      final locator = {
        ...page.locator,
        'manualMapping': {'previousSourceIdentity': 'legacy/other.png'},
      };
      store.db.execute(
        'UPDATE source_pages SET source_locator_json=? WHERE page_id=?',
        [jsonEncode(locator), page.anchor.pageId],
      );
      store.close();
      final replacement = await reimport();
      final current = open(replacement);
      try {
        expect(
          await recoverLocalAnnotations(
            session: current,
            documentId: previousDocumentId,
            isCurrent: () => true,
          ),
          isTrue,
        );
        final verified = AnnotationRepository.open(
          p.join(App.dataPath, 'annotations.db'),
        );
        try {
          expect(
            verified.pages(previousDocumentId).single.locator['manualMapping'],
            locator['manualMapping'],
          );
          expect(verified.list(previousDocumentId).single.id, note.id);
        } finally {
          verified.close();
        }
      } finally {
        current.close();
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  test(
    'backup restored on a fresh installation rebinds verified source and preserves old links',
    () async {
      final database = p.join(root.path, 'annotations.db');
      final backup = await backupAnnotationDatabase(
        databasePath: database,
        destination: root.path,
      );
      File(database).deleteSync();
      final target = open(previous);
      final transientId = target.documentId;
      final preview = await prepareAnnotationRestore(
        backupDirectory: backup,
        databasePath: database,
      );
      try {
        final result = await preview.restore();
        expect(result.importedDocuments, 1);
        // Same local ID on a new installation does not attach old coordinates.
        target.refresh();
        expect(target.all, isEmpty);
        expect(target.documentId, transientId);
        final candidates = await findRecoverableAnnotations(session: target);
        expect(candidates.single.documentId, previousDocumentId);
        expect(
          await recoverLocalAnnotations(
            session: target,
            documentId: previousDocumentId,
            isCurrent: () => true,
          ),
          isTrue,
        );
      } finally {
        await preview.dispose();
        target.close();
      }
      final restored = open(previous);
      try {
        expect(restored.documentId, previousDocumentId);
        expect(restored.all.single.id, note.id);
        expect(restored.all.single.anchor.pageId, note.anchor.pageId);
        expect(restored.all.single.tags, ['构图']);
        expect(restored.all.single.rect!.toJson(), note.rect!.toJson());
        final link = await resolveLocalAnnotationLink(
          AnnotationLink(documentId: previousDocumentId, annotationId: note.id),
        );
        expect(link.comic.id, previous.id);
        expect(link.location.imageNumber, 1);
      } finally {
        restored.close();
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  test(
    'exact reimport recovers IDs, tags and old citation navigation after database reopen',
    () async {
      final comic = await reimport();
      final target = open(comic);
      final transientId = target.documentId;
      final candidates = await findRecoverableAnnotations(session: target);
      expect(candidates.single.documentId, previousDocumentId);
      expect(candidates.single.annotationCount, 1);
      expect(
        await recoverLocalAnnotations(
          session: target,
          documentId: previousDocumentId,
          isCurrent: () => true,
        ),
        isTrue,
      );
      target.close();
      final restored = open(comic);
      try {
        expect(restored.documentId, previousDocumentId);
        expect(restored.all.single.id, note.id);
        expect(restored.all.single.anchor.pageId, note.anchor.pageId);
        expect(restored.all.single.rect!.toJson(), note.rect!.toJson());
        expect(restored.all.single.tags, ['构图']);
        final link = await resolveLocalAnnotationLink(
          AnnotationLink(documentId: previousDocumentId, annotationId: note.id),
        );
        expect(link.comic.id, comic.id);
        expect(
          link.comic.createdAt.millisecondsSinceEpoch,
          comic.createdAt.millisecondsSinceEpoch,
        );
        expect(link.location.imageNumber, 1);
        final store = AnnotationRepository.open(
          p.join(root.path, 'annotations.db'),
        );
        try {
          expect(
            store.documents().any((d) => d.documentId == transientId),
            isFalse,
          );
        } finally {
          store.close();
        }
      } finally {
        restored.close();
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  for (final tombstone in [false, true]) {
    test(
      'target notes and tombstones reject recovery without losing either document; tombstone=$tombstone',
      () async {
        final comic = await reimport();
        final target = open(comic);
        addTearDown(target.close);
        final page = target.anchor(
          chapterId: '0',
          imageNumber: 1,
          width: 12,
          height: 16,
          sourceIdentity: 'file://${p.join(comic.baseDir, '1.png')}',
        );
        final current = target.add(
          page,
          AnnotationKind.pageNote,
          'Current notes',
        );
        if (tombstone) target.remove(current.id);
        await expectLater(
          recoverLocalAnnotations(
            session: target,
            documentId: previousDocumentId,
            isCurrent: () => true,
          ),
          throwsStateError,
        );
        final store = AnnotationRepository.open(
          p.join(root.path, 'annotations.db'),
        );
        try {
          expect(store.list(previousDocumentId).single.id, note.id);
          expect(
            store.document(target.documentId).documentId,
            target.documentId,
          );
        } finally {
          store.close();
        }
      },
      skip: !const bool.fromEnvironment('COMICNOTES_POC'),
    );
  }

  test(
    'changed image and retired recovery leave old identities untouched',
    () async {
      final comic = await reimport();
      final target = open(comic);
      addTearDown(target.close);
      final path = p.join(comic.baseDir, '1.png');
      File(path).writeAsBytesSync([1, 2, 3]);
      await expectLater(
        recoverLocalAnnotations(
          session: target,
          documentId: previousDocumentId,
          isCurrent: () => true,
        ),
        throwsStateError,
      );
      expect(
        await recoverLocalAnnotations(
          session: target,
          documentId: previousDocumentId,
          isCurrent: () => false,
        ),
        isFalse,
      );
      final store = AnnotationRepository.open(
        p.join(root.path, 'annotations.db'),
      );
      try {
        expect(
          store.document(previousDocumentId).libraryKey,
          'local:${previous.id}:${previous.createdAt.millisecondsSinceEpoch}',
        );
        expect(store.list(previousDocumentId).single.id, note.id);
      } finally {
        store.close();
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  test(
    'a document still registered in the library is never a recovery candidate',
    () async {
      final active = open(previous);
      addTearDown(active.close);
      await expectLater(
        findRecoverableAnnotations(session: active),
        throwsStateError,
      );
      await expectLater(
        recoverLocalAnnotations(
          session: active,
          documentId: previousDocumentId,
          isCurrent: () => true,
        ),
        throwsStateError,
      );
      expect(active.all.single.id, note.id);
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  test(
    'failure while publishing page mappings rolls back deleted transient slot and original binding',
    () async {
      final comic = await reimport();
      final target = open(comic);
      addTearDown(target.close);
      final store = AnnotationRepository.open(
        p.join(root.path, 'annotations.db'),
      );
      try {
        store.db.execute(
          "CREATE TRIGGER fail_recovery BEFORE UPDATE ON source_pages BEGIN SELECT RAISE(ABORT,'recovery write failure'); END",
        );
        await expectLater(
          recoverLocalAnnotations(
            session: target,
            documentId: previousDocumentId,
            isCurrent: () => true,
          ),
          throwsA(isA<SqliteException>()),
        );
        expect(
          store.document(target.documentId).libraryKey,
          target.sourceDocument!.libraryKey,
        );
        expect(
          store.document(previousDocumentId).libraryKey,
          'local:${previous.id}:${previous.createdAt.millisecondsSinceEpoch}',
        );
        expect(store.list(previousDocumentId).single.id, note.id);
        store.db.execute('DROP TRIGGER fail_recovery');
        expect(
          await recoverLocalAnnotations(
            session: target,
            documentId: previousDocumentId,
            isCurrent: () => true,
          ),
          isTrue,
        );
      } finally {
        store.close();
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );
}
