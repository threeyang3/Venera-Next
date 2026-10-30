import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/app_runtime/annotation_navigation.dart';
import 'package:venera_next/features/annotations/domain/annotation.dart';
import 'package:venera_next/features/annotations/domain/source_document.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart'
    show ComicChapters;
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/foundation/comic_type.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('annotation-locator-');
    LocalManager.current?.dispose();
    LocalManager(initializeSources: () async {}).path = root.path;
  });
  tearDown(() {
    LocalManager.current?.dispose();
    root.deleteSync(recursive: true);
  });
  LocalComic comic([ComicChapters? chapters]) => LocalComic(
    id: 'book',
    title: 'Book',
    subtitle: '',
    tags: const [],
    directory: 'book',
    chapters: chapters,
    cover: '',
    comicType: ComicType.local,
    downloadedChapters: const [],
    createdAt: DateTime(2026),
  );
  AnnotationSourcePage page({
    String chapter = 'one',
    String identity = 'one/001.png',
  }) => AnnotationSourcePage(
    anchor: PageAnchor(
      documentId: 'doc',
      pageId: 'page',
      chapterId: chapter,
      sourceImageNumber: 99,
      sourceWidth: 100,
      sourceHeight: 200,
    ),
    sourceIdentity: identity,
    assetUri: 'file:///old-root/$identity',
    locator: const {},
  );

  test(
    'uses current source identity, ignoring stale image numbers and cache URIs',
    () async {
      final book = comic(const ComicChapters({'one': 'One'}));
      final result = await locateLocalAnnotation(
        comic: book,
        page: page(),
        images: (chapter) async {
          expect(chapter, 'one');
          return [
            'file://${book.baseDir}/one/002.png',
            'file://${book.baseDir}/one/001.png',
          ];
        },
      );
      expect((result.chapter, result.imageNumber), (1, 2));
    },
  );
  test('chapterless books use the single local image list', () async {
    final book = comic();
    final result = await locateLocalAnnotation(
      comic: book,
      page: page(chapter: '0', identity: '001.png'),
      images: (chapter) async {
        expect(chapter, 1);
        return ['file://${book.baseDir}/001.png'];
      },
    );
    expect((result.chapter, result.imageNumber), (1, 1));
  });
  test(
    'grouped chapters resolve flattened indices without applying history group twice',
    () async {
      final book = comic(
        const ComicChapters.grouped({
          'Vol 1': {'first': 'First', 'second': 'Second'},
          'Vol 2': {'one': 'One'},
        }),
      );
      final result = await locateLocalAnnotation(
        comic: book,
        page: page(),
        images: (_) async => ['file://${book.baseDir}/one/001.png'],
      );
      expect(result.chapter, 3);
      expect(result.imageNumber, 1);
    },
  );
  test(
    'missing and ambiguous source chapters fail instead of choosing a plausible page',
    () async {
      for (final book in [
        comic(const ComicChapters({'else': 'Other'})),
        comic(
          const ComicChapters.grouped({
            'A': {'one': 'One'},
            'B': {'one': 'Another'},
          }),
        ),
        comic(),
      ]) {
        var reads = 0;
        await expectLater(
          locateLocalAnnotation(
            comic: book,
            page: page(),
            images: (_) async {
              reads++;
              return [];
            },
          ),
          throwsStateError,
        );
        expect(reads, 0);
      }
    },
  );
  test(
    'missing images preserve the anchor and report relinking rather than falling back',
    () async {
      final source = page();
      await expectLater(
        locateLocalAnnotation(
          comic: comic(const ComicChapters({'one': 'One'})),
          page: source,
          images: (_) async => [],
        ),
        throwsStateError,
      );
      expect(source.anchor.pageId, 'page');
      expect(source.anchor.sourceImageNumber, 99);
    },
  );
  test(
    'relative traversal and absolute source identities cannot enter navigation',
    () async {
      for (final identity in [
        '../outside.png',
        '/outside.png',
        'one/../001.png',
        r'one\001.png',
        'one//001.png',
      ]) {
        await expectLater(
          locateLocalAnnotation(
            comic: comic(const ComicChapters({'one': 'One'})),
            page: page(identity: identity),
            images: (_) async => [],
          ),
          throwsFormatException,
        );
      }
    },
  );
}
