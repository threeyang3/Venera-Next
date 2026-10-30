import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/features/annotations/data/annotation_repository.dart';
import 'package:photo_view/photo_view.dart';
import 'package:venera_next/features/annotations/annotations.dart';
import 'package:venera_next/features/reader/annotation_layer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:venera_next/features/reader/comic_image.dart';
import 'package:venera_next/features/reader/auto_reading.dart';
import 'package:venera_next/features/reader/display_image_provider.dart';
import 'package:venera_next/features/reader/image_dimensions.dart';
import 'package:venera_next/foundation/image_provider/reader_image.dart';
import 'package:venera_next/foundation/image_work.dart';
import 'package:venera_next/foundation/reader_settings.dart';

class _Provider extends ReaderImageProvider {
  _Provider(this.bytes, {bool resize = false})
    : super(
        'dimensions-${_next++}',
        null,
        'comic',
        'chapter',
        1,
        enableResize: resize,
      );
  static int _next = 0;
  final Future<Uint8List> bytes;
  int loads = 0;
  @override
  Future<Uint8List> load(chunkEvents, checkStop) {
    loads++;
    return bytes;
  }
}

class _RetryProvider extends ReaderImageProvider {
  _RetryProvider() : super('retry-dimensions', null, 'comic', 'chapter', 1);
  int loads = 0;
  @override
  Future<Uint8List> load(chunkEvents, checkStop) async {
    if (++loads == 1) throw Exception('Invalid Status Code: 404');
    return img.encodePng(img.Image(width: 24, height: 48));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('dimension setting defaults off and follows scope precedence', () {
    expect(ReaderSettings.resolve(global: {}).showImageDimensions, isFalse);
    expect(
      ReaderSettings.resolve(
        global: {'showImageDimensions': true},
      ).showImageDimensions,
      isTrue,
    );
    expect(
      ReaderSettings.resolve(
        global: {'showImageDimensions': true},
        device: {'enabled': true, 'showImageDimensions': false},
      ).showImageDimensions,
      isFalse,
    );
    expect(
      ReaderSettings.resolve(
        global: {},
        device: {'enabled': true, 'showImageDimensions': false},
        comic: {'enabled': true, 'showImageDimensions': true},
      ).showImageDimensions,
      isTrue,
    );
  });

  testWidgets(
    'annotation anchor keeps original dimensions while PhotoView uses resized pixels',
    (tester) async {
      final pixels = img.Image(width: 2000, height: 3000)
        ..setPixelRgb(600, 1350, 210, 40, 50)
        ..setPixelRgb(999, 1949, 25, 50, 230);
      final bytes = img.encodePng(pixels);
      final original = _Provider(Future.value(bytes), resize: true);
      final work = ImageWork();
      final image = ReaderDisplayImageProvider(original, work);
      final photo = PhotoViewController();
      final store = AnnotationRepository(
        sqlite3.openInMemory(),
        ownsConnection: true,
      );
      final session = AnnotationSession.persistent(
        store,
        libraryKey: 'resized-original',
        title: 'Original',
        ownsStore: true,
      );
      final destination = Directory.systemTemp.createTempSync(
        'annotation-original-size-',
      );
      final viewport = GlobalKey();
      Widget view(ImageProvider provider) => MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            key: viewport,
            child: ReaderAnnotationLayer(
              image: provider,
              photo: photo,
              session: session,
              chapterId: 'one',
              imageNumber: 1,
              sourceIdentity: 'original.png',
              isCurrent: () => true,
              onInputChanged: (active) => session.inputActive = active,
              child: PhotoView(imageProvider: provider, controller: photo),
            ),
          ),
        ),
      );
      try {
        await tester.pumpWidget(view(image));
        for (
          var i = 0;
          i < 80 && find.byType(AnnotationOverlay).evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        final rawFinder = find.byWidgetPredicate(
          (widget) => widget is RawImage && widget.image != null,
        );
        final raw = tester.widget<RawImage>(rawFinder);
        expect(raw.image!.width, lessThan(2000));
        final overlay = tester.widget<AnnotationOverlay>(
          find.byType(AnnotationOverlay),
        );
        expect(overlay.page.sourceWidth, 2000);
        expect(overlay.page.sourceHeight, 3000);
        photo.updateMultiple(
          scale: photo.scale! * 1.5,
          position: const Offset(17, -21),
          rotation: .12,
        );
        await tester.pumpAndSettle();
        final updated = tester.widget<AnnotationOverlay>(
          find.byType(AnnotationOverlay),
        );
        final box = tester.renderObject<RenderBox>(rawFinder);
        final viewportBox =
            viewport.currentContext!.findRenderObject()! as RenderBox;
        final actual = box.localToGlobal(
          Offset(box.size.width * .3, box.size.height * .45),
        );
        final mapped = updated.transform.toViewport(ContentPoint(.3, .45));
        final expected = viewportBox.localToGlobal(Offset(mapped.x, mapped.y));
        expect((actual - expected).distance, lessThan(1));
        expect(original.loads, 1);
        await tester.tap(find.byTooltip('区域批注'));
        await tester.pumpAndSettle();
        final selection = tester.widget<AnnotationOverlay>(
          find.byType(AnnotationOverlay),
        );
        final start = selection.transform.toViewport(ContentPoint(.3, .45));
        final end = selection.transform.toViewport(ContentPoint(.5, .65));
        final origin = tester.getTopLeft(find.byType(AnnotationOverlay));
        await tester.dragFrom(
          origin + Offset(start.x, start.y),
          Offset(end.x - start.x, end.y - start.y),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Original dimensions');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        final note = session.all.single;
        expect(store.list(session.documentId).single.anchor.sourceWidth, 2000);
        expect(session.sourcePage(note.anchor)!.anchor.sourceHeight, 3000);
        await tester.runAsync(() async {
          final exported =
              await AnnotationExportService(
                resolveImage: (_) async => ResolvedAnnotationImage(
                  bytes: bytes,
                  quality: AnnotationImageQuality.original,
                ),
              ).export(
                destination: destination.path,
                documentId: session.documentId,
                title: 'Original',
                annotations: session.all,
              );
          final crop = img.decodePng(
            File(
              '${exported.directory}/assets/${note.id}.png',
            ).readAsBytesSync(),
          )!;
          final rect = note.rect!;
          final left = (rect.x0 * 2000).floor(), top = (rect.y0 * 3000).floor();
          expect((left - 600).abs(), lessThanOrEqualTo(1));
          expect((top - 1350).abs(), lessThanOrEqualTo(1));
          expect(crop.width, (rect.x1 * 2000).ceil() - left);
          expect(crop.height, (rect.y1 * 3000).ceil() - top);
          expect(crop.getPixel(600 - left, 1350 - top).r, 210);
          expect(crop.getPixel(999 - left, 1949 - top).b, 230);
        });
        final fullProvider = _Provider(Future.value(bytes));
        await tester.pumpWidget(
          view(ReaderDisplayImageProvider(fullProvider, work)),
        );
        for (
          var i = 0;
          i < 80 && find.byType(AnnotationOverlay).evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        final full = tester.widget<AnnotationOverlay>(
          find.byType(AnnotationOverlay),
        );
        expect(tester.widget<RawImage>(rawFinder).image!.width, 2000);
        expect(full.page.pageId, note.anchor.pageId);
        expect(full.page.sourceWidth, 2000);
        expect(full.page.sourceHeight, 3000);
        expect(store.list(session.documentId).single.id, note.id);
        final fullBox = tester.renderObject<RenderBox>(rawFinder);
        final actualFull = fullBox.localToGlobal(
          Offset(fullBox.size.width * .3, fullBox.size.height * .45),
        );
        final mappedFull = full.transform.toViewport(ContentPoint(.3, .45));
        expect(
          (actualFull -
                  viewportBox.localToGlobal(Offset(mappedFull.x, mappedFull.y)))
              .distance,
          lessThan(1),
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        photo.dispose();
        session.close();
        destination.deleteSync(recursive: true);
        final closed = work.dispose();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        await tester.pump();
        await tester.runAsync(() => closed);
      }
    },
  );

  testWidgets(
    'original dimensions survive resized decode, relay and cache hit',
    (tester) async {
      final bytes = img.encodePng(img.Image(width: 2000, height: 2000));
      final original = _Provider(Future.value(bytes), resize: true);
      final work = ImageWork();
      final image = ReaderDisplayImageProvider(original, work);
      Widget view() => MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            height: 180,
            child: ReaderImageDimensions(
              image: image,
              child: Image(image: image),
            ),
          ),
        ),
      );
      try {
        await tester.pumpWidget(view());
        for (
          var i = 0;
          i < 80 && find.text('2000 × 2000').evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(find.text('2000 × 2000'), findsOneWidget);
        final raw = tester.widget<RawImage>(find.byType(RawImage));
        expect(raw.image!.width, lessThan(2000));
        expect(original.loads, 1);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.pumpWidget(view());
        await tester.pump();
        expect(find.text('2000 × 2000'), findsOneWidget);
        expect(original.loads, 1);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        final closed = work.dispose();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        await tester.pump();
        await tester.runAsync(() => closed);
      }
    },
  );

