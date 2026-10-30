import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:venera_next/features/annotations/application/annotation_export_service.dart';
import 'package:venera_next/features/annotations/domain/annotation.dart';
import 'package:venera_next/features/annotations/domain/geometry.dart';

void main() {
  late Directory root;
  late Uint8List bytes;
  final at = DateTime.utc(2026, 10, 29);
  const anchor = PageAnchor(
    documentId: '书籍 & version 1',
    pageId: 'page-1',
    chapterId: '第一卷 [A]',
    sourceImageNumber: 8,
    sourceWidth: 100,
    sourceHeight: 200,
  );
  Annotation note(
    String id, {
    AnnotationKind kind = AnnotationKind.region,
    String text = '笔记 **原样保留**',
    PageAnchor page = anchor,
    List<String> tags = const [],
  }) => Annotation(
    id: id,
    anchor: page,
    kind: kind,
    text: text,
    rect: kind == AnnotationKind.region
        ? ContentRect(0.2, 0.25, 0.7, 0.75)
        : null,
    createdAt: at,
    updatedAt: at,
    tags: tags,
  );
  setUp(() {
    root = Directory.systemTemp.createTempSync('comicnotes-export-test-');
    final pixels = image.Image(width: 100, height: 200);
    for (var y = 0; y < 200; y++) {
      for (var x = 0; x < 100; x++) {
        pixels.setPixelRgb(x, y, x, y, 30);
      }
    }
    bytes = Uint8List.fromList(image.encodePng(pixels));
  });
  tearDown(() => root.deleteSync(recursive: true));
  AnnotationExportService service({
    ResolveAnnotationImage? resolve,
    String id = 'export-1',
  }) => AnnotationExportService(
    newId: () => id,
    resolveImage:
        resolve ??
        (_) async => ResolvedAnnotationImage(
          bytes: bytes,
          quality: AnnotationImageQuality.original,
        ),
  );

  test(
    'exports exact source pixels, relative links, stable IDs and a complete manifest',
    () async {
      final result = await service().export(
        destination: root.path,
        documentId: anchor.documentId,
        title: '中文/漫画 [1]',
        annotations: [
          note('anno-1', tags: ['构图', '人物']),
        ],
      );
      final png = File('${result.directory}/assets/anno-1.png');
      final crop = image.decodePng(await png.readAsBytes())!;
      expect((crop.width, crop.height), (50, 100));
      expect(crop.getPixel(0, 0).r, 20);
      expect(crop.getPixel(0, 0).g, 50);
      expect(crop.getPixel(49, 99).r, 69);
      expect(crop.getPixel(49, 99).g, 149);
      final md = await File(result.markdownPath).readAsString();
      expect(md, contains('![选区截图](assets/anno-1.png)'));
      expect(md, contains('笔记 **原样保留**'));
      expect(md, contains('标签：人物、构图'));
      expect(md, contains('comicnote:annotation:anno-1:start'));
      expect(md, contains('第 8 张原图'));
      final link = RegExp(
        r'comicnotes://open\?[^)]+',
      ).firstMatch(md)!.group(0)!;
      expect(Uri.parse(link).queryParameters, {
        'document': anchor.documentId,
        'annotation': 'anno-1',
      });
      final manifest =
          jsonDecode(
                await File('${result.directory}/manifest.json').readAsString(),
              )
              as Map;
      expect(manifest['schemaVersion'], 1);
      expect(manifest['annotations'].single['tags'], ['人物', '构图']);
      expect(
        (manifest['annotations'] as List).single['annotationId'],
        'anno-1',
      );
      expect((manifest['managedBlockHashes'] as Map)['anno-1'], hasLength(64));
      expect(result.warnings, isEmpty);
      expect(
        root.listSync().where((f) => f.path.contains('.comicnotes-export-')),
        isEmpty,
      );
    },
  );
  test(
    'cache fallback is disclosed in Markdown, manifest and returned warnings',
    () async {
      final result =
          await service(
            resolve: (_) async => ResolvedAnnotationImage(
              bytes: bytes,
              quality: AnnotationImageQuality.displayCache,
            ),
          ).export(
            destination: root.path,
            documentId: anchor.documentId,
            title: 'Book',
            annotations: [note('one')],
          );
      expect(result.warnings.single, contains('缓存'));
      expect(await File(result.markdownPath).readAsString(), contains('缓存'));
      final manifest =
          jsonDecode(
                await File('${result.directory}/manifest.json').readAsString(),
              )
              as Map;
      expect(manifest['assets']['one']['quality'], 'displayCache');
    },
  );
  test(
    'page notes use full images; bookmarks do not require an image source',
    () async {
      var reads = 0;
      final result =
          await service(
            resolve: (_) async {
              reads++;
              return ResolvedAnnotationImage(
                bytes: bytes,
                quality: AnnotationImageQuality.original,
              );
            },
          ).export(
            destination: root.path,
            documentId: anchor.documentId,
            title: 'Book',
            annotations: [
              note('page-note', kind: AnnotationKind.pageNote),
              note('bookmark', kind: AnnotationKind.bookmark),
            ],
          );
      expect(reads, 1);
      final full = image.decodePng(
        await File('${result.directory}/assets/page-note.png').readAsBytes(),
      )!;
      expect((full.width, full.height), (100, 200));
      expect(
        File('${result.directory}/assets/bookmark.png').existsSync(),
        isFalse,
      );
      expect(await File(result.markdownPath).readAsString(), contains('书签'));
    },
  );
  test(
    'failed image resolution leaves existing notebooks and destination unchanged',
    () async {
      final user = File('${root.path}/my-notes.md')..writeAsStringSync('手写内容');
      await expectLater(
        service(
          resolve: (_) async => throw FileSystemException('missing'),
        ).export(
          destination: root.path,
          documentId: anchor.documentId,
          title: 'Book',
          annotations: [note('one')],
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(user.readAsStringSync(), '手写内容');
      expect(root.listSync().map((f) => f.path), [user.path]);
    },
  );
  test(
    'cancelling an in-flight source read removes the entire staging output',
    () async {
      final pending = Completer<ResolvedAnnotationImage>();
      var cancelled = false;
      final exported = service(resolve: (_) => pending.future).export(
        destination: root.path,
        documentId: anchor.documentId,
        title: 'Book',
        annotations: [note('one')],
        isCancelled: () => cancelled,
      );
      final expectation = expectLater(
        exported,
        throwsA(isA<AnnotationExportCancelled>()),
      );
      await pumpEventQueue();
      cancelled = true;
      pending.complete(
        ResolvedAnnotationImage(
          bytes: bytes,
          quality: AnnotationImageQuality.original,
        ),
      );
      await expectation;
      expect(root.listSync(), isEmpty);
    },
  );
  test(
    'duplicate IDs, malicious filenames and cross-document targets are rejected before writing',
    () async {
      const other = PageAnchor(
        documentId: 'other',
        pageId: 'other',
        chapterId: 'one',
        sourceImageNumber: 1,
        sourceWidth: 100,
        sourceHeight: 200,
      );
      for (final notes in [
        [note('one'), note('one')],
        [note('../../escape')],
        [note('one', page: other)],
      ]) {
        await expectLater(
          service().export(
            destination: root.path,
            documentId: anchor.documentId,
            title: 'Book',
            annotations: notes,
          ),
          throwsArgumentError,
        );
        expect(root.listSync(), isEmpty);
      }
    },
  );
  test(
    'existing export directories and externally edited Markdown are never replaced',
    () async {
      final first = await service().export(
        destination: root.path,
        documentId: anchor.documentId,
        title: 'Book',
        annotations: [note('one')],
      );
      final md = File(first.markdownPath)..writeAsStringSync('我额外写下的笔记');
      await expectLater(
        service().export(
          destination: root.path,
          documentId: anchor.documentId,
          title: 'Book',
          annotations: [note('one', text: '更新')],
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(md.readAsStringSync(), '我额外写下的笔记');
      final next = await service(id: 'export-2').export(
        destination: root.path,
        documentId: anchor.documentId,
        title: 'Book',
        annotations: [note('one')],
      );
      expect(File('${next.directory}/assets/one.png').existsSync(), isTrue);
      expect(md.readAsStringSync(), '我额外写下的笔记');
    },
  );
  test(
    'changed dimensions and undecodable images fail rather than cropping the wrong content',
    () async {
      for (final invalid in [
        Uint8List(10),
        Uint8List.fromList(image.encodePng(image.Image(width: 40, height: 80))),
      ]) {
        await expectLater(
          service(
            resolve: (_) async => ResolvedAnnotationImage(
              bytes: invalid,
              quality: AnnotationImageQuality.original,
            ),
          ).export(
            destination: root.path,
            documentId: anchor.documentId,
            title: 'Book',
            annotations: [note('one')],
          ),
          throwsA(anyOf(isA<FormatException>(), isA<StateError>())),
        );
        expect(root.listSync(), isEmpty);
      }
    },
  );
  test(
    'already cropped original renders are not cropped a second time',
    () async {
      final result =
          await service(
            resolve: (_) async => ResolvedAnnotationImage(
              bytes: Uint8List.fromList(
                image.encodePng(image.Image(width: 200, height: 300)),
              ),
              quality: AnnotationImageQuality.original,
              alreadyCropped: true,
            ),
          ).export(
            destination: root.path,
            documentId: anchor.documentId,
            title: 'Book',
            annotations: [note('one')],
          );
      final pixels = image.decodePng(
        await File('${result.directory}/assets/one.png').readAsBytes(),
      )!;
      expect((pixels.width, pixels.height), (200, 300));
    },
  );
  test(
    'Unicode and platform-special titles produce bounded safe output names',
    () async {
      final title = '${List.filled(200, '漫🌙').join()}/../: *?';
      final result = await service().export(
        destination: root.path,
        documentId: anchor.documentId,
        title: title,
        annotations: [note('one')],
      );
      expect(
        utf8
            .encode(result.markdownPath.split(Platform.pathSeparator).last)
            .length,
        lessThan(200),
      );
      expect(result.directory.startsWith(root.path), isTrue);
      expect(AnnotationExportService.filename('..'), '漫画笔记');
      expect(AnnotationExportService.filename('CON'), '_CON');
      expect(AnnotationExportService.filename('a/b\\c'), 'a_b_c');
    },
  );
}
