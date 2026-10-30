import 'dart:io';
import 'package:archive/archive_io.dart' as archive;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:venera_next/app_runtime/annotation_manual_recovery.dart';
import 'package:venera_next/app_runtime/annotation_navigation.dart';
import 'package:venera_next/app_runtime/annotations.dart';
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
  late File archiveFile;
  late LocalComic previous, replacement;
  late String previousId;
  late Annotation note;
  late AnnotationSession session;
  AnnotationSession open(LocalComic comic) => openLocalAnnotationSession(
    libraryKey: 'local:${comic.id}:${comic.createdAt.millisecondsSinceEpoch}',
    title: comic.title,
    sourceRoot: comic.baseDir,
  );
  Future<LocalComic> import() => CBZ.import(
    archiveFile,
    registerComic: (comic) => LocalManager().add(comic, comic.id),
  );
  setUp(() async {
    root = Directory.systemTemp.createTempSync('manual-recovery-runtime-');
    App.dataPath = root.path;
    App.cachePath = (Directory(p.join(root.path, 'cache'))..createSync()).path;
    LocalManager.current?.dispose();
    await LocalManager(initializeSources: () async {}).init();
    final zip = archive.Archive();
    for (var i = 1; i <= 2; i++) {
      final bytes = image.encodePng(
        image.Image(width: 20, height: 30)
          ..clear(image.ColorRgb8(i * 60, 30, 120)),
      );
      zip.addFile(archive.ArchiveFile('pages/$i.png', bytes.length, bytes));
    }
    archiveFile = File(p.join(root.path, 'Book.cbz'))
      ..writeAsBytesSync(archive.ZipEncoder().encodeBytes(zip));
    previous = await import();
    final old = open(previous);
    previousId = old.documentId;
    for (var i = 1; i <= 2; i++) {
      final page = old.anchor(
        chapterId: '0',
        imageNumber: i,
        width: 20,
        height: 30,
        sourceIdentity: 'file://${p.join(previous.baseDir, '$i.png')}',
      );
      final saved = old.add(
        page,
        AnnotationKind.region,
        'Old $i',
        rect: ContentRect(.1, .2, .8, .9),
      );
      if (i == 1) {
        note = saved;
        old.setTags(saved.id, ['legacy']);
      } else {
        old.remove(saved.id);
      }
    }
    old.close();
    final store = AnnotationRepository.open(
      p.join(root.path, 'annotations.db'),
    );
    store.db.execute(
      "UPDATE source_documents SET source_hash=NULL,source_size=NULL,source_uri=NULL,kind='local' WHERE document_id=?",
      [previousId],
    );
    store.close();
    LocalManager().remove(previous.id, previous.comicType);
    Directory(previous.baseDir).deleteSync(recursive: true);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    replacement = await import();
    session = open(replacement);
  });
  tearDown(() async {
    session.close();
    await LocalManager().pendingDownloadTaskWrites;
    LocalManager.current?.dispose();
    root.deleteSync(recursive: true);
  });
  test(
    'verified manual preview restores orphan without fingerprint and old link remains valid',
    () async {
      final candidates = await findManualAnnotationRecovery(session: session);
      expect(candidates.single.documentId, previousId);
      final preview = (await prepareManualAnnotationRecovery(
        session: session,
        documentId: previousId,
        isCurrent: () => true,
      ))!;
      try {
        expect(preview.previous.source, isNull);
        expect(preview.previousPages, hasLength(2));
        expect(preview.annotations.single.tags, ['legacy']);
        expect(preview.targets, hasLength(2));
        for (final target in preview.targets) {
          final png = image.decodePng(target.thumbnail)!;
          expect(png.height, 192);
          expect(target.page.anchor.sourceWidth, 20);
          expect(target.page.anchor.sourceHeight, 30);
        }
        final mapping = {
          for (final page in preview.previousPages)
            page.anchor.pageId: preview.targets
                .singleWhere(
                  (target) =>
                      target.page.anchor.sourceImageNumber ==
                      page.anchor.sourceImageNumber,
                )
                .page
                .anchor
                .pageId,
        };
        expect(
          await preview.commit(pageMapping: mapping, isCurrent: () => true),
          isTrue,
        );
        expect(
          await preview.commit(pageMapping: mapping, isCurrent: () => true),
          isFalse,
        );
        final reopened = open(replacement);
        try {
          expect(reopened.documentId, previousId);
          expect(reopened.all.single.id, note.id);
          expect(reopened.all.single.rect!.toJson(), note.rect!.toJson());
          final destination = await resolveAnnotationLinkDestination(
            AnnotationLink(documentId: previousId, annotationId: note.id),
          );
          expect(destination.comicId, replacement.id);
          expect(destination.imageNumber, 1);
        } finally {
          reopened.close();
        }
      } finally {
        await preview.dispose();
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );
  for (final change in [
    'bytes',
    'symlink',
    'list',
    'oldLive',
    'newNote',
    'oldNote',
    'cancel',
    'disposed',
  ]) {
    test(
      'manual preview refuses changed $change without altering old binding',
      () async {
        final preview = (await prepareManualAnnotationRecovery(
          session: session,
          documentId: previousId,
          isCurrent: () => true,
        ))!;
        final mapping = {
          for (final page in preview.previousPages)
            page.anchor.pageId: preview.targets
                .singleWhere(
                  (target) =>
                      target.page.anchor.sourceImageNumber ==
                      page.anchor.sourceImageNumber,
                )
                .page
                .anchor
                .pageId,
        };
        try {
          final target = preview.targets.first;
          final file = File(target.page.assetUri!.substring(7));
          switch (change) {
            case 'bytes':
              file.writeAsBytesSync(
                image.encodePng(image.Image(width: 20, height: 30)),
              );
            case 'symlink':
              final outside = File(p.join(root.path, 'outside.png'))
                ..writeAsBytesSync(file.readAsBytesSync());
              file.deleteSync();
              Link(file.path).createSync(outside.path);
            case 'list':
              File(
                p.join(replacement.baseDir, 'extra.png'),
              ).writeAsBytesSync(file.readAsBytesSync());
            case 'oldLive':
              await LocalManager().add(previous, previous.id);
            case 'newNote':
              session.add(
                target.page.anchor,
                AnnotationKind.pageNote,
                'New note',
              );
            case 'oldNote':
              final store = AnnotationRepository.open(
                p.join(root.path, 'annotations.db'),
              );
              store.put(
                store
                    .list(previousId)
                    .single
                    .withText('Newer old note', DateTime.now()),
              );
              store.close();
            case 'cancel':
              break;
            case 'disposed':
              await preview.dispose();
          }
          if (['cancel', 'disposed', 'oldLive'].contains(change)) {
            expect(
              await preview.commit(
                pageMapping: mapping,
                isCurrent: () => change != 'cancel',
              ),
              isFalse,
            );
          } else {
            await expectLater(
              preview.commit(pageMapping: mapping, isCurrent: () => true),
              throwsA(anything),
            );
          }
          final store = AnnotationRepository.open(
            p.join(root.path, 'annotations.db'),
          );
          try {
            expect(
              store.document(previousId).libraryKey,
              'local:${previous.id}:${previous.createdAt.millisecondsSinceEpoch}',
            );
            expect(store.list(previousId).single.id, note.id);
            expect(
              store.document(session.documentId).libraryKey,
              'local:${replacement.id}:${replacement.createdAt.millisecondsSinceEpoch}',
            );
          } finally {
            store.close();
          }
        } finally {
          await preview.dispose();
        }
      },
      skip: !const bool.fromEnvironment('COMICNOTES_POC'),
    );
  }
  test(
    'disposing an in-flight commit drains it without moving the old binding',
    () async {
      final preview = (await prepareManualAnnotationRecovery(
        session: session,
        documentId: previousId,
        isCurrent: () => true,
      ))!;
      final mapping = {
        for (final page in preview.previousPages)
          page.anchor.pageId: preview.targets
              .singleWhere(
                (target) =>
                    target.page.anchor.sourceImageNumber ==
                    page.anchor.sourceImageNumber,
              )
              .page
              .anchor
              .pageId,
      };
      final commit = preview.commit(
        pageMapping: mapping,
        isCurrent: () => true,
      );
      await preview.dispose();
      expect(await commit, isFalse);
      await preview.dispose();
      final store = AnnotationRepository.open(
        p.join(root.path, 'annotations.db'),
      );
      try {
        expect(
          store.document(previousId).libraryKey,
          'local:${previous.id}:${previous.createdAt.millisecondsSinceEpoch}',
        );
      } finally {
        store.close();
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  for (final invalid in ['missing', 'receiptChanged', 'corrupt', 'oldLive']) {
    test(
      'prepare rejects $invalid before changing old document',
      () async {
        final file = File(p.join(replacement.baseDir, '1.png'));
        switch (invalid) {
          case 'missing':
            file.deleteSync();
          case 'receiptChanged':
            file.writeAsBytesSync(
              image.encodePng(image.Image(width: 20, height: 30)),
            );
          case 'corrupt':
            file.writeAsBytesSync([1, 2, 3]);
          case 'oldLive':
            await LocalManager().add(previous, previous.id);
        }
        await expectLater(
          prepareManualAnnotationRecovery(
            session: session,
            documentId: previousId,
            isCurrent: () => true,
          ),
          throwsA(anything),
        );
        final store = AnnotationRepository.open(
          p.join(root.path, 'annotations.db'),
        );
        try {
          expect(store.list(previousId).single.id, note.id);
        } finally {
          store.close();
        }
      },
      skip: !const bool.fromEnvironment('COMICNOTES_POC'),
    );
  }
  test(
    'cancelling after image decode leaves old binding and permits a fresh preview',
    () async {
      var checks = 0;
      expect(
        await prepareManualAnnotationRecovery(
          session: session,
          documentId: previousId,
          isCurrent: () => ++checks < 3,
        ),
        isNull,
      );
      final next = await prepareManualAnnotationRecovery(
        session: session,
        documentId: previousId,
        isCurrent: () => true,
      );
      expect(next, isNotNull);
      await next!.dispose();
      final store = AnnotationRepository.open(
        p.join(root.path, 'annotations.db'),
      );
      try {
        expect(
          store.document(previousId).libraryKey,
          'local:${previous.id}:${previous.createdAt.millisecondsSinceEpoch}',
        );
      } finally {
        store.close();
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  test(
    'cancelled prepare has no effect on old notes',
    () async {
      expect(
        await prepareManualAnnotationRecovery(
          session: session,
          documentId: previousId,
          isCurrent: () => false,
        ),
        isNull,
      );
      final store = AnnotationRepository.open(
        p.join(root.path, 'annotations.db'),
      );
      try {
        expect(store.list(previousId).single.id, note.id);
      } finally {
        store.close();
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );
}
