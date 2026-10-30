import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart' as archive;
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:venera_next/app_runtime/annotation_assets.dart';
import 'package:venera_next/app_runtime/annotations.dart';
import 'package:venera_next/features/annotations/application/annotation_export_service.dart';
import 'package:venera_next/features/annotations/domain/annotation.dart';
import 'package:venera_next/features/annotations/domain/geometry.dart';
import 'package:venera_next/features/local_comics/import_export/cbz.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/comic_source_provenance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late List<int> pixels;
  late File source;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('annotation-archive-');
    App.dataPath = root.path;
    App.cachePath = (Directory(p.join(root.path, 'cache'))..createSync()).path;
    LocalManager.current?.dispose();
    await LocalManager(initializeSources: () async {}).init();
    final pattern = image.Image(width: 12, height: 16);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 12; x++) {
        pattern.setPixelRgb(x, y, x * 10, y * 10, 56);
      }
    }
    pixels = image.encodePng(pattern);
    final zip = archive.Archive();
    for (final name in [
      'wrapped/第一章/10.png',
      'wrapped/第一章/2.png',
      'wrapped/第二章/1.png',
    ]) {
      zip.addFile(archive.ArchiveFile(name, pixels.length, pixels));
    }
    source = File(p.join(root.path, 'Book.cbz'))
      ..writeAsBytesSync(archive.ZipEncoder().encodeBytes(zip));
  });
  tearDown(() async {
    await LocalManager().pendingDownloadTaskWrites;
    LocalManager.current?.dispose();
    root.deleteSync(recursive: true);
  });

  test(
    'archive receipt follows renamed chapter pages and is committed before registration',
    () async {
      final comic = await CBZ.import(
        source,
        registerComic: (comic) async {
          expect(
            ComicSourceProvenance.read(
              Directory(p.join(LocalManager().path, comic.directory)),
            ),
            isNotNull,
          );
        },
      );
      final directory = Directory(p.join(LocalManager().path, comic.directory));
      final receipt = ComicSourceProvenance.read(directory)!;
      expect(
        receipt.source['sha256'],
        sha256.convert(source.readAsBytesSync()).toString(),
      );
      expect(receipt.pages.keys, ['0/1.png', '0/2.png', '1/1.png']);
      expect(receipt.pages['0/1.png']!['extractedEntry'], 'wrapped/第一章/2.png');
      expect(receipt.pages['0/1.png']!['archiveEntryIndex'], 1);
      expect(receipt.pages['0/1.png']!['archiveEntryOccurrence'], 0);
      expect(receipt.pages['0/1.png']!['archiveEntryCount'], 1);
      expect(receipt.pages['0/2.png']!['extractedEntry'], 'wrapped/第一章/10.png');
      expect(
        receipt.pages['1/1.png']!['sha256'],
        sha256.convert(pixels).toString(),
      );
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  for (final variant in ['samePath', 'normalizedAlias', 'equalBytes']) {
    test(
      'ZIP duplicate provenance resolves actual extracted bytes and preserves central order; $variant',
      () async {
        final otherPixels = image.encodePng(
          image.Image(width: 12, height: 16)
            ..clear(image.ColorRgb8(240, 20, 30)),
        );
        final output = archive.OutputMemoryStream();
        final encoder = archive.ZipEncoder()..startEncode(output);
        encoder.add(archive.ArchiveFile('wrapped/readme.txt', 4, [1, 2, 3, 4]));
        encoder.add(
          archive.ArchiveFile('wrapped/1.png', pixels.length, pixels),
        );
        final secondName = variant == 'normalizedAlias'
            ? 'wrapped/./1.png'
            : 'wrapped/1.png';
        final secondPixels = variant == 'equalBytes' ? pixels : otherPixels;
        encoder.add(
          archive.ArchiveFile(secondName, secondPixels.length, secondPixels),
        );
        encoder.add(
          archive.ArchiveFile('wrapped/2.png', otherPixels.length, otherPixels),
        );
        encoder.endEncode();
        source.writeAsBytesSync(output.getBytes());
        final comic = await CBZ.import(source);
        final directory = Directory(
          p.join(LocalManager().path, comic.directory),
        );
        final receipt = ComicSourceProvenance.read(directory)!;
        final locator = receipt.pages['1.png']!;
        final actual = File(p.join(directory.path, '1.png')).readAsBytesSync();
        final matching = <int>[];
        if (sha256.convert(actual).toString() ==
            sha256.convert(pixels).toString()) {
          matching.add(1);
        }
        if (sha256.convert(actual).toString() ==
            sha256.convert(secondPixels).toString()) {
          matching.add(2);
        }
        expect(matching, isNotEmpty);
        expect(locator['archiveEntryCount'], 2);
        expect(locator['archiveEntryIndex'], matching.first);
        expect(locator['archiveEntryOccurrence'], matching.first - 1);
        expect(locator['matchingEntryIndices'], matching);
        expect(locator['archiveEntryResolution'], 'contentMatched');
        expect(
          locator['archiveEntryName'],
          matching.first == 1 ? 'wrapped/1.png' : secondName,
        );
        expect(locator['sha256'], sha256.convert(actual).toString());
        expect(receipt.pages['2.png']!['archiveEntryIndex'], 3);
        final session = openLocalAnnotationSession(
          libraryKey: 'local:duplicate:1',
          title: 'Duplicate',
          sourceRoot: directory.path,
        );
        try {
          final page = session.anchor(
            chapterId: '1',
            imageNumber: 1,
            width: 12,
            height: 16,
            sourceIdentity: 'file://${p.join(directory.path, '1.png')}',
          );
          final note = session.add(
            page,
            AnnotationKind.pageNote,
            'Duplicate entry',
          );
          source.deleteSync();
          final resolved = await resolveLocalAnnotationImage(session, note);
          expect(resolved.quality, AnnotationImageQuality.original);
          expect(resolved.bytes, actual);
          expect(resolved.provenance!['archiveEntryIndex'], matching.first);
          final exported =
              await AnnotationExportService(
                resolveImage: (note) =>
                    resolveLocalAnnotationImage(session, note),
              ).export(
                destination: root.path,
                documentId: session.documentId,
                title: 'Duplicate',
                annotations: session.all,
              );
          final manifest = jsonDecode(
            File(
              p.join(exported.directory, 'manifest.json'),
            ).readAsStringSync(),
          );
          expect(
            manifest['assets'][note.id]['source']['archiveEntryOccurrence'],
            matching.first - 1,
          );
        } finally {
          session.close();
        }
      },
      skip: !const bool.fromEnvironment('COMICNOTES_POC'),
    );
  }

  test(
    'oversized duplicate payload cannot overrun verification output or publish an import',
    () async {
      final output = archive.OutputMemoryStream();
      final encoder = archive.ZipEncoder()..startEncode(output);
      encoder.add(archive.ArchiveFile('1.png', pixels.length, pixels));
      final oversized = List<int>.filled(pixels.length + 10000, 65);
      encoder.add(archive.ArchiveFile('1.png', oversized.length, oversized));
      encoder.endEncode();
      final bytes = Uint8List.fromList(output.getBytes());
      final data = ByteData.sublistView(bytes);
      var entry = 0;
      for (var offset = 0; offset + 46 <= bytes.length; offset++) {
        if (data.getUint32(offset, Endian.little) != 0x02014b50) continue;
        if (entry++ == 1) {
          final local = data.getUint32(offset + 42, Endian.little);
          data.setUint32(offset + 24, pixels.length, Endian.little);
          data.setUint32(local + 22, pixels.length, Endian.little);
          break;
        }
      }
      expect(entry, 2);
      source.writeAsBytesSync(bytes);
      var registered = false;
      await expectLater(
        CBZ.import(
          source,
          registerComic: (_) async {
            registered = true;
          },
        ),
        throwsFormatException,
      );
      expect(registered, isFalse);
      expect(
        Directory(p.join(LocalManager().path, 'Book')).existsSync(),
        isFalse,
      );
      expect(
        Directory(App.cachePath).listSync().whereType<Directory>(),
        isEmpty,
      );
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  test(
    'verified original image copy exports after archive deletion and library movement',
    () async {
      final comic = await CBZ.import(source);
      var directory = Directory(p.join(LocalManager().path, comic.directory));
      var session = openLocalAnnotationSession(
        libraryKey: 'local:test:1',
        title: 'Book',
        sourceRoot: directory.path,
      );
      final page = session.anchor(
        chapterId: '0',
        imageNumber: 1,
        width: 12,
        height: 16,
        sourceIdentity: 'file://${p.join(directory.path, '0', '1.png')}',
      );
      final note = session.add(
        page,
        AnnotationKind.region,
        'Original',
        rect: ContentRect(.25, .25, .75, .75),
      );
      final documentId = session.documentId;
      expect(session.sourceDocument!.source!.kind, 'archive');
      expect(
        session.sourcePage(page)!.locator['extractedEntry'],
        'wrapped/第一章/2.png',
      );
      session.close();
      source.deleteSync();
      directory = directory.renameSync(p.join(root.path, 'moved'));
      session = openLocalAnnotationSession(
        libraryKey: 'local:test:1',
        title: 'Book',
        sourceRoot: directory.path,
      );
      addTearDown(session.close);
      expect(session.documentId, documentId);
      final resolved = await resolveLocalAnnotationImage(session, note);
      expect(resolved.quality, AnnotationImageQuality.original);
      expect(resolved.bytes, pixels);
      expect(resolved.warning, isNull);
      final exported =
          await AnnotationExportService(
            resolveImage: (note) => resolveLocalAnnotationImage(session, note),
          ).export(
            destination: root.path,
            documentId: documentId,
            title: 'Book',
            annotations: session.all,
          );
      final manifest = jsonDecode(
        File(p.join(exported.directory, 'manifest.json')).readAsStringSync(),
      );
      expect(manifest['assets'][note.id]['quality'], 'original');
      expect(
        manifest['assets'][note.id]['source']['extractedEntry'],
        'wrapped/第一章/2.png',
      );
      final crop = image.decodePng(
        File(
          p.join(exported.directory, 'assets', '${note.id}.png'),
        ).readAsBytesSync(),
      )!;
      expect((crop.width, crop.height), (6, 8));
      expect([crop.getPixel(0, 0).r, crop.getPixel(0, 0).g], [30, 40]);
      expect([crop.getPixel(5, 7).r, crop.getPixel(5, 7).g], [80, 110]);
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  test(
    'same-sized changed original copy is rejected without losing notes',
    () async {
      final comic = await CBZ.import(source);
      final directory = Directory(p.join(LocalManager().path, comic.directory));
      final session = openLocalAnnotationSession(
        libraryKey: 'local:test:1',
        title: 'Book',
        sourceRoot: directory.path,
      );
      addTearDown(session.close);
      final file = File(p.join(directory.path, '0', '1.png'));
      final page = session.anchor(
        chapterId: '0',
        imageNumber: 1,
        width: 12,
        height: 16,
        sourceIdentity: 'file://${file.path}',
      );
      final note = session.add(page, AnnotationKind.pageNote, 'Keep');
      final bytes = file.readAsBytesSync();
      bytes[bytes.length - 1] ^= 1;
      file.writeAsBytesSync(bytes);
      await expectLater(
        resolveLocalAnnotationImage(session, note),
        throwsA(isA<FileSystemException>()),
      );
      expect(session.sourceDocument!.status, 'changed');
      expect(session.all.single.text, 'Keep');
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  test(
    'flat CBZ metadata chapter ranges preserve original names and crop pixel offsets',
    () async {
      final zip = archive.Archive();
      for (final name in ['001 原图.png', '002%20.png']) {
        zip.addFile(archive.ArchiveFile(name, pixels.length, pixels));
      }
      final metadata = utf8.encode(
        jsonEncode({
          'title': 'Flat book',
          'author': '',
          'tags': [],
          'chapters': [
            {'title': 'First', 'start': 1, 'end': 1},
            {'title': 'Second', 'start': 2, 'end': 2},
          ],
        }),
      );
      zip.addFile(
        archive.ArchiveFile('metadata.json', metadata.length, metadata),
      );
      final file = File(p.join(root.path, 'flat.cbz'))
        ..writeAsBytesSync(archive.ZipEncoder().encodeBytes(zip));
      final comic = await CBZ.import(file);
      final directory = Directory(p.join(LocalManager().path, comic.directory));
      final receipt = ComicSourceProvenance.read(directory)!;
      expect(receipt.pages['1/1.png']!['extractedEntry'], '002%20.png');
      final session = openLocalAnnotationSession(
        libraryKey: 'local:flat:1',
        title: comic.title,
        sourceRoot: directory.path,
      );
      addTearDown(session.close);
      final page = session.anchor(
        chapterId: '1',
        imageNumber: 1,
        width: 12,
        height: 16,
        sourceIdentity: 'file://${p.join(directory.path, '1', '1.png')}',
      );
      session.add(
        page,
        AnnotationKind.region,
        'Offset',
        rect: ContentRect(.5, 0, 1, .5),
      );
      final result =
          await AnnotationExportService(
            resolveImage: (note) => resolveLocalAnnotationImage(session, note),
          ).export(
            destination: root.path,
            documentId: session.documentId,
            title: comic.title,
            annotations: session.all,
          );
      final crop = image.decodePng(
        File(
          p.join(result.directory, 'assets', '${session.all.single.id}.png'),
        ).readAsBytesSync(),
      )!;
      expect((crop.width, crop.height), (6, 8));
      expect([crop.getPixel(0, 0).r, crop.getPixel(0, 0).g], [60, 0]);
      expect([crop.getPixel(5, 7).r, crop.getPixel(5, 7).g], [110, 70]);
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  test(
    'receipt validates occurrence fields while retaining legacy path-only compatibility',
    () async {
      final directory = Directory(p.join(root.path, 'receipt'))..createSync();
      final locator = <String, Object?>{
        'kind': 'archiveImage',
        'extractedEntry': '1.png',
        'size': 1,
        'sha256': 'b' * 64,
      };
      final receipt = ComicSourceProvenance(
        source: {
          'kind': 'archive',
          'uri': source.uri.toString(),
          'size': 1,
          'sha256': 'a' * 64,
        },
        pages: {'1.png': locator},
      );
      await receipt.write(directory);
      expect(ComicSourceProvenance.read(directory), isNotNull);
      locator.addAll({
        'archiveEntryIndex': 4,
        'archiveEntryOccurrence': 1,
        'archiveEntryCount': 2,
        'archiveEntryName': '1.png',
        'archiveEntryResolution': 'contentMatched',
        'matchingEntryIndices': [4],
      });
      await receipt.write(directory);
      expect(ComicSourceProvenance.read(directory), isNotNull);
      locator['archiveEntryOccurrence'] = 2;
      await receipt.write(directory);
      expect(
        () => ComicSourceProvenance.read(directory),
        throwsFormatException,
      );
      locator['archiveEntryOccurrence'] = 1;
      locator.remove('matchingEntryIndices');
      await receipt.write(directory);
      expect(
        () => ComicSourceProvenance.read(directory),
        throwsFormatException,
      );
    },
  );

  test('receipt rejects path traversal and unknown versions', () async {
    final directory = Directory(p.join(root.path, 'receipt'))..createSync();
    final data = {
      'schemaVersion': 1,
      'source': {
        'kind': 'archive',
        'uri': source.uri.toString(),
        'size': 1,
        'sha256': 'a' * 64,
      },
      'pages': {
        '../outside.png': {
          'kind': 'archiveImage',
          'extractedEntry': 'page.png',
          'size': 1,
          'sha256': 'b' * 64,
        },
      },
    };
    final file = File(p.join(directory.path, ComicSourceProvenance.filename))
      ..writeAsStringSync(jsonEncode(data));
    expect(() => ComicSourceProvenance.read(directory), throwsFormatException);
    data['schemaVersion'] = 2;
    file.writeAsStringSync(jsonEncode(data));
    expect(() => ComicSourceProvenance.read(directory), throwsFormatException);
    file.deleteSync();
    Link(file.path).createSync(source.path);
    expect(() => ComicSourceProvenance.read(directory), throwsFormatException);
  });
}
