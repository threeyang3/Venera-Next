import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/features/annotations/application/annotation_session.dart';
import 'package:venera_next/features/annotations/application/annotation_export_service.dart';
import 'package:venera_next/features/annotations/data/annotation_backup.dart';
import 'package:venera_next/features/annotations/data/annotation_repository.dart';
import 'package:venera_next/features/annotations/domain/annotation.dart';
import 'package:venera_next/features/annotations/domain/source_document.dart';

void main() {
  late Directory root;
  late AnnotationRepository store;
  late String databasePath;
  setUp(() {
    root = Directory.systemTemp.createTempSync('annotation-backup-');
    databasePath = '${root.path}/live.db';
    store = AnnotationRepository.open(databasePath);
    store.db.execute('PRAGMA journal_mode=WAL');
  });
  tearDown(() {
    store.close();
    root.deleteSync(recursive: true);
  });

  test(
    'backup captures committed WAL notes, tags, tombstones and source locators across all documents',
    () async {
      final session = AnnotationSession.persistent(
        store,
        libraryKey: 'local:1:1',
        title: 'Book',
        documentSource: const AnnotationDocumentSource(
          kind: 'archive',
          uri: 'file:///missing.cbz',
          sha256: 'original-hash',
          size: 12,
        ),
        pageLocatorOf: (_) => {
          'kind': 'archiveImage',
          'extractedEntry': 'Vol 1/001.jpg',
          'sha256': 'page-hash',
          'size': 8,
        },
      );
      final page = session.anchor(
        chapterId: '1',
        imageNumber: 1,
        width: 100,
        height: 200,
        sourceIdentity: '1.jpg',
      );
      final kept = session.add(page, AnnotationKind.pageNote, 'Live WAL note');
      session.setTags(kept.id, ['构图']);
      final deleted = session.add(page, AnnotationKind.bookmark, 'Tombstone');
      session.remove(deleted.id);
      final second = AnnotationSession.persistent(
        store,
        libraryKey: 'local:2:1',
        title: 'Orphan book',
      );
      second.add(
        second.anchor(chapterId: '1', imageNumber: 1, width: 100, height: 200),
        AnnotationKind.bookmark,
        'Other book',
      );
      expect(File('$databasePath-wal').lengthSync(), greaterThan(0));
      final output = await backupAnnotationDatabase(
        databasePath: databasePath,
        destination: root.path,
      );
      final manifest = jsonDecode(
        File('$output/backup.json').readAsStringSync(),
      );
      expect(manifest['documentCount'], 2);
      expect(manifest['annotationCount'], 2);
      expect(manifest['includesImages'], false);
      expect(
        manifest['sha256'],
        sha256
            .convert(File('$output/annotations.db').readAsBytesSync())
            .toString(),
      );
      final copy = AnnotationRepository.open('$output/annotations.db');
      try {
        expect(copy.list(session.documentId).single.id, kept.id);
        expect(copy.list(session.documentId).single.tags, ['构图']);
        expect(copy.list(second.documentId).single.text, 'Other book');
        expect(
          copy
              .sourcePage(session.documentId, page.pageId)!
              .locator['extractedEntry'],
          'Vol 1/001.jpg',
        );
        expect(
          copy.document(session.documentId).source!.uri,
          'file:///missing.cbz',
        );
        expect(
          copy.db.select(
            'SELECT deleted_at FROM annotations WHERE annotation_id=?',
            [deleted.id],
          ).single['deleted_at'],
          isNotNull,
        );
        expect(
          copy.db.select('PRAGMA integrity_check').single.values.single,
          'ok',
        );
      } finally {
        copy.close();
      }
      final another = await backupAnnotationDatabase(
        databasePath: databasePath,
        destination: root.path,
      );
      expect(another, isNot(output));
      expect(File('$output/backup.json').existsSync(), isTrue);
    },
  );

  test(
    'cancellation after snapshot removes staging without publishing or changing the live database',
    () async {
      var checks = 0;
      await expectLater(
        backupAnnotationDatabase(
          databasePath: databasePath,
          destination: root.path,
          isCancelled: () => ++checks > 1,
        ),
        throwsA(isA<AnnotationExportCancelled>()),
      );
      expect(root.listSync().whereType<Directory>(), isEmpty);
      expect(
        store.db.select('PRAGMA integrity_check').single.values.single,
        'ok',
      );
    },
  );

  test('unsupported and corrupt databases never publish a backup', () async {
    store.db.userVersion = 999;
    await expectLater(
      backupAnnotationDatabase(
        databasePath: databasePath,
        destination: root.path,
      ),
      throwsStateError,
    );
    final corrupt = File('${root.path}/corrupt.db')
      ..writeAsStringSync('broken');
    await expectLater(
      backupAnnotationDatabase(
        databasePath: corrupt.path,
        destination: root.path,
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(root.listSync().whereType<Directory>(), isEmpty);
  });
}
