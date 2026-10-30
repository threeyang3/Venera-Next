import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/annotations/annotations.dart';

void main() {
  final session = AnnotationSession();
  final page = session.anchor(
    chapterId: 'one',
    imageNumber: 1,
    width: 1000,
    height: 2000,
  );
  testWidgets(
    'hover emphasizes the topmost rectangle and keeps reading gestures transparent',
    (tester) async {
      final notes = AnnotationSession();
      final anchor = notes.anchor(
        chapterId: 'hover',
        imageNumber: 1,
        width: 800,
        height: 600,
      );
      notes.add(
        anchor,
        AnnotationKind.region,
        'Outer',
        rect: ContentRect(.2, .2, .7, .7),
      );
      notes.add(
        anchor,
        AnnotationKind.region,
        'Inner',
        rect: ContentRect(.3, .3, .6, .6),
      );
      final boundaryKey = GlobalKey();
      var taps = 0, drags = 0, hovers = 0;
      Widget view({
        bool visible = true,
        double dx = 0,
        ViewportTransform? transform,
      }) => MaterialApp(
        home: RepaintBoundary(
          key: boundaryKey,
          child: Stack(
            children: [
              MouseRegion(
                onHover: (_) => hovers++,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  onPanUpdate: (_) => drags++,
                  child: const ColoredBox(
                    color: Colors.white,
                    child: SizedBox.expand(),
                  ),
                ),
              ),
              Positioned.fill(
                child: AnnotationOverlay(
                  page: anchor,
                  transform:
                      transform ?? ViewportTransform(800, 0, 0, 600, dx, 0),
                  annotations: notes.forPage(anchor),
                  selecting: false,
                  visible: visible,
                  onSelected: (_, _) => fail('Reading selected a region'),
                ),
              ),
            ],
          ),
        ),
      );
      Future<({int width, Uint8List bytes})> snapshot() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        return (await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final data = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            return (width: image.width, bytes: data!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        }))!;
      }

      int changed(
        ({int width, Uint8List bytes}) a,
        ({int width, Uint8List bytes}) b,
        Rect area,
      ) {
        var count = 0;
        for (var y = area.top.toInt(); y < area.bottom.toInt(); y++) {
          for (var x = area.left.toInt(); x < area.right.toInt(); x++) {
            final index = (y * a.width + x) * 4;
            if (a.bytes[index] != b.bytes[index] ||
                a.bytes[index + 1] != b.bytes[index + 1] ||
                a.bytes[index + 2] != b.bytes[index + 2] ||
                a.bytes[index + 3] != b.bytes[index + 3]) {
              count++;
            }
          }
        }
        return count;
      }

      await tester.pumpWidget(view());
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: const Offset(20, 20));
      await tester.pump();
      final before = await snapshot();
      await mouse.moveTo(const Offset(400, 300));
      await tester.pump();
      final hovered = await snapshot();
      expect(
        changed(before, hovered, const Rect.fromLTRB(235, 175, 485, 365)),
        greaterThan(100),
      );
      expect(
        changed(before, hovered, const Rect.fromLTRB(150, 110, 170, 430)),
        0,
      );
      expect(hovers, greaterThan(0));
      await tester.tapAt(const Offset(400, 300));
      await tester.dragFrom(const Offset(400, 300), const Offset(80, 70));
      expect(taps, 1);
      expect(drags, greaterThan(0));
      await mouse.moveTo(const Offset(20, 20));
      await tester.pump();
      expect(
        changed(before, await snapshot(), const Rect.fromLTRB(0, 0, 800, 600)),
        0,
      );
      await mouse.moveTo(const Offset(400, 300));
      await tester.pump();
      await tester.pumpWidget(view(dx: 500));
      final moved = await snapshot();
      await mouse.moveTo(const Offset(20, 20));
      await tester.pump();
      expect(
        changed(moved, await snapshot(), const Rect.fromLTRB(0, 0, 800, 600)),
        0,
      );
      await tester.pumpWidget(view(visible: false));
      final hidden = await snapshot();
      await mouse.moveTo(const Offset(400, 300));
      await tester.pump();
      expect(
        changed(hidden, await snapshot(), const Rect.fromLTRB(0, 0, 800, 600)),
        0,
      );
      await mouse.moveTo(const Offset(20, 20));
      final rotated = ViewportTransform.centered(
        sourceWidth: 800,
        sourceHeight: 600,
        viewportWidth: 800,
        viewportHeight: 600,
        scale: .65,
        panX: 15,
        panY: 10,
        rotation: .3,
      );
      await tester.pumpWidget(view(transform: rotated));
      final rotatedBefore = await snapshot();
      final target = rotated.toViewport(ContentPoint(.5, .5));
      await mouse.moveTo(Offset(target.x, target.y));
      await tester.pump();
      expect(
        changed(
          rotatedBefore,
          await snapshot(),
          const Rect.fromLTRB(0, 0, 800, 600),
        ),
        greaterThan(100),
      );
      await mouse.moveTo(const Offset(20, 20));
      await tester.pump();
      expect(
        changed(
          rotatedBefore,
          await snapshot(),
          const Rect.fromLTRB(0, 0, 800, 600),
        ),
        0,
      );
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('drag inversely maps known viewport pixels into source content', (
    tester,
  ) async {
    ContentRect? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: AnnotationOverlay(
          page: page,
          transform: ViewportTransform(400, 0, 0, 600, 200, 0),
          annotations: const [],
          selecting: true,
          onSelected: (_, rect) => selected = rect,
        ),
      ),
    );
    await tester.dragFrom(const Offset(300, 120), const Offset(200, 360));
    expect(selected, isNotNull);
    expect(selected!.x0, closeTo(0.25, 0.001));
    expect(selected!.y0, closeTo(0.2, 0.001));
    expect(selected!.x1, closeTo(0.75, 0.001));
    expect(selected!.y1, closeTo(0.8, 0.001));
  });
  testWidgets('reading mode lets taps pass through; selection mode captures', (
    tester,
  ) async {
    var taps = 0, selections = 0;
    Widget build(bool selecting) => MaterialApp(
      home: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox.expand(),
          ),
          Positioned.fill(
            child: AnnotationOverlay(
              page: page,
              transform: ViewportTransform(800, 0, 0, 600, 0, 0),
              annotations: const [],
              selecting: selecting,
              onSelected: (_, _) => selections++,
            ),
          ),
        ],
      ),
    );
    await tester.pumpWidget(build(false));
    await tester.tapAt(const Offset(200, 200));
    expect(taps, 1);
    await tester.pumpWidget(build(true));
    await tester.dragFrom(const Offset(200, 200), const Offset(200, 200));
    expect(taps, 1);
    expect(selections, 1);
  });
  testWidgets('page change or resize during drag discards stale selection', (
    tester,
  ) async {
    var saved = 0;
    final second = session.anchor(
      chapterId: 'two',
      imageNumber: 1,
      width: 1000,
      height: 2000,
    );
    Widget build(PageAnchor anchor, double width) => MaterialApp(
      home: AnnotationOverlay(
        page: anchor,
        transform: ViewportTransform(width, 0, 0, 600, 0, 0),
        annotations: const [],
        selecting: true,
        onSelected: (_, _) => saved++,
      ),
    );
    for (final replacement in [(second, 800.0), (page, 700.0)]) {
      await tester.pumpWidget(build(page, 800));
      final gesture = await tester.startGesture(const Offset(100, 100));
      await gesture.moveTo(const Offset(200, 200));
      await tester.pumpWidget(build(replacement.$1, replacement.$2));
      await gesture.moveTo(const Offset(300, 300));
      await gesture.up();
      expect(saved, 0);
    }
  });
  testWidgets('letterbox drag creates no selection', (tester) async {
    var saved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AnnotationOverlay(
          page: page,
          transform: ViewportTransform(300, 0, 0, 600, 250, 0),
          annotations: const [],
          selecting: true,
          onSelected: (_, _) => saved = true,
        ),
      ),
    );
    await tester.dragFrom(const Offset(10, 100), const Offset(200, 200));
    expect(saved, isFalse);
  });
}
