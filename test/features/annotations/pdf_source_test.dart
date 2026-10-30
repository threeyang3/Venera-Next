import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as image;
import 'package:venera_next/app_runtime/annotations.dart';
import 'package:venera_next/app_runtime/annotation_assets.dart';
import 'package:venera_next/app_runtime/annotation_pdf_assets.dart';
import 'package:venera_next/app_runtime/annotation_source_relocation.dart';
import 'package:venera_next/app_runtime/annotation_recovery.dart';
import 'package:venera_next/features/annotations/application/annotation_export_service.dart';
import 'package:venera_next/features/annotations/domain/annotation.dart';
import 'package:venera_next/features/annotations/domain/geometry.dart';
import 'package:venera_next/features/local_comics/import_export/pdf_import.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/comic_source_provenance.dart';
import 'package:venera_next/foundation/pdf_page_geometry.dart';
import 'package:venera_next/foundation/pdf_source_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory caseRoot;
  var sequence = 0;
  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('annotation-pdf-native-');
    final explicit = Platform.environment['PDFIUM_PATH'];
    final libraryName = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium.dylib'
        : 'libpdfium.so';
    final local = File(
      'build/native_assets/${Platform.operatingSystem}/$libraryName',
    );
    if (explicit != null) {
      Pdfrx.pdfiumModulePath = explicit;
    } else if (local.existsSync()) {
      Pdfrx.pdfiumModulePath = local.absolute.path;
    }
    await pdfrxInitialize(tmpPath: root.path);
  });
  tearDownAll(() async {
    await PdfrxEntryFunctions.instance.stopBackgroundWorker();
    root.deleteSync(recursive: true);
  });
  setUp(() async {
    caseRoot = Directory(p.join(root.path, 'case-${sequence++}'))..createSync();
    App.dataPath = caseRoot.path;
    App.cachePath = (Directory(
      p.join(caseRoot.path, 'cache'),
    )..createSync()).path;
    LocalManager.current?.dispose();
    await LocalManager(initializeSources: () async {}).init();
  });
  tearDown(() async {
    await LocalManager().pendingDownloadTaskWrites;
    LocalManager.current?.dispose();
  });
  Future<File> source([String fixture = 'pdf-crop-rotate']) => File(
    'test/fixtures/annotations/$fixture.pdf',
  ).copy(p.join(caseRoot.path, '图册 %20 示例.pdf'));
  for (final fixture in ['pdf-crop-rotate', 'pdf-mixed-boxes']) {
    test('real PDFium reads all boxes and rendered colors: $fixture', () async {
      final expected =
          jsonDecode(
                File(
                  'test/fixtures/annotations/$fixture.json',
                ).readAsStringSync(),
              )
              as List;
      final document = await PdfDocument.openFile(
        'test/fixtures/annotations/$fixture.pdf',
      );
      try {
        expect(document.pages.length, expected.length);
        for (var i = 0; i < expected.length; i++) {
          final page = document.pages[i];
          final geometry = await readPdfPageGeometry(document, i);
          final target = expected[i] as Map;
          expect(geometry.pageIndex, i);
          expect(geometry.rotation, target['rotation']);
          expect(geometry.mediaBox, target['mediaBox']);
          expect(geometry.cropBox, target['cropBox']);
          expect(geometry.effectiveBox, target['effectiveBox']);
          expect(geometry.width, target['widthPoints']);
          expect(geometry.height, target['heightPoints']);
          final rendered = (await page.render(
            fullWidth: page.width,
            fullHeight: page.height,
          ))!;
          try {
            final offset =
                ((rendered.height * .25).floor() * rendered.width +
                    (rendered.width * .25).floor()) *
                4;
            final rgb = target['topLeftRgb'] as List;
            expect(rendered.pixels[offset], rgb[2] * 255);
            expect(rendered.pixels[offset + 1], rgb[1] * 255);
            expect(rendered.pixels[offset + 2], rgb[0] * 255);
          } finally {
            rendered.dispose();
          }
        }
      } finally {
        await document.dispose();
      }
    });
    test(
      'imports real PDF provenance and exports direct original crops: $fixture',
      () async {
        final file = await source(fixture);
        final comic = await PdfComicImporter.import(file);
        final directory = Directory(
          p.join(LocalManager().path, comic.directory),
        );
        final receipt = ComicSourceProvenance.read(directory)!;
        expect(receipt.source['kind'], 'pdf');
        expect(receipt.source['uri'], file.uri.toString());
        final expected =
            jsonDecode(
                  File(
                    'test/fixtures/annotations/$fixture.json',
                  ).readAsStringSync(),
                )
                as List;
        final session = openLocalAnnotationSession(
          libraryKey: 'local:pdf:1',
          title: comic.title,
          sourceRoot: directory.path,
        );
        addTearDown(session.close);
        for (var i = 0; i < expected.length; i++) {
          final name = '${(i + 1).toString().padLeft(4, '0')}.jpg';
          final cache = image.decodeJpg(
            File(p.join(directory.path, name)).readAsBytesSync(),
          )!;
          final page = session.anchor(
            chapterId: '0',
            imageNumber: i + 1,
            width: cache.width.toDouble(),
            height: cache.height.toDouble(),
            sourceIdentity: 'file://${p.join(directory.path, name)}',
          );
          final note = session.add(
            page,
            AnnotationKind.region,
            'PDF original $i',
            rect: ContentRect(.35, .15, .85, .85),
          );
          final locator = session.sourcePage(page)!.locator;
          final geometry = PdfPageGeometry.fromJson(locator);
          expect(geometry.mediaBox, expected[i]['mediaBox']);
          final resolved = await resolveLocalAnnotationImage(
            session,
            note,
            isCancelled: () => session.inputActive,
          );
          expect(resolved.quality, AnnotationImageQuality.original);
          expect(resolved.alreadyCropped, isTrue);
          final crop = image.decodePng(resolved.bytes)!;
          final plan = PdfAnnotationCropPlan(geometry, note);
          expect((crop.width, crop.height), (plan.width, plan.height));
          for (final (sx, sy) in [(.4, .3), (.7, .3), (.4, .7), (.7, .7)]) {
            final pixel = crop.getPixel(
              (sx * plan.fullWidth).floor() - plan.x,
              (sy * plan.fullHeight).floor() - plan.y,
            );
            final cachePixel = cache.getPixel(
              (cache.width * sx).floor(),
              (cache.height * sy).floor(),
            );
            for (final channel in [
              image.Channel.red,
              image.Channel.green,
              image.Channel.blue,
            ]) {
              expect(
                pixel.getChannel(channel),
                closeTo(cachePixel.getChannel(channel), 8),
              );
            }
            final (x, y) = switch (geometry.rotation) {
              90 => (sy, 1 - sx),
              180 => (1 - sx, 1 - sy),
              270 => (1 - sy, sx),
              _ => (sx, sy),
            };
            final rgb = y < .5
                ? (x < .5 ? [255, 0, 0] : [0, 255, 0])
                : (x < .5 ? [0, 0, 255] : [255, 255, 0]);
            expect([pixel.r, pixel.g, pixel.b], rgb);
          }
        }
        final output =
            await AnnotationExportService(
              resolveImage: (note) =>
                  resolveLocalAnnotationImage(session, note),
            ).export(
              destination: caseRoot.path,
              documentId: session.documentId,
              title: comic.title,
              annotations: session.all,
            );
        final manifest = jsonDecode(
          File(p.join(output.directory, 'manifest.json')).readAsStringSync(),
        );
        expect(
          (manifest['assets'] as Map).values.every(
            (value) =>
                value['quality'] == 'original' &&
                value['source']['kind'] == 'pdfOriginalRender',
          ),
          isTrue,
        );
        expect(output.warnings, isEmpty);
      },
      skip: !const bool.fromEnvironment('COMICNOTES_POC'),
    );
  }

  test(
    'closing the source session during PDF resolution cancels without losing notes',
    () async {
      final file = await source();
      final comic = await PdfComicImporter.import(file);
      final directory = Directory(p.join(LocalManager().path, comic.directory));
      final session = openLocalAnnotationSession(
        libraryKey: 'local:pdf:1',
        title: comic.title,
        sourceRoot: directory.path,
      );
      final cache = File(p.join(directory.path, '0001.jpg'));
      final decoded = image.decodeJpg(cache.readAsBytesSync())!;
      final page = session.anchor(
        chapterId: '0',
        imageNumber: 1,
        width: decoded.width.toDouble(),
        height: decoded.height.toDouble(),
        sourceIdentity: 'file://${cache.path}',
      );
      final note = session.add(
        page,
        AnnotationKind.pageNote,
        'Keep on cancellation',
      );
      var cancelled = false;
      final pending = resolveLocalAnnotationImage(
        session,
        note,
        isCancelled: () => cancelled || session.inputActive,
      );
      final expectation = expectLater(
        pending,
        throwsA(isA<AnnotationExportCancelled>()),
      );
      await Future<void>.delayed(Duration.zero);
      cancelled = true;
      session.close();
      await expectation;
      final reopened = openLocalAnnotationSession(
        libraryKey: 'local:pdf:1',
        title: comic.title,
        sourceRoot: directory.path,
      );
      try {
        expect(reopened.all.single.id, note.id);
        expect(reopened.all.single.text, 'Keep on cancellation');
      } finally {
        reopened.close();
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  test(
    'retained original and UUID survive archive deletion and library movement without display cache',
    () async {
      final file = await source();
      final comic = await PdfComicImporter.import(file, retainOriginal: true);
      var directory = Directory(p.join(LocalManager().path, comic.directory));
      var session = openLocalAnnotationSession(
        libraryKey: 'local:pdf:1',
        title: comic.title,
        sourceRoot: directory.path,
      );
      final cache = File(p.join(directory.path, '0001.jpg'));
      final decoded = image.decodeJpg(cache.readAsBytesSync())!;
      final page = session.anchor(
        chapterId: '0',
        imageNumber: 1,
        width: decoded.width.toDouble(),
        height: decoded.height.toDouble(),
        sourceIdentity: 'file://${cache.path}',
      );
      final note = session.add(
        page,
        AnnotationKind.region,
        'Preserve',
        rect: ContentRect(.1, .1, .4, .4),
      );
      final id = session.documentId;
      final retained = File(p.join(directory.path, '.comicnotes-original.pdf'));
      final held = retained.renameSync('${retained.path}.held');
      expect(
        (await resolveLocalAnnotationImage(session, note)).quality,
        AnnotationImageQuality.original,
      );
      held.renameSync(retained.path);
      final savedCopy = retained.readAsBytesSync();
      retained.writeAsStringSync('damaged retained copy');
      final external = file.renameSync(
        p.join(caseRoot.path, 'relocated original.pdf'),
      );
      expect(
        await relocateAnnotationOriginal(
          session,
          external,
          isCurrent: () => true,
        ),
        isTrue,
      );
      expect(
        (await resolveLocalAnnotationImage(session, note)).quality,
        AnnotationImageQuality.original,
      );
      expect(retained.readAsStringSync(), 'damaged retained copy');
      retained.writeAsBytesSync(savedCopy);
      session.close();
      cache.deleteSync();
      external.deleteSync();
      directory = directory.renameSync(p.join(caseRoot.path, 'moved 漫画'));
      session = openLocalAnnotationSession(
        libraryKey: 'local:pdf:1',
        title: comic.title,
        sourceRoot: directory.path,
      );
      addTearDown(session.close);
      expect(session.documentId, id);
      expect(session.all.single.id, note.id);
      expect(
        (await resolveLocalAnnotationImage(session, note)).quality,
        AnnotationImageQuality.original,
      );
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  test(
    'relocating the exact PDF restores original export across reopen without changing anchors',
    () async {
      final file = await source();
      final comic = await PdfComicImporter.import(file);
      final directory = Directory(p.join(LocalManager().path, comic.directory));
      var session = openLocalAnnotationSession(
        libraryKey: 'local:pdf:1',
        title: comic.title,
        sourceRoot: directory.path,
      );
      final cache = File(p.join(directory.path, '0002.jpg'));
      final decoded = image.decodeJpg(cache.readAsBytesSync())!;
      final page = session.anchor(
        chapterId: '0',
        imageNumber: 2,
        width: decoded.width.toDouble(),
        height: decoded.height.toDouble(),
        sourceIdentity: 'file://${cache.path}',
      );
      final note = session.add(
        page,
        AnnotationKind.region,
        'Relocate rotation 90',
        rect: ContentRect(.2, .15, .7, .8),
      );
      session.setTags(note.id, ['保留']);
      final before = await resolveLocalAnnotationImage(session, note);
      final moved = file.renameSync(p.join(caseRoot.path, 'moved 原件 %.pdf'));
      expect(
        (await resolveLocalAnnotationImage(session, note)).quality,
        AnnotationImageQuality.displayCache,
      );
      expect(
        await relocateAnnotationOriginal(session, moved, isCurrent: () => true),
        isTrue,
      );
      final documentId = session.documentId;
      session.close();
      session = openLocalAnnotationSession(
        libraryKey: 'local:pdf:1',
        title: comic.title,
        sourceRoot: directory.path,
      );
      addTearDown(session.close);
      expect(session.documentId, documentId);
      final reopened = session.all.single;
      expect(reopened.id, note.id);
      expect(reopened.anchor.pageId, page.pageId);
      expect(reopened.rect!.toJson(), note.rect!.toJson());
      expect(reopened.tags, ['保留']);
      expect(session.sourceDocument!.source!.uri, moved.uri.toString());
      final after = await resolveLocalAnnotationImage(session, reopened);
      expect(after.quality, AnnotationImageQuality.original);
      expect(after.bytes, before.bytes);
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  test(
    'identical PDF reimport restores orphan identity across a changed retained-copy choice',
    () async {
      final file = await source();
      final comic = await PdfComicImporter.import(
        file,
        retainOriginal: true,
        registerComic: (comic) => LocalManager().add(comic, comic.id),
      );
      final old = openLocalAnnotationSession(
        libraryKey:
            'local:${comic.id}:${comic.createdAt.millisecondsSinceEpoch}',
        title: comic.title,
        sourceRoot: comic.baseDir,
      );
      final cache = File(p.join(comic.baseDir, '0002.jpg'));
      final decoded = image.decodeJpg(cache.readAsBytesSync())!;
      final page = old.anchor(
        chapterId: '0',
        imageNumber: 2,
        width: decoded.width.toDouble(),
        height: decoded.height.toDouble(),
        sourceIdentity: 'file://${cache.path}',
      );
      final note = old.add(
        page,
        AnnotationKind.region,
        'Recover PDF',
        rect: ContentRect(.1, .2, .7, .8),
      );
      final documentId = old.documentId;
      old.close();
      LocalManager().remove(comic.id, comic.comicType);
      Directory(comic.baseDir).deleteSync(recursive: true);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final imported = await PdfComicImporter.import(
        file,
        retainOriginal: false,
        registerComic: (comic) => LocalManager().add(comic, comic.id),
      );
      final current = openLocalAnnotationSession(
        libraryKey:
            'local:${imported.id}:${imported.createdAt.millisecondsSinceEpoch}',
        title: imported.title,
        sourceRoot: imported.baseDir,
      );
      expect(
        (await findRecoverableAnnotations(session: current)).single.documentId,
        documentId,
      );
      expect(
        await recoverLocalAnnotations(
          session: current,
          documentId: documentId,
          isCurrent: () => true,
        ),
        isTrue,
      );
      current.close();
      final restored = openLocalAnnotationSession(
        libraryKey:
            'local:${imported.id}:${imported.createdAt.millisecondsSinceEpoch}',
        title: imported.title,
        sourceRoot: imported.baseDir,
      );
      try {
        expect(restored.documentId, documentId);
        expect(restored.all.single.id, note.id);
        expect(
          restored
              .sourcePage(restored.all.single.anchor)!
              .locator
              .containsKey('retainedSourcePath'),
          isFalse,
        );
        expect(
          (await resolveLocalAnnotationImage(
            restored,
            restored.all.single,
          )).quality,
          AnnotationImageQuality.original,
        );
      } finally {
        restored.close();
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  for (final changed in [false, true]) {
    test(
      'unreachable original explicitly falls back to verified cache; changed=$changed',
      () async {
        final file = await source();
        final comic = await PdfComicImporter.import(file);
        final directory = Directory(
          p.join(LocalManager().path, comic.directory),
        );
        final session = openLocalAnnotationSession(
          libraryKey: 'local:pdf:1',
          title: comic.title,
          sourceRoot: directory.path,
        );
        addTearDown(session.close);
        final cache = File(p.join(directory.path, '0001.jpg'));
        final decoded = image.decodeJpg(cache.readAsBytesSync())!;
        final page = session.anchor(
          chapterId: '0',
          imageNumber: 1,
          width: decoded.width.toDouble(),
          height: decoded.height.toDouble(),
          sourceIdentity: 'file://${cache.path}',
        );
        final note = session.add(page, AnnotationKind.pageNote, 'Still here');
        if (changed) {
          file.writeAsStringSync('\n% changed', mode: FileMode.append);
        } else {
          file.deleteSync();
        }
        final resolved = await resolveLocalAnnotationImage(session, note);
        expect(resolved.quality, AnnotationImageQuality.displayCache);
        expect(resolved.warning, contains('渲染缓存'));
        expect(session.sourceDocument!.status, changed ? 'changed' : 'missing');
        final output =
            await AnnotationExportService(
              resolveImage: (note) =>
                  resolveLocalAnnotationImage(session, note),
            ).export(
              destination: caseRoot.path,
              documentId: session.documentId,
              title: comic.title,
              annotations: session.all,
            );
        expect(
          File(output.markdownPath).readAsStringSync(),
          contains(resolved.warning!),
        );
        await File(
          'test/fixtures/annotations/pdf-crop-rotate.pdf',
        ).copy(file.path);
        expect(
          (await resolveLocalAnnotationImage(session, note)).quality,
          AnnotationImageQuality.original,
        );
        expect(session.sourceDocument!.status, 'available');
        final corrupt = cache.readAsBytesSync()..[20] ^= 1;
        cache.writeAsBytesSync(corrupt);
        await expectLater(
          resolveLocalAnnotationImage(session, note),
          throwsA(isA<FileSystemException>()),
        );
        expect(session.all.single.text, 'Still here');
      },
      skip: !const bool.fromEnvironment('COMICNOTES_POC'),
    );
  }

  test(
    'changing the PDF during import fails before registration and removes owned output',
    () async {
      final file = await source();
      var modified = false, registered = false;
      await expectLater(
        PdfComicImporter.import(
          file,
          retainOriginal: true,
          onProgress: (page, total) {
            if (!modified) {
              modified = true;
              file.writeAsStringSync(
                '\n% source changed',
                mode: FileMode.append,
              );
            }
          },
          registerComic: (_) async => registered = true,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(registered, isFalse);
      expect(
        Directory(LocalManager().path).listSync().whereType<Directory>(),
        isEmpty,
      );
      expect(file.existsSync(), isTrue);
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );
}