  testWidgets(
    'split images show full dimensions and switching clears stale label',
    (tester) async {
      final first = _Provider(
        Future.value(img.encodePng(img.Image(width: 800, height: 400))),
      );
      final pending = Completer<Uint8List>();
      final second = _Provider(pending.future);
      Widget view(ImageProvider image, {bool enabled = true}) => MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            child: ComicImage(
              image: image,
              width: double.infinity,
              splitWideImage: true,
              showImageDimensions: enabled,
            ),
          ),
        ),
      );
      await tester.pumpWidget(view(first));
      for (
        var i = 0;
        i < 80 && find.text('800 × 400').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.text('800 × 400'), findsOneWidget);
      expect(find.text('400 × 800'), findsNothing);
      await tester.pumpWidget(view(first, enabled: false));
      expect(find.byType(ImageDimensionsOverlay), findsNothing);
      await tester.pumpWidget(view(second));
      expect(find.text('800 × 400'), findsNothing);
      pending.complete(img.encodePng(img.Image(width: 40, height: 90)));
      for (var i = 0; i < 80 && find.text('40 × 90').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.text('40 × 90'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await tester.pump();
    },
  );

  testWidgets(
    'overlay preserves image bounds with large text and ignores gestures',
    (tester) async {
      var taps = 0;
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(3)),
              child: Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const ImageDimensionsOverlay(
                    size: Size(12345, 67890),
                    child: SizedBox(width: 72, height: 100),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(
          tester.getSize(find.byType(ImageDimensionsOverlay)),
          const Size(72, 100),
        );
        expect(
          find.bySemanticsLabel('Image dimensions: 12345 × 67890 pixels'),
          findsOneWidget,
        );
        await tester.tap(find.byType(ImageDimensionsOverlay));
        expect(taps, 1);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('dimension observer joins the replacement stream after retry', (
    tester,
  ) async {
    final provider = _RetryProvider();
    final states = <AutoReadingImageState>[];
    final work = ImageWork();
    final image = ReaderDisplayImageProvider(provider, work);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 120,
            height: 120,
            child: ReaderImageDimensions(
              image: image,
              onLoadState: states.add,
              builder: (reload) =>
                  TextButton(onPressed: reload, child: const Text('Retry')),
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.text('24 × 48'), findsNothing);
      expect(states, [
        AutoReadingImageState.loading,
        AutoReadingImageState.failed,
      ]);
      await tester.tap(find.text('Retry'));
      for (var i = 0; i < 80 && find.text('24 × 48').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.text('24 × 48'), findsOneWidget);
      expect(provider.loads, 2);
      expect(states, [
        AutoReadingImageState.loading,
        AutoReadingImageState.failed,
        AutoReadingImageState.loading,
        AutoReadingImageState.ready,
      ]);
    } finally {
      await tester.pumpWidget(const SizedBox());
      final closed = work.dispose();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await tester.pump();
      await tester.runAsync(() => closed);
    }
  });
}
