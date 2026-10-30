import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_view/photo_view.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/features/annotations/data/annotation_repository.dart';
import 'package:venera_next/features/annotations/annotations.dart';
import 'package:venera_next/features/reader/annotation_layer.dart';

void main() {
  late AnnotationSession session;
  late PhotoViewController photo;
  late MemoryImage image;
  late bool current;
  late bool inputActive;
  late GlobalKey repaint;
  setUp(() {
    session = AnnotationSession();
    photo = PhotoViewController();
    current = true;
    inputActive = false;
    repaint = GlobalKey();
    final pixels = img.Image(width: 400, height: 600)
      ..clear(img.ColorRgb8(245, 245, 245));
    for (final top in [12, 308]) {
      img.drawRect(
        pixels,
        x1: 12,
        y1: top,
        x2: 388,
        y2: top + 280,
        color: img.ColorRgb8(30, 30, 30),
        thickness: 4,
      );
    }
    img.drawString(
      pixels,
      'Source image 400 x 600',
      font: img.arial24,
      x: 30,
      y: 30,
      color: img.ColorRgb8(30, 30, 30),
    );
    img.drawLine(
      pixels,
      x1: 20,
      y1: 260,
      x2: 370,
      y2: 90,
      color: img.ColorRgb8(60, 60, 60),
      thickness: 3,
    );
    img.drawCircle(
      pixels,
      x: 200,
      y: 440,
      radius: 75,
      color: img.ColorRgb8(30, 30, 30),
    );
    image = MemoryImage(Uint8List.fromList(img.encodePng(pixels)));
  });

  Widget build({bool layer = true, int imageNumber = 1}) => MaterialApp(
    home: Scaffold(
      body: RepaintBoundary(
        key: repaint,
        child: layer
            ? ReaderAnnotationLayer(
                key: ValueKey(imageNumber),
                image: image,
                photo: photo,
                session: session,
                chapterId: 'one',
                imageNumber: imageNumber,
                isCurrent: () => current,
                onInputChanged: (value) {
                  inputActive = value;
                  session.inputActive = value;
                },
                child: PhotoView(
                  imageProvider: image,
                  controller: photo,
                  filterQuality: FilterQuality.medium,
                  backgroundDecoration: const BoxDecoration(
                    color: Color(0xffe4e4e4),
                  ),
                ),
              )
            : const SizedBox.expand(),
      ),
    ),
  );

  PageAnchor page([int number = 1]) => session.anchor(
    chapterId: 'one',
    imageNumber: number,
    width: 400,
    height: 600,
  );

  Future<void> mount(WidgetTester tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      photo.dispose();
    });
    await tester.pumpWidget(build());
    await tester.runAsync(() async {
      await image.obtainKey(ImageConfiguration.empty);
    });
    for (
      var i = 0;
      i < 30 &&
          find
              .byTooltip(session.persistent ? '区域批注' : '区域批注（临时）')
              .evaluate()
              .isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(
      find.byTooltip(session.persistent ? '区域批注' : '区域批注（临时）'),
      findsOneWidget,
    );
  }

  testWidgets(
    'persistent editor keeps failed-write text and commits after retry',
    (tester) async {
      final store = AnnotationRepository(
        sqlite3.openInMemory(),
        ownsConnection: true,
      );
      session = AnnotationSession.persistent(
        store,
        libraryKey: 'book',
        title: 'Book',
      );
      addTearDown(store.close);
      await mount(tester);
      store.db.execute(
        "CREATE TRIGGER fail_insert BEFORE INSERT ON annotations BEGIN SELECT RAISE(ABORT,'disk failure'); END",
      );
      await tester.tap(find.byTooltip('整页笔记'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '失败后保留这段文字');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('保存失败'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '失败后保留这段文字',
      );
      expect(session.all, isEmpty);
      expect(inputActive, isTrue);
      store.db.execute('DROP TRIGGER fail_insert');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(session.all.single.text, '失败后保留这段文字');
      expect(store.list(session.documentId).single.id, session.all.single.id);
      expect(inputActive, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reopening a reader restores persisted notes in its inspector', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'reader-annotations-',
    );
    final path = '${directory.path}/annotations.db';
    AnnotationSession open() => AnnotationSession.persistent(
      AnnotationRepository.open(path),
      libraryKey: 'book',
      title: 'Book',
      ownsStore: true,
    );
    session = open();
    addTearDown(() {
      session.close();
      directory.deleteSync(recursive: true);
    });
    await mount(tester);
    await tester.tap(find.byTooltip('整页笔记'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '跨阅读会话恢复');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final id = session.all.single.id;
    await tester.pumpWidget(const SizedBox());
    session.close();
    session = open();
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(session.all.single.id, id);
    await tester.tap(find.byTooltip('本页批注 (1)'));
    await tester.pumpAndSettle();
    expect(find.text('跨阅读会话恢复'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'actual PhotoView selection saves natural coordinates and keeps zoom',
    (tester) async {
      await mount(tester);
      photo.updateMultiple(scale: 2.5, position: const Offset(30, -20));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('区域批注（临时）'));
      await tester.pumpAndSettle();
      expect(inputActive, isTrue);
      // Source .25,.4 -> screen 180,130 at scale 2.5 and pan 30,-20.
      await tester.dragFrom(const Offset(180, 130), const Offset(400, 450));
      await tester.pumpAndSettle();
      expect(find.text('区域批注'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '画面的留白');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final note = session.forPage(page()).single;
      expect(note.anchor.sourceImageNumber, 1);
      expect(note.rect!.x0, closeTo(0.25, 0.002));
      expect(note.rect!.y0, closeTo(0.4, 0.002));
      expect(note.rect!.x1, closeTo(0.65, 0.002));
      expect(note.rect!.y1, closeTo(0.7, 0.002));
      expect(note.text, '画面的留白');
      expect(photo.scale, 2.5);
      expect(photo.position, const Offset(30, -20));
      expect(inputActive, isFalse);
      expect(tester.takeException(), isNull);
      final output = Platform.environment['COMICNOTES_QA_DIR'];
      if (output != null) {
        await tester.runAsync(() async {
          final boundary =
              repaint.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final rendered = await boundary.toImage();
          try {
            final png = await rendered.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(output).create(recursive: true);
            await File(
              '$output/annotation-widget.png',
            ).writeAsBytes(png!.buffer.asUint8List());
            await File('$output/annotation.json').writeAsString(
              const JsonEncoder.withIndent('  ').convert(note.toJson()),
            );
          } finally {
            rendered.dispose();
          }
        });
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('page note supports edit and delete with unchanged UUID', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byTooltip('整页笔记'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '第一版');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final id = session.forPage(page()).single.id;
    await tester.tap(find.byTooltip('本页批注 (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第一版'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '第二版');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(session.forPage(page()).single.id, id);
    expect(session.forPage(page()).single.text, '第二版');
    expect(inputActive, isTrue);
    await tester.tap(find.byTooltip('删除批注'));
    await tester.pumpAndSettle();
    expect(session.forPage(page()), isEmpty);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(inputActive, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Esc exits selection without saving or retaining input hold', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byTooltip('区域批注（临时）'));
    await tester.pump();
    expect(inputActive, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(inputActive, isFalse);
    expect(session.forPage(page()), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'editor completed after target invalidation never saves to another page',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byTooltip('整页笔记'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '旧页');
      current = false;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(session.forPage(page()), isEmpty);
      expect(session.forPage(page(2)), isEmpty);
      expect(inputActive, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('closing reader with editor open discards the pending draft', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byTooltip('整页笔记'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '不应保存');
    await tester.pumpWidget(build(layer: false));
    await tester.pumpAndSettle();
    // The navigator may retain the dialog; completing it still cannot save.
    if (find.text('保存').evaluate().isNotEmpty) {
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
    }
    expect(session.forPage(page()), isEmpty);
    expect(inputActive, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
