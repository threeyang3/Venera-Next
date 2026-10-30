import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:venera_next/app_runtime/annotation_assets.dart';
import 'package:venera_next/app_runtime/annotations.dart';
import 'package:venera_next/app_runtime/annotation_recovery.dart';
import 'package:venera_next/app_runtime/annotation_navigation.dart';
import 'package:venera_next/app_runtime/annotation_source_relocation.dart';
import 'package:venera_next/features/annotations/application/annotation_export_service.dart';
import 'package:venera_next/features/annotations/application/annotation_session.dart';
import 'package:venera_next/features/annotations/domain/annotation.dart';
import 'package:venera_next/features/comic_storage/comic_storage.dart';
import 'package:venera_next/features/local_comics/import_export/comic_import_service.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/features/favorites/favorites_manager.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/annotation_link_contract.dart';
import 'package:venera_next/foundation/comic_source_provenance.dart';
import 'package:venera_next/foundation/folder_source_provenance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const service = ComicImportService(
    localManager: LocalManager.new,
    favoritesManager: LocalFavoritesManager.new,
  );
  late Directory root, source;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('folder-source-');
    App.dataPath = (Directory(p.join(root.path, 'data'))..createSync()).path;
    App.cachePath = (Directory(p.join(root.path, 'cache'))..createSync()).path;
    LocalManager.current?.dispose();
    await LocalManager(initializeSources: () async {}).init();
    source = Directory(p.join(root.path, 'source', 'Book'))
      ..createSync(recursive: true);
    for (final (path, color) in [
      ('cover.png', 100),
      ('第1章/1.png', 20),
      ('第1章/2.png', 40),
      ('第2章/1.png', 60),
    ]) {
      final file = File(p.join(source.path, path));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(
        image.encodePng(
          image.Image(width: 12, height: 16)
            ..clear(image.ColorRgb8(color, 34, 56)),
        ),
      );
    }
  });
  tearDown(() async {
    await LocalManager().pendingDownloadTaskWrites;
    LocalManager.current?.dispose();
    root.deleteSync(recursive: true);
  });
  AnnotationSession open(LocalComic comic) => openLocalAnnotationSession(
    libraryKey: 'local:${comic.id}:${comic.createdAt.millisecondsSinceEpoch}',
    title: comic.title,
    sourceRoot: comic.baseDir,
  );
  Future<LocalComic> import(Directory directory, bool copy) async {
    final result = await service.runImport(
      (op) => op.directory(directory, single: true, copy: copy),
    );
    expect(result.succeeded, isTrue);
    expect(result.importedCount, 1);
    expect(
      result.issues,
      isEmpty,
      reason: result.issues
          .map((issue) => '${issue.kind}: ${issue.error}')
          .join('\n'),
    );
    return LocalManager().getComics(LocalSortType.name).single;
  }

  test(
    'folder identity ignores absolute location and cover but preserves relative paths and bytes',
    () async {
      final receipt = await captureComicFolderSource(source);
      expect(receipt.pages.keys.toSet(), {
        '第1章/1.png',
        '第1章/2.png',
        '第2章/1.png',
      });
      File(
        p.join(source.path, 'cover.png'),
      ).writeAsStringSync('different thumbnail');
      expect(
        (await captureComicFolderSource(source)).source['sha256'],
        receipt.source['sha256'],
      );
      final moved = await source.rename(p.join(root.path, 'Moved'));
      final after = await captureComicFolderSource(moved);
      expect(after.source['sha256'], receipt.source['sha256']);
      expect(after.source['uri'], isNot(receipt.source['uri']));
      File(
        p.join(moved.path, '第1章', '2.png'),
      ).renameSync(p.join(moved.path, '第1章', '3.png'));
      expect(
        (await captureComicFolderSource(moved)).source['sha256'],
        isNot(receipt.source['sha256']),
      );
    },
  );
  test(
    'folder image links outside the selected directory cannot establish provenance',
    () async {
      final external = File(p.join(root.path, 'outside.png'))
        ..writeAsStringSync('outside');
      Link(p.join(source.path, '第1章', '3.png')).createSync(external.path);
      await expectLater(
        captureComicFolderSource(source),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
  for (final copy in [false, true]) {
    test(
      'real folder import, original export, reimport and old citation recovery; copy=$copy',
      () async {
        final before = source
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => p.relative(f.path, from: source.path))
            .toSet();
        final comic = await import(source, copy);
        expect(
          source
              .listSync(recursive: true)
              .whereType<File>()
              .map((f) => p.relative(f.path, from: source.path))
              .toSet(),
          before,
        );
        expect(
          File(
            p.join(source.path, ComicSourceProvenance.filename),
          ).existsSync(),
          isFalse,
        );
        final key =
            'local:${comic.id}:${comic.createdAt.millisecondsSinceEpoch}';
        final receipt = ComicSourceProvenance.readFile(
          folderSourceReceiptFile(App.dataPath, key),
        )!;
        expect(receipt.source['kind'], 'folder');
        final session = open(comic);
        final page = session.anchor(
          chapterId: '第1章',
          imageNumber: 2,
          width: 12,
          height: 16,
          sourceIdentity: 'file://${p.join(comic.baseDir, '第1章', '2.png')}',
        );
        final note = session.add(
          page,
          AnnotationKind.pageNote,
          'Original folder note',
        );
        session.setTags(note.id, ['构图']);
        final oldId = session.documentId;
        if (copy) await source.delete(recursive: true);
        final original = await resolveLocalAnnotationImage(session, note);
        expect(original.quality, AnnotationImageQuality.original);
        expect(original.provenance!['kind'], 'folderImageOriginal');
        final next = Directory(p.join(root.path, 'Reimport'))..createSync();
        for (final identity in receipt.pages.keys) {
          final target = File(p.join(next.path, identity));
          await target.parent.create(recursive: true);
          await File(p.join(comic.baseDir, identity)).copy(target.path);
        }
        session.close();
        LocalManager().remove(comic.id, comic.comicType);
        await Directory(comic.baseDir).delete(recursive: true);
        final replacement = await import(next, copy);
        final target = open(replacement);
        try {
          expect(
            (await findRecoverableAnnotations(
              session: target,
            )).single.documentId,
            oldId,
          );
          expect(
            await recoverLocalAnnotations(
              session: target,
              documentId: oldId,
              isCurrent: () => true,
            ),
            isTrue,
          );
        } finally {
          target.close();
        }
        final restored = open(replacement);
        try {
          expect(restored.documentId, oldId);
          expect(restored.all.single.id, note.id);
          expect(restored.all.single.anchor.pageId, page.pageId);
          expect(restored.all.single.tags, ['构图']);
          expect(
            (await resolveLocalAnnotationImage(
              restored,
              restored.all.single,
            )).bytes,
            original.bytes,
          );
          final link = await resolveLocalAnnotationLink(
            AnnotationLink(documentId: oldId, annotationId: note.id),
          );
          expect(link.comic.id, replacement.id);
          expect(link.location.chapter, 1);
          expect(link.location.imageNumber, 2);
        } finally {
          restored.close();
        }
      },
      skip: !const bool.fromEnvironment('COMICNOTES_POC'),
    );
  }
  test(
    'receipt persistence failure reports a warning without undoing imported comic',
    () async {
      File(
        p.join(App.dataPath, 'comicnotes-sources'),
      ).writeAsStringSync('blocks metadata directory');
      final result = await service.runImport(
        (op) => op.directory(source, single: true, copy: false),
      );
      expect(result.succeeded, isTrue);
      expect(result.importedCount, 1);
      expect(
        result.issues.single.kind,
        ComicImportIssueKind.annotationSourceFailed,
      );
      final comic = LocalManager().getComics(LocalSortType.name).single;
      final session = open(comic);
      try {
        expect(session.sourceDocument!.source, isNull);
      } finally {
        session.close();
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  test(
    'folder relocation validates complete manifest, exports missing old path, and refuses changed bytes',
    () async {
      final comic = await import(source, false);
      final session = open(comic);
      try {
        final page = session.anchor(
          chapterId: '第1章',
          imageNumber: 1,
          width: 12,
          height: 16,
          sourceIdentity: 'file://${p.join(comic.baseDir, '第1章', '1.png')}',
        );
        final note = session.add(page, AnnotationKind.pageNote, 'Move');
        final expected = await resolveLocalAnnotationImage(session, note);
        final moved = await source.rename(p.join(root.path, 'Moved'));
        expect(
          await relocateAnnotationFolder(session, moved, isCurrent: () => true),
          isTrue,
        );
        expect(
          (await resolveLocalAnnotationImage(session, note)).bytes,
          expected.bytes,
        );
        final uri = session.sourceDocument!.source!.uri;
        final changed = File(p.join(moved.path, '第1章', '1.png'));
        final bytes = changed.readAsBytesSync();
        bytes[bytes.length - 1] ^= 1;
        changed.writeAsBytesSync(bytes);
        await expectLater(
          relocateAnnotationFolder(session, moved, isCurrent: () => true),
          throwsStateError,
        );
        expect(session.sourceDocument!.source!.uri, uri);
        await expectLater(
          resolveLocalAnnotationImage(session, note),
          throwsA(isA<FileSystemException>()),
        );
        expect(session.sourceDocument!.status, 'changed');
        expect(session.all.single.id, note.id);
      } finally {
        session.close();
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );
}
