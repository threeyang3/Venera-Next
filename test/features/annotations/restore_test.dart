import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/annotations/application/annotation_export_service.dart';
import 'package:venera_next/features/annotations/application/annotation_session.dart';
import 'package:venera_next/features/annotations/data/annotation_backup.dart';
import 'package:venera_next/features/annotations/data/annotation_repository.dart';
import 'package:venera_next/features/annotations/data/annotation_restore.dart';
import 'package:venera_next/features/annotations/domain/annotation.dart';

void main() {
  late Directory root;
  late AnnotationRepository source;
  late AnnotationRepository target;
  late AnnotationSession session;
  late String backup;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('restore-test-');
    source = AnnotationRepository.open('${root.path}/source.db');
    target = AnnotationRepository.open('${root.path}/target.db');
    session = AnnotationSession.persistent(
      source,
      libraryKey: 'local:1:1',
      title: 'Book',
    );
    final page = session.anchor(
      chapterId: '1',
      imageNumber: 1,
      width: 100,
      height: 200,
    );
    final note = session.add(page, AnnotationKind.pageNote, 'Backup note');
    session.setTags(note.id, ['构图']);
    final deleted = session.add(page, AnnotationKind.bookmark, 'Deleted');
    session.remove(deleted.id);
    backup = await backupAnnotationDatabase(
      databasePath: '${root.path}/source.db',
      destination: root.path,
    );
  });
  tearDown(() {
    source.close();
    target.close();
    root.deleteSync(recursive: true);
  });
  Future<void> rehash() async {
    final file = File('$backup/backup.json');
    final manifest = jsonDecode(file.readAsStringSync()) as Map;
    manifest['sha256'] = sha256
        .convert(File('$backup/annotations.db').readAsBytesSync())
        .toString();
    file.writeAsStringSync(jsonEncode(manifest));
  }

  test(
    'round trip preserves UUIDs, tags and tombstones without local-ID binding',
    () async {
      final preview = await prepareAnnotationRestore(
        backupDirectory: backup,
        databasePath: '${root.path}/target.db',
      );
      try {
        expect(preview.documentCount, 1);
        expect(preview.annotationCount, 1);
        expect(preview.existingDocumentCount, 0);
        final result = await preview.restore();
        expect(result.importedDocuments, 1);
        expect(
          target.list(session.documentId).single.id,
          session.all.single.id,
        );
        expect(target.list(session.documentId).single.tags, ['构图']);
        expect(
          target.document(session.documentId).libraryKey,
          'restored:${session.documentId}',
        );
        expect(
          target.db.select('SELECT COUNT(*) n FROM annotations').single['n'],
          2,
        );
        expect(target.db.select('PRAGMA foreign_key_check'), isEmpty);
        await expectLater(preview.restore(), throwsStateError);
      } finally {
        await preview.dispose();
      }
    },
  );
  test(
    'recheck existing UUID at commit keeps newer edits and deleted records',
    () async {
      final preview = await prepareAnnotationRestore(
        backupDirectory: backup,
        databasePath: '${root.path}/target.db',
      );
      final first = await prepareAnnotationRestore(
        backupDirectory: backup,
        databasePath: '${root.path}/target.db',
      );
      try {
        await first.restore();
        target.db.execute(
          "UPDATE annotations SET note_text='newer', deleted_at=123",
        );
        final result = await preview.restore();
        expect(result.importedDocuments, 0);
        expect(result.skippedDocuments, 1);
        expect(
          target.db
              .select('SELECT DISTINCT note_text FROM annotations')
              .single['note_text'],
          'newer',
        );
        expect(target.list(session.documentId), isEmpty);
      } finally {
        await preview.dispose();
        await first.dispose();
      }
    },
  );
  test(
    'preview uses verified private copy when selected backup changes later',
    () async {
      final preview = await prepareAnnotationRestore(
        backupDirectory: backup,
        databasePath: '${root.path}/target.db',
      );
      try {
        File('$backup/annotations.db').writeAsStringSync('mutated');
        await preview.restore();
        expect(target.list(session.documentId).single.text, 'Backup note');
      } finally {
        await preview.dispose();
      }
    },
  );
  test('tampered hash and count reject before writing target', () async {
    final manifestFile = File('$backup/backup.json');
    final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map;
    manifest['annotationCount'] = 999;
    manifestFile.writeAsStringSync(jsonEncode(manifest));
    await expectLater(
      prepareAnnotationRestore(
        backupDirectory: backup,
        databasePath: '${root.path}/target.db',
      ),
      throwsFormatException,
    );
    File('$backup/annotations.db').writeAsStringSync('broken');
    await expectLater(
      prepareAnnotationRestore(
        backupDirectory: backup,
        databasePath: '${root.path}/target.db',
      ),
      throwsFormatException,
    );
    expect(target.documents(), isEmpty);
  });
  test('source triggers are rejected even with a matching hash', () async {
    final bad = AnnotationRepository.open('$backup/annotations.db');
    bad.db.execute(
      'CREATE TRIGGER bad AFTER INSERT ON annotation_tags BEGIN DELETE FROM annotations; END',
    );
    bad.close();
    await rehash();
    await expectLater(
      prepareAnnotationRestore(
        backupDirectory: backup,
        databasePath: '${root.path}/target.db',
      ),
      throwsFormatException,
    );
    expect(target.documents(), isEmpty);
  });
  test(
    'version 1 backup restores without source_size or modifying selected backup',
    () async {
      final old = AnnotationRepository.open('$backup/annotations.db');
      old.db.execute('ALTER TABLE source_documents DROP COLUMN source_size');
      old.db.userVersion = 1;
      old.close();
      final manifestFile = File('$backup/backup.json');
      final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map;
      manifest['schemaVersion'] = 1;
      manifestFile.writeAsStringSync(jsonEncode(manifest));
      await rehash();
      final before = File('$backup/annotations.db').readAsBytesSync();
      final preview = await prepareAnnotationRestore(
        backupDirectory: backup,
        databasePath: '${root.path}/target.db',
      );
      try {
        await preview.restore();
        expect(target.list(session.documentId).single.text, 'Backup note');
        expect(File('$backup/annotations.db').readAsBytesSync(), before);
      } finally {
        await preview.dispose();
      }
    },
  );
  test(
    'nonfinite source dimensions reject even with matching manifest',
    () async {
      final bad = AnnotationRepository.open('$backup/annotations.db');
      bad.db.execute('UPDATE source_pages SET source_width=1e999');
      bad.close();
      await rehash();
      await expectLater(
        prepareAnnotationRestore(
          backupDirectory: backup,
          databasePath: '${root.path}/target.db',
        ),
        throwsFormatException,
      );
      expect(target.documents(), isEmpty);
    },
  );
  test('cross-document page collision rolls back all imported rows', () async {
    final existing = AnnotationSession.persistent(
      target,
      libraryKey: 'another',
      title: 'Existing',
    );
    final page = existing.anchor(
      chapterId: '1',
      imageNumber: 1,
      width: 100,
      height: 200,
    );
    final oldPage = source.pages(session.documentId).single.anchor.pageId;
    target.db.execute('UPDATE source_pages SET page_id=? WHERE page_id=?', [
      oldPage,
      page.pageId,
    ]);
    final preview = await prepareAnnotationRestore(
      backupDirectory: backup,
      databasePath: '${root.path}/target.db',
    );
    try {
      await expectLater(preview.restore(), throwsA(isA<Exception>()));
      expect(target.documents().single.documentId, existing.documentId);
      expect(target.db.select('SELECT * FROM annotations'), isEmpty);
    } finally {
      await preview.dispose();
    }
  });
  test(
    'cancellation inside transaction rolls back document insertion',
    () async {
      final preview = await prepareAnnotationRestore(
        backupDirectory: backup,
        databasePath: '${root.path}/target.db',
      );
      var checks = 0;
      try {
        await expectLater(
          preview.restore(isCancelled: () => ++checks > 2),
          throwsA(isA<AnnotationExportCancelled>()),
        );
        expect(target.documents(), isEmpty);
      } finally {
        await preview.dispose();
      }
    },
  );
}
