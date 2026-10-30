import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart' as archive;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:venera_next/app_runtime/annotations.dart';
import 'package:venera_next/app_runtime/annotation_assets.dart';
import 'package:venera_next/app_runtime/annotation_recovery.dart';
import 'package:venera_next/features/annotations/application/annotation_export_service.dart';
import 'package:venera_next/features/annotations/domain/annotation.dart';
import 'package:venera_next/features/annotations/domain/geometry.dart';
import 'package:venera_next/features/local_comics/import_export/epub_import.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/comic_source_provenance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('annotation-epub-');
    App.dataPath = root.path;
    App.cachePath = (Directory(p.join(root.path, 'cache'))..createSync()).path;
    LocalManager.current?.dispose();
    await LocalManager(initializeSources: () async {}).init();
  });
  tearDown(() async {
    await LocalManager().pendingDownloadTaskWrites;
    LocalManager.current?.dispose();
    root.deleteSync(recursive: true);
  });

  File book(bool markup) {
    final data = <String, List<int>>{};
    void text(String path, String value) => data[path] = utf8.encode(value);
    text(
      'META-INF/container.xml',
      '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
    );
    text(
      'OPS/book.opf',
      '''<package><metadata><title>Source EPUB</title></metadata><manifest>
      <item id="a" href="images/a.png" media-type="image/png"/>
      <item id="b" href="images/b.png" media-type="image/png"/>
      <item id="b-alias" href="images/b.png" media-type="image/png"/>
      <item id="c1" href="text/1.xhtml" media-type="application/xhtml+xml"/>
      <item id="c2" href="text/2.xhtml" media-type="application/xhtml+xml"/>
      <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
      </manifest><spine>${markup ? '<itemref idref="c1"/><itemref idref="nav" linear="no"/><itemref idref="c1"/><itemref idref="c2"/>' : '<itemref idref="b"/><itemref idref="a"/><itemref idref="b"/>'}</spine></package>''',
    );
    text(
      'OPS/text/1.xhtml',
      '<html><body><img src="../images/a.png"/><img src="../images/a.png"/><img src="../images/b.png"/></body></html>',
    );
    text(
      'OPS/text/2.xhtml',
      '<html><body><img src="../images/b.png"/></body></html>',
    );
    text(
      'OPS/nav.xhtml',
      markup
          ? '<html><body><nav><a href="text/1.xhtml">First</a><a href="text/2.xhtml">Second</a></nav></body></html>'
          : '<html><body/></html>',
    );
    for (final (index, name) in ['a', 'b'].indexed) {
      final pixels = image.Image(width: 40, height: 60);
      for (var y = 0; y < 60; y++) {
        for (var x = 0; x < 40; x++) {
          pixels.setPixelRgb(x, y, x + index * 20, y + index * 40, 100);
        }
      }
      data['OPS/images/$name.png'] = image.encodePng(pixels);
    }
    final zip = archive.Archive();
    for (final entry in data.entries) {
      zip.addFile(
        archive.ArchiveFile(entry.key, entry.value.length, entry.value),
      );
    }
    return File(p.join(root.path, markup ? 'markup.epub' : 'direct.epub'))
      ..writeAsBytesSync(archive.ZipEncoder().encodeBytes(zip));
  }

  for (final markup in [false, true]) {
    test(
      'EPUB preserves resource occurrences and exports original pixels after source deletion; markup=$markup',
      () async {
        final file = book(markup);
        final comic = await EpubComicImporter.import(file);
        var directory = Directory(p.join(LocalManager().path, comic.directory));
        final receipt = ComicSourceProvenance.read(directory)!;
        expect(receipt.source['kind'], 'epub');
        expect(receipt.pages, hasLength(markup ? 7 : 3));
        final pages = receipt.pages.values.toList();
        expect(pages.first['opfPath'], 'OPS/book.opf');
        if (markup) {
          expect(pages[0]['spineIndex'], 0);
          expect(pages[0]['imageOccurrence'], 0);
          expect(pages[1]['resourceOccurrence'], 1);
          expect(pages[1]['imageOccurrence'], 1);
          expect(pages[3]['spineIndex'], 2); // includes the non-linear itemref
          expect(pages[3]['resourceOccurrence'], 0);
          expect(pages.last['spineIndex'], 3);
        } else {
          expect(pages[0]['imageManifestIds'], ['b', 'b-alias']);
          expect(pages[2]['spineIndex'], 2);
          expect(pages[0]['imageResourcePath'], pages[2]['imageResourcePath']);
        }
        var session = openLocalAnnotationSession(
          libraryKey: 'local:epub:1',
          title: comic.title,
          sourceRoot: directory.path,
        );
        final pageIds = <String>{};
        for (final (index, entry) in receipt.pages.entries.indexed) {
          final chapter = markup ? entry.key.split('/').first : '0';
          final anchor = session.anchor(
            chapterId: chapter,
            imageNumber: index + 1,
            width: 40,
            height: 60,
            sourceIdentity: 'file://${p.join(directory.path, entry.key)}',
          );
          expect(pageIds.add(anchor.pageId), isTrue);
          session.add(
            anchor,
            AnnotationKind.region,
            'Occurrence $index',
            rect: ContentRect(.25, .2, .75, .8),
          );
        }
        final documentId = session.documentId;
        final noteIds = session.all.map((n) => n.id).toList();
        session.close();
        file.deleteSync();
        directory = directory.renameSync(p.join(root.path, 'moved'));
        session = openLocalAnnotationSession(
          libraryKey: 'local:epub:1',
          title: comic.title,
          sourceRoot: directory.path,
        );
        addTearDown(session.close);
        expect(session.documentId, documentId);
        expect(session.all.map((n) => n.id), noteIds);
        for (final note in session.all) {
          final locator = session.sourcePage(note.anchor)!.locator;
          final resolved = await resolveLocalAnnotationImage(session, note);
          expect(resolved.quality, AnnotationImageQuality.original);
          expect(resolved.provenance!['kind'], 'epubImageCopy');
          expect(resolved.provenance!['spineIndex'], locator['spineIndex']);
        }
        final result =
            await AnnotationExportService(
              resolveImage: (note) =>
                  resolveLocalAnnotationImage(session, note),
            ).export(
              destination: root.path,
              documentId: documentId,
              title: comic.title,
              annotations: session.all,
            );
        for (final note in session.all) {
          final locator = session.sourcePage(note.anchor)!.locator;
          final second = locator['imageResourcePath'] == 'OPS/images/b.png';
          final png = image.decodePng(
            File(
              p.join(result.directory, 'assets', '${note.id}.png'),
            ).readAsBytesSync(),
          )!;
          expect((png.width, png.height), (20, 36));
          final first = png.getPixel(0, 0), last = png.getPixel(19, 35);
          expect(
            [first.r, first.g, first.b],
            [10 + (second ? 20 : 0), 12 + (second ? 40 : 0), 100],
          );
          expect(
            [last.r, last.g, last.b],
            [29 + (second ? 20 : 0), 47 + (second ? 40 : 0), 100],
          );
        }
        expect(result.warnings, isEmpty);
      },
      skip: !const bool.fromEnvironment('COMICNOTES_POC'),
    );
  }

  test(
    'reimported repeated-spine EPUB restores distinct old occurrence IDs',
    () async {
      final file = book(true);
      final comic = await EpubComicImporter.import(
        file,
        registerComic: (comic) => LocalManager().add(comic, comic.id),
      );
      final old = openLocalAnnotationSession(
        libraryKey:
            'local:${comic.id}:${comic.createdAt.millisecondsSinceEpoch}',
        title: comic.title,
        sourceRoot: comic.baseDir,
      );
      final receipt = ComicSourceProvenance.read(Directory(comic.baseDir))!;
      for (final entry in receipt.pages.entries) {
        final page = old.anchor(
          chapterId: entry.key.split('/').first,
          imageNumber: 1,
          width: 40,
          height: 60,
          sourceIdentity: 'file://${p.join(comic.baseDir, entry.key)}',
        );
        old.add(page, AnnotationKind.pageNote, entry.key);
      }
      final documentId = old.documentId,
          ids = old.all.map((note) => note.id).toSet();
      old.close();
      LocalManager().remove(comic.id, comic.comicType);
      Directory(comic.baseDir).deleteSync(recursive: true);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final imported = await EpubComicImporter.import(
        file,
        registerComic: (comic) => LocalManager().add(comic, comic.id),
      );
      final current = openLocalAnnotationSession(
        libraryKey:
            'local:${imported.id}:${imported.createdAt.millisecondsSinceEpoch}',
        title: imported.title,
        sourceRoot: imported.baseDir,
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
        expect(restored.all.map((note) => note.id).toSet(), ids);
        expect(
          restored.all.map((note) => note.anchor.pageId).toSet(),
          hasLength(7),
        );
        for (final note in restored.all) {
          expect(
            (await resolveLocalAnnotationImage(restored, note)).quality,
            AnnotationImageQuality.original,
          );
        }
      } finally {
        restored.close();
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );
}
