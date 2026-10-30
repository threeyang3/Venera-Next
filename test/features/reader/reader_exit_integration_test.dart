import 'package:venera_next/app_runtime/annotation_manual_recovery.dart';
import 'package:venera_next/app_shell/import_commands.dart';
import 'package:venera_next/features/reader/annotation_layer.dart';
import 'package:venera_next/features/reader/display_image_provider.dart';
import 'package:venera_next/features/favorites/favorites_scope.dart';
import 'package:venera_next/features/annotations/annotations.dart';
import 'package:venera_next/features/annotations/data/annotation_repository.dart';
import 'package:venera_next/app_runtime/annotations.dart';
import 'package:venera_next/app_runtime/annotation_export_binding.dart';
import 'package:venera_next/app_runtime/annotation_navigation.dart';
import 'package:venera_next/app_runtime/annotation_source_relocation.dart';
import 'package:venera_next/app_runtime/annotation_recovery.dart';
import 'package:venera_next/foundation/comic_source_provenance.dart';
import 'package:venera_next/foundation/annotation_link_contract.dart';
import 'package:venera_next/routing/app_links.dart';
import 'package:venera_next/features/reader/reader_session_scope.dart';
import 'package:venera_next/features/history/history_scope.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_view/photo_view.dart';
import 'package:venera_next/components/message.dart';
import 'package:venera_next/components/window_frame.dart';
import 'package:venera_next/components/window_selection_task.dart';
import 'package:venera_next/app_runtime/application_host.dart';
import 'package:venera_next/app_runtime/core_bootstrap.dart';
import 'package:venera_next/features/comic_source/source_update_service.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart'
    show
        ComicSource,
        ComicSourceManager,
        configureComicSourceRegistry,
        ChapterCommentsLoader,
        SendChapterCommentFunc,
        LikeCommentFunc,
        LoadComicPagesFunc,
        VoteCommentFunc;
import 'package:venera_next/features/reader/chapter_comments.dart';
import 'package:venera_next/foundation/res.dart';
import 'package:venera_next/foundation/selection_operation.dart';
import 'package:venera_next/foundation/image_work.dart';
import 'package:venera_next/foundation/persistence_failure.dart';
import 'package:venera_next/features/comic_source/models.dart';
import 'package:venera_next/features/favorites/favorites_manager.dart';
import 'package:venera_next/features/history/history.dart';
import 'package:venera_next/features/local_comics/local_comics.dart';
import 'package:venera_next/features/reader/auto_reading.dart';
import 'package:venera_next/features/reader/comic_image.dart';
import 'package:venera_next/features/reader/continuous_view.dart';
import 'package:venera_next/features/reader/platform_effects.dart';
import 'package:venera_next/features/reader/image_export.dart';
import 'package:venera_next/features/reader/image_position.dart';
import 'package:venera_next/features/reader/image_downloads.dart';
import 'package:venera_next/features/reader/gallery_view.dart';
import 'package:venera_next/features/reader/layout_detection.dart';
import 'package:venera_next/features/reader/reader_page.dart';
import 'package:venera_next/features/reader/reader_session.dart';
import 'package:venera_next/features/reader/exit_guard.dart';
import 'package:venera_next/features/reader/history_writer.dart';
import 'package:venera_next/features/reader/volume_controller.dart';
import 'package:venera_next/features/reader/window_controller.dart';
import 'package:venera_next/features/reader/top_bar.dart';
import 'package:venera_next/features/reader/scaffold.dart';
import 'package:venera_next/features/reader/progress_bar.dart';
import 'package:venera_next/features/reader/images_host.dart';
import 'package:venera_next/features/reader/chapters.dart';
import 'package:venera_next/features/reader/brightness.dart';
import 'package:venera_next/features/reader/settings_panel.dart';
import 'package:venera_next/routing/settings.dart' show ReaderSettings;
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/routing/app_navigation.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/cache_manager.dart';
import 'package:venera_next/foundation/app_data_operations.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/foundation/comic_layout.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/network/images.dart';
import 'package:venera_next/network/request_scope.dart';
import 'package:window_manager/window_manager.dart';

import '../../support/data_sync_fixture.dart';

void main() {
  final binding = _ReaderExitBinding();
  setUpAll(() async {
    final fontPath = Platform.environment['WINDOW_OWNER_QA_FONT'];
    if (fontPath != null) {
      final font = FontLoader('WindowOwnerQA')
        ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView));
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        );
      await icons.load();
    }
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (_) async => false,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
  });

  for (final cancel in [false, true]) {
    testWidgets(
      'manual recovery UI restores legacy notes onto explicitly chosen Reader source image; cancel=$cancel',
      (tester) async {
        final fixture = await _ReaderFixture.create(tester);
        late Annotation saved;
        late String documentId;
        try {
          await tester.runAsync(() async {
            final old = AnnotationSession.persistent(
              AnnotationRepository.open('${App.dataPath}/annotations.db'),
              libraryKey: 'orphan:manual-preview',
              title: 'Old manual book',
              ownsStore: true,
            );
            final page = old.anchor(
              chapterId: 'legacy',
              imageNumber: 7,
              width: 100,
              height: 150,
              sourceIdentity: 'lost/7.png',
              assetUri: 'file:///missing/lost/7.png',
            );
            saved = old.add(
              page,
              AnnotationKind.region,
              'Legacy composition',
              rect: ContentRect(.2, .3, .7, .8),
            );
            old.setTags(saved.id, ['legacy']);
            documentId = old.documentId;
            old.close();
          });
          await fixture.mount(
            tester,
            pushed: false,
            withWindow: false,
            persistentAnnotations: true,
          );
          await _pumpUntil(
            tester,
            () => find.byTooltip('全书批注').evaluate().isNotEmpty,
          );
          final reader = fixture.readerKey.currentState!;
          final targetId = reader.annotations.documentId;
          await tester.tap(find.byTooltip('全书批注').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('手工逐页关联旧批注'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Old manual book'));
          await _pumpUntil(
            tester,
            () =>
                find.text('逐页关联旧批注').evaluate().isNotEmpty &&
                find
                    .byType(DropdownButtonFormField<String>)
                    .evaluate()
                    .isNotEmpty,
          );
          expect(reader.annotations.inputActive, isTrue);
          expect(reader.annotations.documentId, targetId);
          if (cancel) {
            void Function()? release;
            final draining = reader.imageWork.prepareForExit().then(
              (value) => release = value,
            );
            await _pumpUntil(tester, () => release != null);
            await draining;
            release!();
            await tester.pumpAndSettle();
            expect(find.text('逐页关联旧批注'), findsNothing);
            expect(reader.annotations.documentId, targetId);
            expect(reader.annotations.inputActive, isFalse);
            await tester.runAsync(() async {
              final store = AnnotationRepository.open(
                '${App.dataPath}/annotations.db',
              );
              try {
                expect(
                  store.document(documentId).libraryKey,
                  'orphan:manual-preview',
                );
                expect(store.list(documentId).single.id, saved.id);
                expect(store.list(targetId), isEmpty);
              } finally {
                store.close();
              }
            });
            expect(tester.takeException(), isNull);
            return;
          }
          await tester.tap(find.byType(DropdownButtonFormField<String>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('one · 2 · one/2.png').last);
          await tester.pumpAndSettle();
          final preview = tester
              .widgetList<AnnotationOverlay>(find.byType(AnnotationOverlay))
              .singleWhere(
                (overlay) => overlay.page.pageId == saved.anchor.pageId,
              );
          expect(
            preview.annotations.single.rect!.toJson(),
            saved.rect!.toJson(),
          );
          await tester.ensureVisible(find.byType(Checkbox));
          await tester.tap(find.byType(Checkbox));
          await tester.pump();
          await tester.tap(find.text('确认恢复旧批注'));
          await _pumpUntil(
            tester,
            () => reader.annotations.documentId == documentId,
          );
          await _pumpUntil(tester, () => _annotationImagesReady(reader));
          await tester.pumpAndSettle();
          final restored = reader.annotations.all.single;
          expect(restored.id, saved.id);
          expect(restored.anchor.pageId, saved.anchor.pageId);
          expect(restored.anchor.chapterId, 'one');
          expect(restored.anchor.sourceImageNumber, 2);
          expect(restored.tags, ['legacy']);
          expect(reader.annotations.inputActive, isFalse);
          final destination = await tester.runAsync(
            () => resolveAnnotationLinkDestination(
              AnnotationLink(documentId: documentId, annotationId: saved.id),
            ),
          );
          expect(destination!.imageNumber, 2);
          await tester.runAsync(() => reader.jumpToAnnotation(restored));
          await _pumpUntil(tester, () => reader.page == 2);
          expect(reader.annotations.selectedId, saved.id);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      skip: !const bool.fromEnvironment('COMICNOTES_POC'),
    );
  }

  testWidgets(
    'global open reaches actual Reader without losing viewport or modal input',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      try {
        await tester.runAsync(() => LocalFavoritesManager().init());
        await fixture.mount(
          tester,
          pushed: true,
          withWindow: false,
          persistentAnnotations: true,
          globalImport: true,
        );
        await _pumpUntil(
          tester,
          () => find.byTooltip('整页笔记').evaluate().length == 1,
        );
        final reader = fixture.readerKey.currentState!;
        final viewport = reader.imageViewController;
        Future<void> open() async {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          await tester.pumpAndSettle();
        }

        reader.focusNode.requestFocus();
        await tester.pump();
        await open();
        expect(find.text('Import Comics'), findsOneWidget);
        await open();
        expect(find.text('Import Comics'), findsOneWidget);
        appNavigation.rootNavigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
        expect(fixture.readerKey.currentState, same(reader));
        expect(reader.imageViewController, same(viewport));
        expect(reader.page, 1);
        await tester.tap(find.byTooltip('整页笔记'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Draft remains');
        await open();
        expect(find.text('Import Comics'), findsNothing);
        expect(find.text('Draft remains'), findsOneWidget);
        expect(reader.annotations.inputActive, isTrue);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(reader.annotations.all, isEmpty);
        expect(reader.annotations.inputActive, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
        await tester.runAsync(() => LocalFavoritesManager().closeAndWait());
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  for (final scenario in [
    (mode: ReaderMode.galleryLeftToRight, count: 1, target: 1),
    (mode: ReaderMode.galleryRightToLeft, count: 2, target: 2),
    (mode: ReaderMode.continuousTopToBottom, count: 1, target: 2),
    (mode: ReaderMode.waterfallTopToBottom, count: 1, target: 2),
  ]) {
    testWidgets(
      'annotation context menu acts on the clicked original; ${scenario.mode.key}; count=${scenario.count}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(600, 1400);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        String? clipboard;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                clipboard = (call.arguments as Map)['text'] as String;
              }
              return null;
            });
        final fixture = await _ReaderFixture.create(tester);
        try {
          appdata.settings['readerMode'] = scenario.mode.key;
          appdata.settings['readerScreenPicNumberForLandscape'] =
              scenario.count;
          appdata.settings['readerScreenPicNumberForPortrait'] = scenario.count;
          appdata.settings['showSingleImageOnFirstPage'] = false;
          appdata.settings['splitDualPage'] = false;
          await fixture.mount(
            tester,
            pushed: false,
            withWindow: false,
            persistentAnnotations: true,
          );
          await _pumpUntil(
            tester,
            () => find.byTooltip('区域批注').evaluate().length == 1,
          );
          final reader = fixture.readerKey.currentState!;
          final anchor = reader.annotations.anchor(
            chapterId: 'one',
            imageNumber: scenario.target,
            width: 100,
            height: 150,
            sourceIdentity: reader.images![scenario.target - 1],
          );
          final note = reader.annotations.add(
            anchor,
            AnnotationKind.region,
            'Clicked original',
            rect: ContentRect(.15, .15, .4, .4),
          );
          reader.update();
          await tester.pumpAndSettle();
          Future<void> openMenu() async {
            final overlay = tester.widget<AnnotationOverlay>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is AnnotationOverlay &&
                    widget.page.pageId == anchor.pageId,
              ),
            );
            final point = overlay.transform.toViewport(ContentPoint(.25, .25));
            final origin = tester.getTopLeft(
              find.byWidgetPredicate((widget) => identical(widget, overlay)),
            );
            await tester.tapAt(
              origin + Offset(point.x, point.y),
              buttons: kSecondaryMouseButton,
            );
            await tester.pumpAndSettle();
            expect(find.text('编辑批注'), findsOneWidget);
            expect(find.text('Settings'), findsNothing);
            expect(reader.annotations.inputActive, isTrue);
          }

          await openMenu();
          await tester.tapAt(const Offset(20, 20));
          await tester.pumpAndSettle();
          expect(find.text('编辑批注'), findsNothing);
          expect(reader.annotations.inputActive, isFalse);
          expect(reader.annotations.all.single.id, note.id);
          await openMenu();
          await tester.tap(find.text('复制批注文字'));
          await tester.pumpAndSettle();
          expect(clipboard, 'Clicked original');
          expect(reader.annotations.inputActive, isFalse);
          await openMenu();
          await tester.tap(find.text('复制批注引用'));
          await tester.pumpAndSettle();
          final link = AnnotationLink.parse(Uri.parse(clipboard!))!;
          expect(link.documentId, reader.annotations.documentId);
          expect(link.annotationId, note.id);
          await openMenu();
          await tester.tap(find.text('编辑批注'));
          await tester.pumpAndSettle();
          expect(find.byType(AnnotationEditor), findsOneWidget);
          await tester.enterText(
            find.byType(TextField),
            'Updated clicked original',
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(reader.annotations.all.single.id, note.id);
          expect(
            reader.annotations.all.single.anchor.sourceImageNumber,
            scenario.target,
          );
          expect(
            reader.annotations.all.single.text,
            'Updated clicked original',
          );
          expect(reader.annotations.inputActive, isFalse);
          if (scenario.target == 1) {
            final failing = AnnotationRepository.open(
              '${App.dataPath}/annotations.db',
            );
            try {
              expect(
                failing.document(reader.annotations.documentId),
                isNotNull,
              );
              failing.db.execute(
                "CREATE TRIGGER fail_context_delete BEFORE UPDATE ON annotations BEGIN SELECT RAISE(ABORT, 'context delete failed'); END",
              );
              await openMenu();
              await tester.tap(find.text('删除批注'));
              await tester.pumpAndSettle();
              expect(find.text('批注操作失败'), findsOneWidget);
              expect(reader.annotations.all.single.id, note.id);
              expect(reader.annotations.inputActive, isTrue);
              await tester.tap(find.text('关闭'));
              await tester.pumpAndSettle();
              expect(reader.annotations.inputActive, isFalse);
            } finally {
              failing.db.execute('DROP TRIGGER IF EXISTS fail_context_delete');
              failing.close();
            }
          }
          await openMenu();
          await tester.tap(find.text('删除批注'));
          await tester.pumpAndSettle();
          expect(reader.annotations.all, isEmpty);
          expect(reader.annotations.inputActive, isFalse);
          final stored = AnnotationRepository.open(
            '${App.dataPath}/annotations.db',
          );
          try {
            expect(stored.document(reader.annotations.documentId), isNotNull);
            expect(stored.list(reader.annotations.documentId), isEmpty);
          } finally {
            stored.close();
          }
          await tester.tapAt(
            const Offset(300, 1000),
            buttons: kSecondaryMouseButton,
          );
          await tester.pumpAndSettle();
          expect(find.text('Settings'), findsOneWidget);
          expect(find.text('编辑批注'), findsNothing);
          await tester.tapAt(const Offset(590, 1300));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      skip: !const bool.fromEnvironment('COMICNOTES_POC'),
    );
  }

  for (final change in ['page', 'note']) {
    testWidgets(
      'annotation context menu rejects retired $change',
      (tester) async {
        final fixture = await _ReaderFixture.create(tester);
        try {
          await fixture.mount(
            tester,
            pushed: false,
            withWindow: false,
            persistentAnnotations: true,
          );
          await _pumpUntil(
            tester,
            () => find.byTooltip('区域批注').evaluate().length == 1,
          );
          final reader = fixture.readerKey.currentState!;
          final overlay = tester.widget<AnnotationOverlay>(
            find.byType(AnnotationOverlay),
          );
          final note = reader.annotations.add(
            overlay.page,
            AnnotationKind.region,
            'Keep original',
            rect: ContentRect(.2, .2, .6, .6),
          );
          reader.update();
          await tester.pumpAndSettle();
          final current = tester.widget<AnnotationOverlay>(
            find.byType(AnnotationOverlay),
          );
          final point = current.transform.toViewport(ContentPoint(.4, .4));
          await tester.tapAt(
            tester.getTopLeft(find.byType(AnnotationOverlay)) +
                Offset(point.x, point.y),
            buttons: kSecondaryMouseButton,
          );
          await tester.pumpAndSettle();
          expect(find.text('删除批注'), findsOneWidget);
          if (change == 'page') {
            reader.controller.toPage(2, animated: false);
          } else {
            reader.annotations.update(note.id, 'Newer edit');
            reader.update();
          }
          await tester.pumpAndSettle();
          expect(find.text('删除批注'), findsNothing);
          expect(
            reader.annotations.all.single.text,
            change == 'page' ? 'Keep original' : 'Newer edit',
          );
          expect(reader.annotations.inputActive, isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      skip: !const bool.fromEnvironment('COMICNOTES_POC'),
    );
  }

  for (final mode in [
    ReaderMode.continuousTopToBottom,
    ReaderMode.waterfallTopToBottom,
  ]) {
    for (final invert in [false, true]) {
      testWidgets(
        'split-wide annotations keep one original identity; ${mode.key}; invert=$invert',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(600, 1000);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final fixture = await _ReaderFixture.create(tester);
          try {
            await tester.runAsync(() async {
              final wide = img.Image(width: 300, height: 100);
              img.fillRect(
                wide,
                x1: 0,
                y1: 0,
                x2: 149,
                y2: 99,
                color: img.ColorRgb8(220, 30, 40),
              );
              img.fillRect(
                wide,
                x1: 150,
                y1: 0,
                x2: 299,
                y2: 99,
                color: img.ColorRgb8(20, 70, 230),
              );
              File(
                '${LocalManager().path}/book/one/1.png',
              ).writeAsBytesSync(img.encodePng(wide));
            });
            appdata.settings['readerMode'] = mode.key;
            appdata.settings['splitDualPage'] = true;
            appdata.settings['splitDualPageInvert'] = invert;
            await fixture.mount(
              tester,
              pushed: false,
              withWindow: false,
              persistentAnnotations: true,
            );
            await _pumpUntil(
              tester,
              () => find.byTooltip('区域批注').evaluate().length == 1,
            );
            final reader = fixture.readerKey.currentState!;
            final flow = reader.imageViewController! as ContinuousModeState;
            final photo = flow.photoViewController;
            List<({ViewportTransform transform, Rect clip})> projections() {
              final layer = tester.widget<ReaderAnnotationLayer>(
                find.byType(ReaderAnnotationLayer),
              );
              return [
                layer.geometryBuilder!(Size.zero, Size.zero)!,
                ...layer.additionalGeometries!(),
              ];
            }

            for (final right in [false, true]) {
              await tester.tap(find.byTooltip('区域批注'));
              await tester.pumpAndSettle();
              final sourceStart = ContentPoint(right ? .6 : .1, .35);
              final sourceEnd = ContentPoint(right ? .75 : .25, .65);
              final projection = projections().singleWhere((projection) {
                final point = projection.transform.toViewport(sourceStart);
                return projection.clip.contains(Offset(point.x, point.y));
              });
              final p0 = projection.transform.toViewport(sourceStart);
              final p1 = projection.transform.toViewport(sourceEnd);
              final finder = find.byWidgetPredicate(
                (widget) =>
                    widget is AnnotationOverlay &&
                    widget.selecting &&
                    widget.transform.tx == projection.transform.tx &&
                    widget.transform.ty == projection.transform.ty,
              );
              final overlay = tester.widget<AnnotationOverlay>(finder);
              expect(overlay.page.sourceWidth, 300);
              expect(overlay.page.sourceHeight, 100);
              final origin = tester.getTopLeft(finder);
              await tester.dragFrom(
                origin + Offset(p0.x, p0.y),
                Offset(p1.x - p0.x, p1.y - p0.y),
              );
              await tester.pumpAndSettle();
              expect(find.byType(AnnotationEditor), findsOneWidget);
              await tester.enterText(
                find.byType(TextField),
                right ? 'Right original half' : 'Left original half',
              );
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
              await tester.pumpAndSettle();
              final note = reader.annotations.all.firstWhere(
                (note) => note.text.startsWith(right ? 'Right' : 'Left'),
              );
              expect(note.rect!.x0, closeTo(sourceStart.x, .01));
              expect(note.rect!.x1, closeTo(sourceEnd.x, .01));
              expect(note.rect!.y0, closeTo(.35, .01));
              expect(note.rect!.y1, closeTo(.65, .01));
            }
            expect(reader.annotations.all, hasLength(2));
            expect(
              reader.annotations.all.map((note) => note.anchor.pageId).toSet(),
              hasLength(1),
            );
            final state = flow.imageStates
                .whereType<ComicImageState>()
                .firstWhere(
                  (state) =>
                      (state.widget.image as ReaderDisplayImageProvider)
                          .image
                          .page ==
                      1,
                );
            expect(state.imagePaintSlices.first.source.left, invert ? 0 : .5);
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byType(RepaintBoundary).first,
            );
            final snapshot = await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1);
              try {
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                );
                return (width: image.width, bytes: bytes!.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            });
            for (final right in [false, true]) {
              final source = ContentPoint(right ? .8 : .3, .5);
              final projection = projections().singleWhere((projection) {
                final point = projection.transform.toViewport(source);
                return projection.clip.contains(Offset(point.x, point.y));
              });
              final point = projection.transform.toViewport(source);
              final global =
                  tester.getTopLeft(find.byType(ReaderContinuousView)) +
                  Offset(point.x, point.y);
              final pixel = boundary.globalToLocal(global);
              final index =
                  (pixel.dy.floor() * snapshot!.width + pixel.dx.floor()) * 4;
              final red = snapshot.bytes[index],
                  blue = snapshot.bytes[index + 2];
              expect(right ? blue - red : red - blue, greaterThan(150));
            }
            await tester.tap(find.byTooltip('区域批注'));
            await tester.pumpAndSettle();
            final start = ContentPoint(.6, .35);
            final beforeFlip = projections().singleWhere((projection) {
              final point = projection.transform.toViewport(start);
              return projection.clip.contains(Offset(point.x, point.y));
            });
            final startPoint = beforeFlip.transform.toViewport(start);
            final viewportOrigin = tester.getTopLeft(
              find.byType(ReaderContinuousView),
            );
            final gesture = await tester.startGesture(
              viewportOrigin + Offset(startPoint.x, startPoint.y),
            );
            await gesture.moveBy(const Offset(30, 30));
            await tester.pump();
            appdata.settings['splitDualPageInvert'] = !invert;
            reader.update();
            await tester.pumpAndSettle();
            await gesture.up();
            await tester.pumpAndSettle();
            expect(find.byType(AnnotationEditor), findsNothing);
            expect(reader.annotations.all, hasLength(2));
            await tester.tap(find.byTooltip('取消框选'));
            await tester.pumpAndSettle();
            expect(state.imagePaintSlices.first.source.left, invert ? .5 : 0);
            tester.view.physicalSize = const Size(650, 1100);
            await tester.pumpAndSettle();
            photo.updateMultiple(scale: 1.15, position: const Offset(12, -8));
            await tester.pumpAndSettle();
            final box = state.context.findRenderObject() as RenderBox;
            for (final note in reader.annotations.all) {
              final point = Offset(note.rect!.x0, note.rect!.y0);
              final slice = state.imagePaintSlices.singleWhere(
                (slice) => slice.source.contains(point),
              );
              final actual = box.localToGlobal(
                Offset(
                  slice.destination.left +
                      (point.dx - slice.source.left) /
                          slice.source.width *
                          slice.destination.width,
                  slice.destination.top + point.dy * slice.destination.height,
                ),
              );
              final projection = projections().singleWhere((projection) {
                final mapped = projection.transform.toViewport(
                  ContentPoint(point.dx, point.dy),
                );
                return projection.clip.contains(Offset(mapped.x, mapped.y));
              });
              final mapped = projection.transform.toViewport(
                ContentPoint(point.dx, point.dy),
              );
              final origin = tester.getTopLeft(
                find.byType(ReaderContinuousView),
              );
              expect(
                (actual - (origin + Offset(mapped.x, mapped.y))).distance,
                lessThan(1),
              );
            }
            expect(flow.photoViewController, same(photo));
            expect(
              reader.annotations.all.every(
                (note) => note.anchor.sourceImageNumber == 1,
              ),
              isTrue,
            );
            expect(tester.takeException(), isNull);
          } finally {
            await fixture.dispose(tester);
          }
        },
        skip: !const bool.fromEnvironment('COMICNOTES_POC'),
      );
    }
  }

  testWidgets(
    'spread annotations keep original picker usable in narrow windows',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fixture = await _ReaderFixture.create(tester);
      try {
        appdata.settings['readerScreenPicNumberForLandscape'] = 3;
        appdata.settings['readerScreenPicNumberForPortrait'] = 3;
        appdata.settings['showSingleImageOnFirstPage'] = false;
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          persistentAnnotations: true,
        );
        await _pumpUntil(
          tester,
          () => find.byTooltip('区域批注').evaluate().length == 1,
        );
        final picker = find
            .ancestor(
              of: find.text('批注原图 3'),
              matching: find.byType(SingleChildScrollView),
            )
            .first;
        await tester.drag(picker, const Offset(-300, 0));
        await tester.pumpAndSettle();
        await tester.tap(find.text('批注原图 3'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<ReaderAnnotationLayer>(
                find.byType(ReaderAnnotationLayer),
              )
              .singleWhere((layer) => layer.active)
              .imageNumber,
          3,
        );
        await tester.tap(find.byTooltip('整页笔记'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Narrow third original');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          fixture
              .readerKey
              .currentState!
              .annotations
              .all
              .single
              .anchor
              .sourceImageNumber,
          3,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  for (final mode in [
    ReaderMode.galleryLeftToRight,
    ReaderMode.galleryRightToLeft,
    ReaderMode.galleryTopToBottom,
  ]) {
    for (final count in [2, 3]) {
      testWidgets(
        'spread annotations bind each original image; ${mode.key}; count=$count',
        (tester) async {
          final fixture = await _ReaderFixture.create(
            tester,
            layout: count == 2 ? ComicLayout.longStrip : null,
          );
          try {
            appdata.settings['readerMode'] = mode.key;
            appdata.settings['readerScreenPicNumberForLandscape'] = count;
            appdata.settings['readerScreenPicNumberForPortrait'] = count;
            appdata.settings['showSingleImageOnFirstPage'] = false;
            await fixture.mount(
              tester,
              pushed: false,
              withWindow: false,
              persistentAnnotations: true,
            );
            await _pumpUntil(
              tester,
              () => find.byTooltip('区域批注').evaluate().length == 1,
            );
            final reader = fixture.readerKey.currentState!;
            final gallery = reader.imageViewController! as GalleryModeState;
            final photo = gallery.photoViewControllers[1]!;
            for (var image = 1; image <= count; image++) {
              await tester.tap(find.text('批注原图 $image'));
              await tester.pumpAndSettle();
              if (image == 1) {
                reader.focusNode.requestFocus();
                await tester.pump();
                await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
                await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
                await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
                await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
                await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
              } else {
                await tester.tap(find.byTooltip('区域批注'));
              }
              await tester.pumpAndSettle();
              final positionBefore = gallery.controller.page!;
              final finder = find.byWidgetPredicate(
                (widget) => widget is AnnotationOverlay && widget.selecting,
              );
              final overlay = tester.widget<AnnotationOverlay>(finder);
              expect(overlay.page.sourceImageNumber, image);
              expect(overlay.page.sourceWidth, 100);
              expect(
                overlay.page.sourceHeight,
                count == 2 && image > 1 ? 400 : 150,
              );
              final p0 = overlay.transform.toViewport(ContentPoint(.4, .8));
              final p1 = overlay.transform.toViewport(ContentPoint(.65, .95));
              await tester.dragFrom(
                tester.getTopLeft(finder) + Offset(p0.x, p0.y),
                Offset(p1.x - p0.x, p1.y - p0.y),
              );
              await tester.pumpAndSettle();
              expect(find.byType(AnnotationEditor), findsOneWidget);
              expect(gallery.controller.page, closeTo(positionBefore, .001));
              await tester.enterText(find.byType(TextField), 'Original $image');
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
              await tester.pumpAndSettle();
              final note = reader.annotations.all.firstWhere(
                (note) => note.text == 'Original $image',
              );
              expect(note.anchor.sourceImageNumber, image);
              expect(note.rect!.x0, closeTo(.4, .01));
              expect(note.rect!.y0, closeTo(.8, .01));
              expect(note.rect!.x1, closeTo(.65, .01));
              expect(note.rect!.y1, closeTo(.95, .01));
            }
            expect(
              reader.annotations.all.map((note) => note.anchor.pageId).toSet(),
              hasLength(count),
            );
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = const Size(1000, 720);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetPhysicalSize);
            await tester.pumpAndSettle();
            photo.updateMultiple(
              scale: 1.3,
              position: const Offset(12, -9),
              rotation: .08,
            );
            await tester.pumpAndSettle();
            for (final note in reader.annotations.all) {
              final overlay = tester.widget<AnnotationOverlay>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is AnnotationOverlay &&
                      widget.page.pageId == note.anchor.pageId,
                ),
              );
              final state =
                  gallery.imageStates.entries
                          .firstWhere(
                            (entry) =>
                                entry.value ==
                                note.anchor.sourceImageNumber - 1,
                          )
                          .key
                      as ComicImageState;
              final box = state.context.findRenderObject() as RenderBox;
              final paint = state.imagePaintBounds!;
              final expected = box.localToGlobal(
                Offset(
                  paint.left + paint.width * note.rect!.x0,
                  paint.top + paint.height * note.rect!.y0,
                ),
              );
              final projected = overlay.transform.toViewport(
                ContentPoint(note.rect!.x0, note.rect!.y0),
              );
              final origin = tester.getTopLeft(find.byType(ReaderGalleryView));
              expect(
                (expected - (origin + Offset(projected.x, projected.y)))
                    .distance,
                lessThan(1),
              );
            }
            expect(reader.imageViewController, same(gallery));
            expect(gallery.photoViewControllers[1], same(photo));
            await tester.tap(find.byTooltip('隐藏标注'));
            await tester.pumpAndSettle();
            expect(
              tester
                  .widgetList<AnnotationOverlay>(find.byType(AnnotationOverlay))
                  .where(
                    (overlay) => reader.annotations.all.any(
                      (note) => note.anchor.pageId == overlay.page.pageId,
                    ),
                  )
                  .every((overlay) => !overlay.visible),
              isTrue,
            );
            if (count == 2) {
              reader.controller.toPage(2, animated: false);
              await _pumpUntil(
                tester,
                () =>
                    find.byTooltip('整页笔记').evaluate().length == 1 &&
                    tester
                        .widgetList<ReaderAnnotationLayer>(
                          find.byType(ReaderAnnotationLayer),
                        )
                        .any(
                          (layer) =>
                              layer.active &&
                              layer.imageNumber == 3 &&
                              layer.isCurrent(),
                        ),
              );
              await tester.tap(find.byTooltip('整页笔记'));
              await tester.pumpAndSettle();
              await tester.enterText(find.byType(TextField), 'Last singleton');
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
              await tester.pumpAndSettle();
              expect(
                reader.annotations.all
                    .firstWhere((note) => note.text == 'Last singleton')
                    .anchor
                    .sourceImageNumber,
                3,
              );
            }
            expect(tester.takeException(), isNull);
          } finally {
            await fixture.dispose(tester);
          }
        },
        skip: !const bool.fromEnvironment('COMICNOTES_POC'),
      );
    }
  }

  for (final mode in [
    ReaderMode.continuousTopToBottom,
    ReaderMode.continuousLeftToRight,
    ReaderMode.continuousRightToLeft,
    ReaderMode.waterfallTopToBottom,
  ]) {
    testWidgets(
      'continuous annotations use actual image geometry and keep the viewport; ${mode.key}',
      (tester) async {
        final fixture = await _ReaderFixture.create(tester);
        try {
          appdata.settings['readerMode'] = mode.key;
          appdata.settings['splitDualPage'] = false;
          await fixture.mount(
            tester,
            pushed: false,
            withWindow: false,
            persistentAnnotations: true,
          );
          await _pumpUntil(
            tester,
            () => find.byTooltip('区域批注').evaluate().length == 1,
          );
          final reader = fixture.readerKey.currentState!;
          final flow = reader.imageViewController! as ContinuousModeState;
          final originalPhoto = flow.photoViewController;
          final originalScroll = flow.scrollController;
          reader.focusNode.requestFocus();
          await tester.pump();
          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          await tester.pump();
          final overlayFinder = find.byWidgetPredicate(
            (widget) => widget is AnnotationOverlay && widget.selecting,
          );
          final overlay = tester.widget<AnnotationOverlay>(overlayFinder);
          expect(overlay.page.sourceWidth, 100);
          expect(overlay.page.sourceHeight, 150);
          final p0 = overlay.transform.toViewport(ContentPoint(.1, .1));
          final p1 = overlay.transform.toViewport(ContentPoint(.25, .25));
          await tester.dragFrom(
            tester.getTopLeft(overlayFinder) + Offset(p0.x, p0.y),
            Offset(p1.x - p0.x, p1.y - p0.y),
          );
          await tester.pumpAndSettle();
          expect(find.byType(AnnotationEditor), findsOneWidget);
          await tester.enterText(
            find.byType(TextField),
            'Continuous source note',
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          final note = reader.annotations.all.single;
          expect(note.anchor.sourceImageNumber, 1);
          expect(note.rect!.x0, closeTo(.1, .01));
          expect(note.rect!.y0, closeTo(.1, .01));
          expect(note.rect!.x1, closeTo(.25, .01));
          expect(note.rect!.y1, closeTo(.25, .01));
          expect(flow.scrollController, same(originalScroll));
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1000, 700);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          await tester.pumpAndSettle();
          expect(reader.imageViewController, same(flow));
          expect(flow.photoViewController, same(originalPhoto));
          expect(flow.scrollController, same(originalScroll));
          expect(
            reader.annotations.all.single.rect!.toJson(),
            note.rect!.toJson(),
          );
          await tester.tap(find.byTooltip('区域批注'));
          await tester.pump();
          final resizedOverlay = tester.widget<AnnotationOverlay>(
            find.byWidgetPredicate(
              (widget) => widget is AnnotationOverlay && widget.selecting,
            ),
          );
          final offsetBeforeSelection = flow.scrollController.offset;
          final resizedStart = resizedOverlay.transform.toViewport(
            ContentPoint(.1, .1),
          );
          final resizedEnd = resizedOverlay.transform.toViewport(
            ContentPoint(.2, .2),
          );
          final resizedFinder = find.byWidgetPredicate(
            (widget) => widget is AnnotationOverlay && widget.selecting,
          );
          await tester.dragFrom(
            tester.getTopLeft(resizedFinder) +
                Offset(resizedStart.x, resizedStart.y),
            Offset(
              resizedEnd.x - resizedStart.x,
              resizedEnd.y - resizedStart.y,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            flow.scrollController.offset,
            closeTo(offsetBeforeSelection, .01),
          );
          expect(find.byType(AnnotationEditor), findsOneWidget);
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(reader.annotations.all, hasLength(1));
          originalPhoto.updateMultiple(
            scale: 1.4,
            position: const Offset(15, -10),
          );
          await tester.pumpAndSettle();
          final active = tester.widget<ReaderAnnotationLayer>(
            find.byType(ReaderAnnotationLayer),
          );
          final displayed = tester.widget<AnnotationOverlay>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is AnnotationOverlay &&
                  widget.page.pageId == note.anchor.pageId,
            ),
          );
          expect(active.imageNumber, reader.page);
          final state = flow.imageStates
              .whereType<ComicImageState>()
              .firstWhere(
                (state) =>
                    (state.widget.image as ReaderDisplayImageProvider)
                        .image
                        .page ==
                    1,
              );
          final box = state.context.findRenderObject() as RenderBox;
          final paint = state.imagePaintBounds!;
          final actual = box.localToGlobal(
            Offset(
              paint.left + paint.width * note.rect!.x0,
              paint.top + paint.height * note.rect!.y0,
            ),
          );
          final projected = displayed.transform.toViewport(
            ContentPoint(note.rect!.x0, note.rect!.y0),
          );
          final origin = tester.getTopLeft(find.byType(ReaderContinuousView));
          expect(
            (actual - (origin + Offset(projected.x, projected.y))).distance,
            lessThan(1),
          );
          expect(reader.imageViewController, same(flow));
          expect(flow.photoViewController, same(originalPhoto));
          await tester.tap(find.byTooltip('隐藏标注'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widgetList<AnnotationOverlay>(find.byType(AnnotationOverlay))
                .every((widget) => !widget.visible),
            isTrue,
          );
          await tester.tap(find.byTooltip('显示标注'));
          await tester.pumpAndSettle();
          originalPhoto.updateMultiple(scale: 1, position: Offset.zero);
          await tester.pumpAndSettle();
          reader.controller.toPage(2, animated: false);
          await _pumpUntil(
            tester,
            () =>
                reader.page == 2 &&
                find.byType(ReaderAnnotationLayer).evaluate().isNotEmpty &&
                tester
                        .widget<ReaderAnnotationLayer>(
                          find.byType(ReaderAnnotationLayer),
                        )
                        .imageNumber ==
                    2 &&
                tester
                    .widget<ReaderAnnotationLayer>(
                      find.byType(ReaderAnnotationLayer),
                    )
                    .isCurrent() &&
                find.byTooltip('整页笔记').evaluate().length == 1,
          );
          expect(reader.annotations.all.single.id, note.id);
          await tester.tap(find.byTooltip('整页笔记'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'stale page two');
          reader.controller.toPage(3, animated: false);
          await _pumpUntil(tester, () => reader.page == 3);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(reader.annotations.all.single.id, note.id);
          expect(
            reader.annotations.all.single.rect!.toJson(),
            note.rect!.toJson(),
          );
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      skip: !const bool.fromEnvironment('COMICNOTES_POC'),
    );
  }

  testWidgets(
    'waterfall annotation source identity follows the displayed chapter',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      try {
        const chapters = ComicChapters({'one': 'First', 'two': 'Second'});
        await tester.runAsync(() async {
          final folder = Directory('${LocalManager().path}/book/two')
            ..createSync();
          await File(
            '${LocalManager().path}/book/one/1.png',
          ).copy('${folder.path}/1.png');
          final book = LocalManager().find('book', ComicType.local)!;
          await LocalManager().add(
            LocalComic(
              id: book.id,
              title: book.title,
              subtitle: book.subtitle,
              tags: book.tags,
              directory: book.directory,
              chapters: chapters,
              cover: book.cover,
              comicType: book.comicType,
              downloadedChapters: const ['one', 'two'],
              createdAt: book.createdAt,
            ),
            book.id,
          );
        });
        appdata.settings['readerMode'] = ReaderMode.waterfallTopToBottom.key;
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          persistentAnnotations: true,
          chapters: chapters,
        );
        await _pumpUntil(
          tester,
          () => find.byTooltip('整页笔记').evaluate().isNotEmpty,
        );
        final reader = fixture.readerKey.currentState!;
        final flow = reader.imageViewController! as ContinuousModeState;
        await tester.tap(find.byTooltip('整页笔记'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'first chapter');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        final first = reader.annotations.all.single;
        expect(flow.toChapter(2), isTrue);
        await _pumpUntil(
          tester,
          () =>
              reader.chapter == 2 &&
              find.byType(ReaderAnnotationLayer).evaluate().isNotEmpty &&
              tester
                      .widget<ReaderAnnotationLayer>(
                        find.byType(ReaderAnnotationLayer),
                      )
                      .chapterId ==
                  'two',
        );
        await tester.tap(find.byTooltip('整页笔记'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'second chapter');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        final second = reader.annotations.all.firstWhere(
          (note) => note.text == 'second chapter',
        );
        expect(first.anchor.chapterId, 'one');
        expect(second.anchor.chapterId, 'two');
        expect(second.anchor.sourceImageNumber, 1);
        expect(second.anchor.pageId, isNot(first.anchor.pageId));
        expect(
          reader.annotations.sourcePage(second.anchor)!.sourceIdentity,
          'two/1.png',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  for (final wide in [false, true]) {
    testWidgets(
      'annotation keyboard selects current page and finds notes without typing page turns; wide=$wide',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(wide ? 1200 : 800, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final fixture = await _ReaderFixture.create(tester);
        Future<void> command(
          LogicalKeyboardKey key, {
          bool shift = false,
        }) async {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          if (shift) {
            await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          }
          await tester.sendKeyEvent(key);
          if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          await tester.pumpAndSettle();
        }

        try {
          await fixture.mount(
            tester,
            pushed: false,
            withWindow: false,
            persistentAnnotations: true,
          );
          final reader = fixture.readerKey.currentState!;
          reader.focusNode.requestFocus();
          await tester.pump();
          await command(LogicalKeyboardKey.keyN, shift: true);
          expect(find.byTooltip('取消框选'), findsOneWidget);
          expect(reader.annotations.inputActive, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(reader.annotations.inputActive, isFalse);
          expect(reader.focusNode.hasPrimaryFocus, isTrue);
          await command(LogicalKeyboardKey.keyN, shift: true);
          final overlayFinder = find.byWidgetPredicate(
            (widget) => widget is AnnotationOverlay && widget.selecting,
          );
          expect(overlayFinder, findsOneWidget);
          final overlay = tester.widget<AnnotationOverlay>(overlayFinder);
          final start = overlay.transform.toViewport(ContentPoint(.2, .2));
          final end = overlay.transform.toViewport(ContentPoint(.8, .8));
          await tester.dragFrom(
            tester.getTopLeft(overlayFinder) + Offset(start.x, start.y),
            Offset(end.x - start.x, end.y - start.y),
          );
          await tester.pumpAndSettle();
          expect(find.byType(AnnotationEditor), findsOneWidget);
          await tester.enterText(find.byType(TextField), 'Saved with keyboard');
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(reader.annotations.all.single.text, 'Saved with keyboard');
          expect(reader.annotations.all.single.anchor.sourceImageNumber, 1);
          expect(reader.focusNode.hasPrimaryFocus, isTrue);
          await command(LogicalKeyboardKey.keyF);
          final search = find.byKey(const ValueKey('annotation-search'));
          expect(search, findsOneWidget);
          expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
          final before = reader.page;
          await tester.enterText(search, 'draft search');
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump();
          expect(reader.page, before);
          await command(LogicalKeyboardKey.keyN, shift: true);
          expect(find.byTooltip('取消框选'), findsNothing);
          expect(
            tester
                .widget<EditableText>(
                  find.descendant(
                    of: search,
                    matching: find.byType(EditableText),
                  ),
                )
                .controller
                .text,
            'draft search',
          );
          await tester.tap(find.byTooltip('关闭批注面板'));
          await tester.pumpAndSettle();
          expect(reader.annotations.inputActive, isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      skip:
          !const bool.fromEnvironment('COMICNOTES_POC') ||
          (wide && !const bool.fromEnvironment('COMICNOTES_WORKSPACE')),
    );
  }

  testWidgets(
    'local annotation inspector edits persistent notes through real reader routes',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      try {
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          persistentAnnotations: true,
        );
        final reader = fixture.readerKey.currentState!;
        expect(reader.annotations.persistent, isTrue);
        await tester.tap(find.byTooltip('整页笔记'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '原批注');
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        final id = reader.annotations.all.single.id;
        await tester.tap(find.byTooltip('本页批注 (1)'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('原批注'));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsOneWidget);
        await tester.enterText(find.byType(TextField), '修改后批注');
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        expect(reader.annotations.all.single.id, id);
        expect(reader.annotations.all.single.text, '修改后批注');
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        expect(reader.annotations.inputActive, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  testWidgets(
    'annotation inspector locates a source image across chapters without changing saved layout preferences',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      try {
        await tester.runAsync(() async {
          final second = Directory('${LocalManager().path}/book/two')
            ..createSync();
          await File(
            '${LocalManager().path}/book/one/1.png',
          ).copy('${second.path}/1.png');
          final book = LocalManager().find('book', ComicType.local)!;
          await LocalManager().add(
            LocalComic(
              id: book.id,
              title: book.title,
              subtitle: book.subtitle,
              tags: book.tags,
              directory: book.directory,
              chapters: const ComicChapters({'one': 'One', 'two': 'Two'}),
              cover: book.cover,
              comicType: book.comicType,
              downloadedChapters: const ['one', 'two'],
              createdAt: book.createdAt,
            ),
          );
        });
        await fixture.mount(
          tester,
          pushed: false,
          persistentAnnotations: true,
          chapters: const ComicChapters({'one': 'One', 'two': 'Two'}),
        );
        final reader = fixture.readerKey.currentState!;
        final page = reader.annotations.anchor(
          chapterId: 'two',
          imageNumber: 99,
          width: 100,
          height: 150,
          sourceIdentity: 'file://${LocalManager().path}/book/two/1.png',
        );
        final note = reader.annotations.add(
          page,
          AnnotationKind.pageNote,
          '跨章节批注',
        );
        appdata.settings['readerScreenPicNumberForLandscape'] = 2;
        tester
            .state<ReaderScaffoldState>(find.byType(ReaderScaffold))
            .openAnnotationInspector();
        await tester.pumpAndSettle();
        expect(find.text('全书批注 · 1'), findsOneWidget);
        await tester.tap(find.text('定位原图'));
        await _pumpUntil(
          tester,
          () =>
              reader.chapter == 2 &&
              !reader.isLoading &&
              reader.images?.length == 1 &&
              _annotationImagesReady(reader),
        );
        await tester.pumpAndSettle();
        expect(reader.page, 1);
        expect(reader.imagesPerPage, 1);
        expect(reader.annotations.selectedId, note.id);
        expect(appdata.settings['readerScreenPicNumberForLandscape'], 2);
        expect(find.text('跨章节批注'), findsOneWidget);
        final overlay = tester
            .widgetList<AnnotationOverlay>(find.byType(AnnotationOverlay))
            .singleWhere((w) => w.page.pageId == page.pageId);
        expect(overlay.selectedId, note.id);
        tester
            .state<ReaderScaffoldState>(find.byType(ReaderScaffold))
            .openAnnotationInspector();
        await tester.pumpAndSettle();
        await tester.tap(find.text('返回阅读布局'));
        await _pumpUntil(tester, () => _annotationImagesReady(reader));
        await tester.pumpAndSettle();
        expect(reader.imagesPerPage, 2);
        expect(reader.annotations.selectedId, isNull);
        expect(reader.chapter, 2);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  testWidgets(
    'Mac annotation workspace keeps reader geometry, keyboard ownership and docked navigation coherent',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fixture = await _ReaderFixture.create(tester);
      try {
        appdata.settings['readerScreenPicNumberForLandscape'] = 1;
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          persistentAnnotations: true,
          brightness:
              Platform.environment['COMICNOTES_WORKSPACE_QA_DARK'] == 'true'
              ? Brightness.dark
              : Brightness.light,
        );
        final reader = fixture.readerKey.currentState!;
        await _pumpUntil(tester, () => _annotationImagesReady(reader));
        final page = reader.annotations.anchor(
          chapterId: 'one',
          imageNumber: 3,
          width: 100,
          height: 150,
          sourceIdentity: reader.images!.last,
        );
        final note = reader.annotations.add(
          page,
          AnnotationKind.region,
          '观察画面的构图',
          rect: ContentRect(.2, .2, .7, .65),
        );
        reader.annotations.setTags(note.id, ['构图']);
        final viewport = reader.imageViewController;
        tester
            .state<ReaderScaffoldState>(find.byType(ReaderScaffold))
            .openAnnotationInspector();
        await _pumpUntil(
          tester,
          () =>
              reader.size == const Size(920, 848) &&
              _annotationImagesReady(reader),
        );
        await tester.pumpAndSettle();
        expect(reader.imageViewController, same(viewport));
        expect(find.text('全书批注 · 1'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('annotation-search')),
          '构图',
        );
        await tester.pump();
        expect(reader.annotations.inputActive, isTrue);
        final before = reader.page;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(reader.page, before);
        reader.focusNode.requestFocus();
        await tester.pump();
        expect(reader.annotations.inputActive, isFalse);
        await tester.tap(find.text('定位原图'));
        await _pumpUntil(
          tester,
          () => reader.page == 3 && _annotationImagesReady(reader),
        );
        await tester.pumpAndSettle();
        expect(find.text('全书批注 · 1'), findsOneWidget);
        expect(reader.annotations.selectedId, note.id);
        final overlay = tester
            .widgetList<AnnotationOverlay>(find.byType(AnnotationOverlay))
            .singleWhere((w) => w.page.pageId == page.pageId);
        final center = overlay.transform.toViewport(const ContentPoint(.5, .5));
        expect(center.x, closeTo(460, 1));
        expect(center.y, closeTo(424, 1));
        final directory = Platform.environment['COMICNOTES_WORKSPACE_QA_DIR'];
        if (directory != null) {
          await tester.runAsync(() async {
            await Directory(directory).create(recursive: true);
            final image = await tester
                .renderObject<RenderRepaintBoundary>(
                  find.byType(RepaintBoundary).first,
                )
                .toImage(pixelRatio: 1);
            try {
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '$directory/workspace-${Platform.environment['COMICNOTES_WORKSPACE_QA_DARK'] == 'true' ? 'dark' : 'light'}.png',
              ).writeAsBytes(data!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        final focusedViewport = reader.imageViewController;
        await tester.tap(find.byTooltip('收起批注栏'));
        await _pumpUntil(tester, () => reader.size == const Size(1280, 848));
        expect(reader.imageViewController, same(focusedViewport));
        await tester.tap(find.byTooltip('专注阅读'));
        await _pumpUntil(tester, () => reader.size == const Size(1280, 900));
        expect(find.byTooltip('显示工作台'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    skip:
        !const bool.fromEnvironment('COMICNOTES_POC') ||
        !const bool.fromEnvironment('COMICNOTES_WORKSPACE'),
  );

  testWidgets(
    'comicnotes app link resolves the real database and opens its original image in a focused reader',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      const memory = MethodChannel('flutter_memory_info');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        memory,
        (_) async => 8 * 1024 * 1024 * 1024,
      );
      try {
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          persistentAnnotations: true,
        );
        final old = fixture.readerKey.currentState!;
        final page = old.annotations.anchor(
          chapterId: 'one',
          imageNumber: 99,
          width: 100,
          height: 150,
          sourceIdentity: old.images!.last,
        );
        final note = old.annotations.add(
          page,
          AnnotationKind.region,
          '外部引用定位',
          rect: ContentRect(0.1, 0.1, 0.6, 0.6),
        );
        appdata.settings['readerMode'] = ReaderMode.continuousTopToBottom.key;
        appdata.settings['readerScreenPicNumberForLandscape'] = 2;
        final uri = AnnotationLink(
          documentId: note.anchor.documentId,
          annotationId: note.id,
        ).toUri();
        expect(await tester.runAsync(() => handleAppLink(uri)), isTrue);
        final linked = find.byWidgetPredicate(
          (w) => w is Reader && w is! _TestReader,
        );
        await _pumpUntil(
          tester,
          () =>
              linked.evaluate().isNotEmpty &&
              tester.state<ReaderState>(linked).images?.length == 3 &&
              _annotationImagesReady(tester.state<ReaderState>(linked)),
        );
        await tester.pumpAndSettle();
        final next = tester.state<ReaderState>(linked),
            widget = tester.widget<Reader>(linked);
        expect(widget.initialAnnotationId, note.id);
        expect(widget.initialPage, 3);
        expect(next.page, 3);
        expect(next.chapter, 1);
        expect(next.mode.isGallery, isTrue);
        expect(next.imagesPerPage, 1);
        expect(next.annotations.selectedId, note.id);
        expect(next.annotations.documentId, old.annotations.documentId);
        expect(
          appdata.settings['readerMode'],
          ReaderMode.continuousTopToBottom.key,
        );
        expect(appdata.settings['readerScreenPicNumberForLandscape'], 2);
        expect(find.text('外部引用定位'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        messenger.setMockMethodCallHandler(memory, null);
        await fixture.dispose(tester);
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  testWidgets(
    'comicnotes app link rejects a binding to another import version without deleting notes',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      try {
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          persistentAnnotations: true,
        );
        final reader = fixture.readerKey.currentState!;
        final page = reader.annotations.anchor(
          chapterId: 'one',
          imageNumber: 1,
          width: 100,
          height: 150,
          sourceIdentity: reader.images!.first,
        );
        final note = reader.annotations.add(
          page,
          AnnotationKind.bookmark,
          '旧版本',
        );
        final store = AnnotationRepository.open(
          '${App.dataPath}/annotations.db',
        );
        try {
          store.db.execute(
            'UPDATE source_documents SET library_key=? WHERE document_id=?',
            ['local:book:0', note.anchor.documentId],
          );
          expect(
            await tester.runAsync(
              () => handleAppLink(
                AnnotationLink(
                  documentId: note.anchor.documentId,
                  annotationId: note.id,
                ).toUri(),
              ),
            ),
            isFalse,
          );
          expect(store.list(note.anchor.documentId).single.id, note.id);
        } finally {
          store.close();
        }
        expect(
          find.byWidgetPredicate((w) => w is Reader && w is! _TestReader),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  testWidgets(
    'comicnotes app link drops a retired asynchronous handler before opening a reader',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final pending = Completer<AnnotationLinkDestination>();
      var active = true;
      try {
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          persistentAnnotations: true,
          resolveLink: (_) => pending.future,
        );
        final uri = AnnotationLink(
          documentId: 'book',
          annotationId: 'note',
        ).toUri();
        final work = handleAppLink(uri, isActive: () => active);
        active = false;
        pending.complete(
          const AnnotationLinkDestination(
            comicId: 'book',
            createdAtMilliseconds: 0,
            chapter: 1,
            imageNumber: 1,
            annotationId: 'note',
          ),
        );
        expect(await work, isFalse);
        expect(
          find.byWidgetPredicate((w) => w is Reader && w is! _TestReader),
          findsNothing,
        );
      } finally {
        if (!pending.isCompleted) {
          pending.completeError(StateError('cancelled test'));
        }
        await fixture.dispose(tester);
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  testWidgets(
    'local annotation export writes a complete notebook through its real runtime binding',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      const selector = MethodChannel('plugins.flutter.io/file_selector');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      try {
        final output = Directory('${fixture.directory.path}/exports')
          ..createSync();
        messenger.setMockMethodCallHandler(selector, (call) async {
          expect(call.method, 'getDirectoryPath');
          return output.path;
        });
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          persistentAnnotations: true,
        );
        final reader = fixture.readerKey.currentState!;
        await tester.tap(find.byTooltip('整页笔记'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '导出此条笔记');
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        await tester.runAsync(reader.exportAnnotations);
        await tester.pumpAndSettle();
        expect(find.text('已导出 1 条批注'), findsOneWidget);
        final files = output
            .listSync(recursive: true)
            .whereType<File>()
            .toList();
        final markdown = files
            .singleWhere((f) => f.path.endsWith('.md'))
            .readAsStringSync();
        expect(markdown, contains('导出此条笔记'));
        expect(markdown, contains('缓存'));
        expect(files.where((f) => f.path.endsWith('.png')), hasLength(1));
        expect(
          files.where((f) => f.path.endsWith('manifest.json')),
          hasLength(1),
        );
        // The completed success dialog cannot hold an image-work close hostage.
        void Function()? release;
        final closing = reader.imageWork.prepareForExit().then(
          (value) => release = value,
        );
        for (var i = 0; i < 50 && release == null; i++) {
          await tester.pump();
          await tester.runAsync(() => pumpEventQueue());
        }
        expect(release, isNotNull);
        await closing;
        release!();
        expect(reader.annotations.inputActive, isFalse);
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        messenger.setMockMethodCallHandler(selector, null);
        await fixture.dispose(tester);
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  testWidgets(
    'annotation inspector relocates an exact original through the real file selector binding',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      const selector = MethodChannel('plugins.flutter.io/file_selector');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      try {
        final original = File('${fixture.directory.path}/original.cbz')
          ..writeAsBytesSync([1, 2, 3, 4]);
        final fingerprint = (await tester.runAsync(
          () => ComicSourceProvenance.fingerprint(original),
        ))!;
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          persistentAnnotations: true,
        );
        final reader = fixture.readerKey.currentState!;
        final document = reader.annotations.sourceDocument!;
        final store = AnnotationRepository.open(
          '${App.dataPath}/annotations.db',
        );
        try {
          store.openDocument(
            libraryKey: document.libraryKey,
            title: 'Book',
            source: AnnotationDocumentSource(
              kind: 'archive',
              uri: original.uri.toString(),
              sha256: fingerprint['sha256'] as String,
              size: 4,
            ),
          );
        } finally {
          store.close();
        }
        final page = reader.annotations.anchor(
          chapterId: 'one',
          imageNumber: 1,
          width: 100,
          height: 150,
          sourceIdentity: reader.images!.first,
        );
        final note = reader.annotations.add(
          page,
          AnnotationKind.pageNote,
          'Keep ID',
        );
        final moved = original.renameSync(
          '${fixture.directory.path}/moved %.cbz',
        );
        messenger.setMockMethodCallHandler(selector, (call) async {
          expect(call.method, 'openFile');
          return [moved.path];
        });
        tester
            .state<ReaderScaffoldState>(find.byType(ReaderScaffold))
            .openAnnotationInspector();
        await tester.pumpAndSettle();
        await tester.tap(find.text('重新关联原件'));
        await _pumpUntil(
          tester,
          () => find.text('原件已重新关联，批注 ID 与坐标保持不变').evaluate().isNotEmpty,
        );
        expect(
          reader.annotations.sourceDocument!.source!.uri,
          moved.uri.toString(),
        );
        expect(reader.annotations.all.single.id, note.id);
        expect(reader.annotations.inputActive, isFalse);
        expect(find.byType(ReaderScaffold), findsOneWidget);
        await tester.tap(find.byTooltip('关闭批注面板'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        messenger.setMockMethodCallHandler(selector, null);
        await fixture.dispose(tester);
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  testWidgets(
    'annotation inspector recovers orphan notes into the current reader without losing old links',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      try {
        final comic = LocalManager().find('book', ComicType.local)!;
        late Annotation note;
        late String documentId;
        await tester.runAsync(() async {
          final receipt = ComicSourceProvenance(
            source: {
              'kind': 'archive',
              'uri': 'file:///removed.cbz',
              'sha256': 'a' * 64,
              'size': 1,
            },
            pages: {},
          );
          final pageFile = File('${comic.baseDir}/one/1.png');
          receipt.pages['one/1.png'] = {
            'kind': 'archiveImage',
            'extractedEntry': '1.png',
            ...await ComicSourceProvenance.fingerprint(pageFile),
          };
          await receipt.write(Directory(comic.baseDir));
          final old = openLocalAnnotationSession(
            libraryKey: 'local:removed:0',
            title: 'Older import',
            sourceRoot: comic.baseDir,
          );
          try {
            final page = old.anchor(
              chapterId: 'one',
              imageNumber: 1,
              width: 100,
              height: 150,
              sourceIdentity: 'file://${pageFile.path}',
            );
            note = old.add(page, AnnotationKind.pageNote, '恢复原来的文字');
            old.setTags(note.id, ['旧标签']);
            documentId = old.documentId;
          } finally {
            old.close();
          }
        });
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          persistentAnnotations: true,
        );
        final reader = fixture.readerKey.currentState!;
        expect(reader.annotations.all, isEmpty);
        tester
            .state<ReaderScaffoldState>(find.byType(ReaderScaffold))
            .openAnnotationInspector();
        await tester.pumpAndSettle();
        await tester.tap(find.text('恢复旧批注'));
        await _pumpUntil(
          tester,
          () => find.text('恢复同一原件的旧批注').evaluate().isNotEmpty,
        );
        await tester.pumpAndSettle();
        expect(find.text('Older import'), findsOneWidget);
        await tester.tap(find.text('Older import'));
        await _pumpUntil(
          tester,
          () =>
              reader.annotations.documentId == documentId &&
              _annotationImagesReady(reader),
        );
        await tester.pumpAndSettle();
        expect(reader.annotations.all.single.id, note.id);
        expect(reader.annotations.all.single.tags, ['旧标签']);
        expect(reader.annotations.inputActive, isFalse);
        final target = await tester.runAsync(
          () => resolveLocalAnnotationLink(
            AnnotationLink(documentId: documentId, annotationId: note.id),
          ),
        );
        expect(target!.comic.id, 'book');
        expect(target.location.imageNumber, 1);
        tester
            .state<ReaderScaffoldState>(find.byType(ReaderScaffold))
            .openAnnotationInspector();
        await tester.pumpAndSettle();
        expect(find.text('恢复原来的文字'), findsOneWidget);
        expect(find.text('恢复旧批注'), findsNothing);
        await tester.tap(find.byTooltip('关闭批注面板'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  testWidgets(
    'annotation inspector backs up the live database through its real file selector binding',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      const selector = MethodChannel('plugins.flutter.io/file_selector');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      try {
        final output = Directory('${fixture.directory.path}/backups')
          ..createSync();
        messenger.setMockMethodCallHandler(selector, (_) async => output.path);
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          persistentAnnotations: true,
        );
        final reader = fixture.readerKey.currentState!;
        final page = reader.annotations.anchor(
          chapterId: 'one',
          imageNumber: 1,
          width: 100,
          height: 150,
          sourceIdentity: reader.images!.first,
        );
        final note = reader.annotations.add(
          page,
          AnnotationKind.pageNote,
          '备份此条批注',
        );
        reader.annotations.setTags(note.id, ['构图']);
        tester
            .state<ReaderScaffoldState>(find.byType(ReaderScaffold))
            .openAnnotationInspector();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('备份全部批注'));
        await _pumpUntil(
          tester,
          () => find.text('全部批注已备份').evaluate().isNotEmpty,
        );
        await tester.pumpAndSettle();
        final database = output
            .listSync(recursive: true)
            .whereType<File>()
            .singleWhere((file) => file.path.endsWith('annotations.db'));
        final copy = AnnotationRepository.open(database.path);
        try {
          expect(copy.list(reader.annotations.documentId).single.id, note.id);
          expect(copy.list(reader.annotations.documentId).single.tags, ['构图']);
        } finally {
          copy.close();
        }
        expect(reader.annotations.inputActive, isFalse);
        void Function()? release;
        final closing = reader.imageWork.prepareForExit().then(
          (value) => release = value,
        );
        await _pumpUntil(tester, () => release != null);
        expect(release, isNotNull);
        await closing;
        release!();
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        messenger.setMockMethodCallHandler(selector, null);
        await fixture.dispose(tester);
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  testWidgets(
    'local annotation export cancels without publishing when its image owner closes',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final pending = Completer<AnnotationExportResult?>();
      bool Function()? cancelled;
      try {
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          persistentAnnotations: true,
          exportNotes:
              ({required session, required title, required isCancelled}) {
                cancelled = isCancelled;
                return pending.future;
              },
        );
        final reader = fixture.readerKey.currentState!;
        final work = reader.exportAnnotations();
        await tester.pump();
        expect(find.text('正在导出图文笔记'), findsOneWidget);
        final release = reader.imageWork.holdForExit();
        expect(cancelled!(), isTrue);
        pending.complete(null);
        await work;
        await tester.pumpAndSettle();
        expect(find.text('正在导出图文笔记'), findsNothing);
        expect(reader.annotations.inputActive, isFalse);
        release();
        expect(tester.takeException(), isNull);
      } finally {
        if (!pending.isCompleted) pending.complete(null);
        await fixture.dispose(tester);
      }
    },
    skip: !const bool.fromEnvironment('COMICNOTES_POC'),
  );

  for (final mode in [
    ReaderMode.galleryLeftToRight,
    ReaderMode.galleryRightToLeft,
    ReaderMode.galleryTopToBottom,
  ]) {
    for (final landscapeImages in [1, 2]) {
      for (final duringAnimation in [false, true]) {
        testWidgets(
          'actual automatic gallery resumes after rotation: ${mode.key} spread=$landscapeImages animated=$duringAnimation',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = const Size(375, 667);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetPhysicalSize);
            final fixture = await _ReaderFixture.create(tester, imageCount: 12);
            try {
              appdata.settings['readerMode'] = mode.key;
              appdata.settings['readerScreenPicNumberForLandscape'] =
                  landscapeImages;
              appdata.settings['autoPageTurningInterval'] = 1;
              appdata.settings['enablePageAnimation'] = true;
              await fixture.mount(tester, pushed: false, withWindow: false);
              final reader = fixture.readerKey.currentState!;
              Future<void> expectAutomaticAdvance() async {
                await _pumpUntil(tester, () {
                  final viewport = reader.imageViewController;
                  return !reader.isPageAnimating &&
                      viewport is AutoReadingViewport &&
                      (viewport as AutoReadingViewport).autoReadingReady;
                });
                final before = reader.page;
                await _pumpUntil(
                  tester,
                  () => reader.page > before && !reader.isPageAnimating,
                );
                expect(reader.autoReading.isActive, isTrue);
              }

              reader.autoReading.start();
              if (duringAnimation) {
                await _pumpUntil(tester, () => reader.isPageAnimating);
              }
              tester.view.physicalSize = const Size(667, 375);
              await tester.pump();
              await expectAutomaticAdvance();
              tester.view.physicalSize = const Size(375, 667);
              await tester.pump();
              await expectAutomaticAdvance();
              expect(tester.takeException(), isNull);
            } finally {
              await fixture.dispose(tester);
            }
          },
        );
      }
    }
  }

  for (final mode in [
    ReaderMode.galleryLeftToRight,
    ReaderMode.continuousTopToBottom,
    ReaderMode.waterfallTopToBottom,
  ]) {
    for (final savedPage in [2, 1001]) {
      for (final group in [null, 1]) {
        testWidgets(
          'chapterless history resumes page $savedPage with group $group in ${mode.key}',
          (tester) async {
            await tester.binding.setSurfaceSize(const Size(375, 667));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final imageCount = savedPage == 1001 ? 1200 : 3;
            final fixture = await _ReaderFixture.create(
              tester,
              imageCount: imageCount,
            );
            final saved = _resumeHistory(page: savedPage, maxPage: imageCount);
            try {
              appdata.settings['readerMode'] = mode.key;
              await fixture.mount(
                tester,
                pushed: false,
                chapters: null,
                savedHistory: saved,
                initialChapter: saved.ep,
                initialPage: saved.page,
                initialChapterGroup: group,
              );
              final reader = fixture.readerKey.currentState!;
              expect(reader.chapter, 1);
              expect(reader.page, savedPage);
              expect(reader.history, same(saved));
              expect(saved.page, savedPage);
              expect(saved.maxPage, imageCount);
              expect(saved.group, isNull);
              expect(tester.takeException(), isNull);
            } finally {
              await fixture.dispose(tester);
            }
            expect(fixture.history.progress, isNotEmpty);
            expect(fixture.history.progress.last.page, savedPage);
          },
        );
      }
    }
  }

  testWidgets('flat chapter history ignores obsolete group coordinates', (
    tester,
  ) async {
    final fixture = await _ReaderFixture.create(tester);
    final saved = _resumeHistory(chapter: 2, page: 2, group: 2);
    try {
      await fixture.mount(
        tester,
        pushed: false,
        chapters: const ComicChapters({
          'previous': 'Previous',
          'one': 'Current',
        }),
        savedHistory: saved,
        initialChapter: saved.ep,
        initialPage: saved.page,
        initialChapterGroup: saved.group,
      );
      final reader = fixture.readerKey.currentState!;
      expect(reader.chapter, 2);
      expect(reader.eid, 'one');
      expect(reader.page, 2);
      expect(saved.ep, 2);
      expect(saved.page, 2);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  for (final group in [null, 1, 2]) {
    testWidgets(
      'grouped chapter history resumes coordinates with group $group',
      (tester) async {
        final fixture = await _ReaderFixture.create(tester);
        final saved = _resumeHistory(
          chapter: group == null ? 2 : 1,
          page: 2,
          group: group,
        );
        try {
          await fixture.mount(
            tester,
            pushed: false,
            chapters: const ComicChapters.grouped({
              'First volume': {'one': 'First chapter'},
              'Second volume': {'one': 'Second chapter'},
            }),
            savedHistory: saved,
            initialChapter: saved.ep,
            initialPage: saved.page,
            initialChapterGroup: saved.group,
          );
          final reader = fixture.readerKey.currentState!;
          expect(reader.chapter, group == 1 ? 1 : 2);
          expect(reader.eid, 'one');
          expect(reader.page, 2);
          expect(saved.ep, 1);
          expect(saved.group, group == 1 ? 1 : 2);
          expect(saved.page, 2);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
    );
  }

  for (final layout in [ComicLayout.paged, ComicLayout.longStrip]) {
    for (final mode in ReaderMode.values) {
      testWidgets(
        'real image detection selects ${mode.key} for ${layout.name}',
        (tester) async {
          final fixture = await _ReaderFixture.create(
            tester,
            imageCount: 10,
            layout: layout,
          );
          try {
            final settings = appdata.settings;
            settings['comicLayoutDetections'] = <String, dynamic>{};
            settings['autoReaderMode'] = true;
            settings['readerMode'] = mode.isGallery
                ? ReaderMode.continuousTopToBottom.key
                : ReaderMode.galleryLeftToRight.key;
            settings['pagedReaderMode'] = mode.key;
            settings['longStripReaderMode'] = mode.key;
            settings['readerScreenPicNumberForLandscape'] = 2;
            settings['readerScreenPicNumberForPortrait'] = 2;
            settings['showSingleImageOnFirstPage'] = true;
            settings['enablePageAnimation'] = false;
            await fixture.mount(tester, pushed: false, initialPage: 4);
            final reader = fixture.readerKey.currentState!;
            await _pumpUntil(
              tester,
              () => !reader.isDetectingLayout && reader.mode == mode,
            );
            expect(
              reader.layoutProbe,
              isNull,
              reason: 'Use the production probe.',
            );
            expect(settings.comicLayout('book', 'local'), layout);
            expect(reader.settingsSaves, 1);
            expect(reader.chapter, 1);
            expect(reader.page, mode.isGallery ? 3 : 4);
            expect(reader.history!.page, 4);
            expect(reader.history!.maxPage, 10);
            expect(
              reader.imageViewController,
              mode.isGallery
                  ? isA<GalleryModeState>()
                  : isA<ContinuousModeState>(),
            );
            // Mode selection can finish before the new viewport decodes a frame.
            await _pumpUntil(
              tester,
              () => _paintedImages(
                find.byType(ReaderImagesHost),
              ).evaluate().isNotEmpty,
            );
            expect(_paintedImages(find.byType(ReaderImagesHost)), findsWidgets);
            final saved = await tester.runAsync(
              () async => jsonDecode(
                await File(
                  '${fixture.directory.path}/appdata.json',
                ).readAsString(),
              ),
            );
            final detection =
                saved['settings']['comicLayoutDetections']['book@local'];
            expect(detection['layout'], layout.name);
            expect(detection['samples'], 6);
            expect(detection['version'], ComicLayoutDetection.version);
            expect(tester.takeException(), isNull);
          } finally {
            await fixture.dispose(tester);
          }
        },
      );
    }
  }

  for (final mode in [
    ReaderMode.continuousLeftToRight,
    ReaderMode.continuousRightToLeft,
  ]) {
    for (final largerNeighbor in [false, true]) {
      testWidgets(
        'a loading neighbor cannot displace a fully visible page in ${mode.key} (larger: $largerNeighbor)',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(800, 600));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final fixture = await _ReaderFixture.create(
            tester,
            imageCount: 10,
            layout: ComicLayout.longStrip,
          );
          final neighbor = File('${LocalManager().path}/book/one/8.png');
          if (largerNeighbor) {
            neighbor.writeAsBytesSync(
              img.encodePng(img.Image(width: 100, height: 100)),
            );
          }
          final read = _LocalReadGate(neighbor);
          final previousIO = IOOverrides.current;
          try {
            appdata.settings['readerMode'] = mode.key;
            appdata.settings['preloadImageCount'] = 0;
            IOOverrides.global = read;
            await fixture.mount(
              tester,
              pushed: false,
              initialPage: 4,
              waitForImage: false,
            );
            final reader = fixture.readerKey.currentState!;
            final viewport = reader.imageViewController! as ContinuousModeState;
            bool decodedNeighbors() {
              final visible = viewport.imageStates
                  .whereType<ComicImageState>()
                  .where((image) => image.visibleInReader);
              return read.reads > 0 &&
                  visible.any(
                    (image) =>
                        (image.widget.image as ReaderDisplayImageProvider)
                                .image
                                .page ==
                            4 &&
                        image.readyForAutoReading,
                  ) &&
                  visible
                      .where(
                        (image) =>
                            (image.widget.image as ReaderDisplayImageProvider)
                                .image
                                .page !=
                            8,
                      )
                      .every((image) => image.readyForAutoReading);
            }

            await _pumpUntil(tester, decodedNeighbors);
            await tester.pump();
            expect(reader.page, 4);
            expect(reader.history!.page, 4);
            expect(read.completedReads, 0);
            read.release();
            await _pumpUntil(
              tester,
              () => viewport.imageStates
                  .whereType<ComicImageState>()
                  .where((image) => image.visibleInReader)
                  .every((image) => image.readyForAutoReading),
            );
            await tester.pump();
            expect(reader.page, largerNeighbor ? 8 : 4);
            expect(reader.history!.page, largerNeighbor ? 8 : 4);
            expect(tester.takeException(), isNull);
          } finally {
            read.release();
            IOOverrides.global = previousIO;
            await fixture.dispose(tester);
          }
        },
      );
    }
  }

  testWidgets('captured waterfall chapter metadata retains its original map', (
    tester,
  ) async {
    final fixture = await _ReaderFixture.create(tester);
    final chapters = {'one': 'Original title', 'two': 'Second title'};
    try {
      appdata.settings['readerMode'] = ReaderMode.waterfallTopToBottom.key;
      await fixture.mount(
        tester,
        pushed: false,
        chapters: ComicChapters(chapters),
      );
      final view = tester.widget<ReaderContinuousView>(
        find.byType(ReaderContinuousView),
      );
      chapters.remove('one');
      chapters['one'] = 'Changed title';
      expect(view.chapterId(1), 'one');
      expect(view.chapterTitle(1), 'Original title');
    } finally {
      await fixture.dispose(tester);
    }
  });

  for (final detached in [false, true]) {
    testWidgets(
      'captured waterfall load rejects retired target; detached=$detached',
      (tester) async {
        final fixture = await _ReaderFixture.create(tester);
        final chapters = {'one': 'Original title'};
        final scope = RequestScope();
        try {
          appdata.settings['readerMode'] = ReaderMode.waterfallTopToBottom.key;
          await fixture.mount(
            tester,
            pushed: false,
            chapters: ComicChapters(chapters),
          );
          final view = tester.widget<ReaderContinuousView>(
            find.byType(ReaderContinuousView),
          );
          if (detached) {
            await tester.pumpWidget(const SizedBox());
          } else {
            chapters.remove('one');
            chapters['replacement'] = 'Changed chapter';
          }
          await tester.runAsync(
            () => expectLater(
              view.loadChapter(1, scope),
              throwsA(isA<RequestCancelled>()),
            ),
          );
        } finally {
          scope.dispose();
          await fixture.dispose(tester);
        }
      },
    );
  }

  testWidgets(
    'source replacement reloads images while exit drains the original chapter',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final manager = ComicSourceManager();
      final oldChapter = Completer<Res<List<String>>>();
      final started = Completer<void>();
      final first = 'file://${LocalManager().path}/book/one/1.png';
      final replacement = 'file://${LocalManager().path}/book/one/2.png';
      var source = _ReaderPagesSource((_, ep) {
        if (ep == 'two') {
          if (!started.isCompleted) started.complete();
          return oldChapter.future;
        }
        return Future.value(Res(List.filled(3, first)));
      });
      configureComicSourceRegistry(
        all: manager.all,
        find: (key) => key == 'replacement' ? source : manager.find(key),
        fromIntKey: (key) => key == 42 ? source : manager.fromIntKey(key),
        isEmpty: () => false,
      );
      try {
        appdata.settings['readerMode'] = ReaderMode.waterfallTopToBottom.key;
        await fixture.mount(
          tester,
          pushed: true,
          comicType: const _OtherComicType(),
          chapters: const ComicChapters({'one': 'One', 'two': 'Two'}),
        );
        final reader = fixture.readerKey.currentState!;
        final originalView = reader.imageViewController!;
        expect(originalView.toChapter(2), isTrue);
        await _pumpUntil(tester, () => started.isCompleted);
        source = _ReaderPagesSource(
          (_, _) async => Res(List.filled(3, replacement)),
        );
        manager.notifyStateChange();
        await _pumpUntil(
          tester,
          () => !reader.isLoading && reader.images?.first == replacement,
        );
        expect(reader.chapter, 1);
        expect(reader.imageViewController, isNot(same(originalView)));
        var closed = false;
        final closing = reader.requestExit().then((_) => closed = true);
        await tester.pump();
        expect(closed, isFalse);
        oldChapter.complete(Res([first]));
        await _pumpUntil(tester, () => closed);
        await closing;
        await tester.pumpAndSettle();
        expect(fixture.readerKey.currentState, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        if (!oldChapter.isCompleted) oldChapter.complete(Res([first]));
        await fixture.dispose(tester);
        configureComicSourceRegistry(
          all: manager.all,
          find: manager.find,
          fromIntKey: manager.fromIntKey,
          isEmpty: () => manager.isEmpty,
        );
      }
    },
  );

  testWidgets('captured gallery shell callbacks ignore unmounted owner', (
    tester,
  ) async {
    final fixture = await _ReaderFixture.create(tester);
    try {
      await fixture.mount(tester, pushed: false);
      final view = tester.widget<ReaderGalleryView>(
        find.byType(ReaderGalleryView),
      );
      await tester.pumpWidget(const SizedBox());
      view.onCollectImage();
      view.onPageReported(true, true);
      view.onChapterChanged();
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets(
    'captured reader image read retains the original chapter cache key',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final previous = CacheManager.instance;
      final cache = CacheManager.open(
        dataPath: fixture.directory.path,
        cacheRoot: fixture.directory.path,
      );
      CacheManager.instance = cache;
      try {
        await fixture.mount(
          tester,
          pushed: false,
          chapters: const ComicChapters({'one': 'One', 'two': 'Two'}),
        );
        await tester.runAsync(() async {
          await cache.writeCache('collision@local@book@one', [1, 2, 3]);
          await cache.writeCache('collision@local@book@two', [4, 5, 6]);
        });
        final read = tester
            .widget<ReaderGalleryView>(find.byType(ReaderGalleryView))
            .readImage;
        fixture.readerKey.currentState!.controller.restoreChapter(2);
        final bytes = await tester.runAsync(
          () => read(
            const ReaderImageAddress(
              imageKey: 'collision',
              sourceKey: 'local',
              comicId: 'book',
              chapterId: 'one',
            ),
          ),
        );
        expect(bytes, [1, 2, 3]);
      } finally {
        await tester.runAsync(cache.dispose);
        CacheManager.instance = previous;
        await fixture.dispose(tester);
      }
    },
  );

  testWidgets('reader image cache miss returns an absent image', (
    tester,
  ) async {
    final fixture = await _ReaderFixture.create(tester);
    final previous = CacheManager.instance;
    final cache = CacheManager.open(
      dataPath: fixture.directory.path,
      cacheRoot: fixture.directory.path,
    );
    CacheManager.instance = cache;
    try {
      await fixture.mount(tester, pushed: false);
      final read = tester
          .widget<ReaderGalleryView>(find.byType(ReaderGalleryView))
          .readImage;
      expect(
        await tester.runAsync(
          () => read(
            const ReaderImageAddress(
              imageKey: 'missing',
              sourceKey: 'local',
              comicId: 'book',
              chapterId: 'one',
            ),
          ),
        ),
        isNull,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.runAsync(cache.dispose);
      CacheManager.instance = previous;
      await fixture.dispose(tester);
    }
  });

  testWidgets('reader context menu can open settings for its original route', (
    tester,
  ) async {
    final fixture = await _ReaderFixture.create(tester);
    try {
      await fixture.mount(tester, pushed: false);
      await tester.tapAt(
        tester.getCenter(find.byType(ReaderGalleryView)),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderSettings), findsOneWidget);
      expect(fixture.readerKey.currentState, isNotNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  for (final change in ['chapter', 'viewport', 'settings', 'source', 'hold']) {
    testWidgets('reader context menu retires automatically on $change change', (
      tester,
    ) async {
      final fixture = await _ReaderFixture.create(tester);
      var source = _ReaderCommentSource();
      final restore = _readerCommentRegistry(() => source);
      final saving = Completer<void>();
      try {
        await fixture.mount(
          tester,
          pushed: false,
          chapters: const ComicChapters({'one': 'One', 'two': 'Two'}),
        );
        final reader = fixture.readerKey.currentState!;
        if (change == 'hold') {
          // Isolate preparation from the normal menu-first window back action.
          reader.disposeReaderWindow();
          await tester.pumpAndSettle();
        }
        await tester.tapAt(
          tester.getCenter(find.byType(ReaderGalleryView)),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(find.text('Settings'), findsOneWidget);
        switch (change) {
          case 'chapter':
            expect(reader.toChapter(2), isTrue);
          case 'viewport':
            reader.mode = ReaderMode.continuousTopToBottom;
            reader.update();
          case 'settings':
            appdata.settings['enableTapToTurnPages'] = false;
            reader.update();
          case 'source':
            source = _ReaderCommentSource();
            ComicSourceManager.current!.notifyStateChange();
          case 'hold':
            fixture.history.onProgress = (_) => saving.future;
            fixture.closeWindow(tester);
            expect(fixture.frame.isClosing, isTrue);
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(find.text('Settings'), findsNothing);
        expect(find.byType(ReaderSettings), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        if (!saving.isCompleted) saving.complete();
        await tester.pump();
        await fixture.dispose(tester);
        restore();
      }
    });
  }

  testWidgets(
    'removing reader clears its context menu and preserves the cover route',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      try {
        await fixture.mount(tester, pushed: true);
        final reader = fixture.readerKey.currentState!;
        final route = ModalRoute.of(reader.context)!;
        await tester.tapAt(
          tester.getCenter(find.byType(ReaderGalleryView)),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(find.text('Settings'), findsOneWidget);
        final navigator = appNavigation.rootNavigatorKey.currentState!;
        unawaited(
          navigator.push<void>(
            MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('Menu cover')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        navigator.removeRoute(route);
        await tester.pumpAndSettle();
        expect(find.text('Menu cover'), findsOneWidget);
        navigator.pop();
        await tester.pumpAndSettle();
        expect(find.text('Library home'), findsOneWidget);
        expect(find.text('Settings'), findsNothing);
        expect(navigator.canPop(), isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
  );

  testWidgets('delayed reader tap is retired when its page is removed', (
    tester,
  ) async {
    final fixture = await _ReaderFixture.create(tester);
    try {
      appdata.settings['enableDoubleTapToZoom'] = true;
      await fixture.mount(tester, pushed: false);
      await tester.tapAt(tester.getCenter(find.byType(ReaderGalleryView)));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('delayed reader tap cannot open menus for a replaced chapter', (
    tester,
  ) async {
    final fixture = await _ReaderFixture.create(tester);
    try {
      appdata.settings['enableDoubleTapToZoom'] = true;
      await fixture.mount(tester, pushed: false);
      await tester.tapAt(tester.getCenter(find.byType(ReaderGalleryView)));
      fixture.readerKey.currentState!.controller.restoreChapter(2);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.state<ReaderScaffoldState>(find.byType(ReaderScaffold)).isOpen,
        isFalse,
      );
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('delayed reader long press cannot act on a replaced chapter', (
    tester,
  ) async {
    final fixture = await _ReaderFixture.create(tester);
    try {
      appdata.settings['longPressAction'] = 'autoReading';
      await fixture.mount(tester, pushed: false);
      final reader = fixture.readerKey.currentState!;
      var becameActive = false;
      void recordAutomaticReading() {
        becameActive |= reader.autoReading.isActive;
      }

      reader.autoReading.addListener(recordAutomaticReading);
      final pointer = await tester.startGesture(
        tester.getCenter(find.byType(ReaderGalleryView)),
      );
      reader.controller.restoreChapter(2);
      await tester.pump(const Duration(milliseconds: 300));
      await pointer.up();
      expect(reader.autoReading.isActive, isFalse);
      expect(becameActive, isFalse);
      reader.autoReading.removeListener(recordAutomaticReading);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets(
    'changing mode during an active gesture releases its pause safely',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      try {
        await fixture.mount(tester, pushed: false);
        final reader = fixture.readerKey.currentState!;
        reader.autoReading.start();
        final pointer = await tester.startGesture(
          tester.getCenter(find.byType(ReaderGalleryView)),
        );
        expect(reader.autoReading.status, AutoReadingStatus.paused);
        await tester.pump(const Duration(milliseconds: 300));
        reader.mode = ReaderMode.continuousTopToBottom;
        reader.update();
        await tester.pump();
        expect(
          reader.autoReading.status,
          isIn([AutoReadingStatus.running, AutoReadingStatus.waiting]),
        );
        expect(tester.takeException(), isNull);
        reader.autoReading.stop();
        await pointer.up();
      } finally {
        await fixture.dispose(tester);
      }
    },
  );

  testWidgets('old progress callbacks cannot navigate a replacement chapter', (
    tester,
  ) async {
    final fixture = await _ReaderFixture.create(tester);
    try {
      await fixture.mount(tester, pushed: false);
      final reader = fixture.readerKey.currentState!;
      final progress = tester.widget<ReaderBottomBar>(
        find.byType(ReaderBottomBar),
      );
      reader.controller.restoreChapter(2);
      reader.controller.restorePage(1);
      progress.onPageChanged(2);
      expect(reader.page, 1);
      progress.onPrevious();
      expect(reader.chapter, 2);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('old progress callbacks are harmless after reader removal', (
    tester,
  ) async {
    final fixture = await _ReaderFixture.create(tester);
    try {
      await fixture.mount(tester, pushed: false);
      final progress = tester.widget<ReaderBottomBar>(
        find.byType(ReaderBottomBar),
      );
      await tester.pumpWidget(const SizedBox());
      progress.onPageChanged(2);
      progress.onNext();
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets(
    'shell page reports update input without rebuilding image content',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      try {
        await fixture.mount(tester, pushed: false);
        final reader = fixture.readerKey.currentState!;
        final content = tester.widget<ReaderImagesHost>(
          find.byType(ReaderImagesHost),
        );
        final before = tester.widget<ReaderBottomBar>(
          find.byType(ReaderBottomBar),
        );
        reader.setPage(2);
        reader.updateShell();
        await tester.pump();
        final after = tester.widget<ReaderBottomBar>(
          find.byType(ReaderBottomBar),
        );
        expect(after.page, 2);
        expect(after.label, 'E1 : P2');
        expect(after.progressIdentity, before.progressIdentity);
        expect(
          identical(
            tester.widget<ReaderImagesHost>(find.byType(ReaderImagesHost)),
            content,
          ),
          isTrue,
        );
      } finally {
        await fixture.dispose(tester);
      }
    },
  );

  testWidgets('progress retires changed mode, layout, metadata and viewport', (
    tester,
  ) async {
    final fixture = await _ReaderFixture.create(tester);
    final chapterMap = {'one': 'First', 'two': 'Second'};
    try {
      await fixture.mount(
        tester,
        pushed: false,
        chapters: ComicChapters(chapterMap),
      );
      final reader = fixture.readerKey.currentState!;
      var request = reader.createProgressRequest();
      reader.mode = ReaderMode.galleryRightToLeft;
      expect(request.selectPage(2), isFalse);
      reader.mode = ReaderMode.galleryLeftToRight;
      request = reader.createProgressRequest();
      chapterMap['one'] = 'Renamed';
      expect(request.selectPage(2), isFalse);
      expect(reader.createProgressRequest().identity, isNot(request.identity));
      request = reader.createProgressRequest();
      appdata.settings['readerScreenPicNumberForLandscape'] = 2;
      expect(request.selectPage(2), isFalse);
      appdata.settings['readerScreenPicNumberForLandscape'] = 1;
      request = reader.createProgressRequest();
      final viewport = reader.imageViewController!;
      reader.viewportBinding.clear();
      expect(request.selectPage(2), isFalse);
      reader.viewportBinding.update(viewport, true);
      expect(reader.page, 1);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets(
    'sidebar pauses are independent and release only their own reason',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      try {
        await fixture.mount(tester, pushed: false);
        final reader = fixture.readerKey.currentState!;
        reader.autoReading.start();
        final first = reader.acquireAutomaticReadingPause();
        final second = reader.acquireAutomaticReadingPause();
        reader.autoReading.pause('external', true);
        first();
        first();
        expect(reader.autoReading.status, AutoReadingStatus.paused);
        second();
        expect(reader.autoReading.status, AutoReadingStatus.paused);
        reader.autoReading.pause('external', false);
        expect(reader.autoReading.status, AutoReadingStatus.running);
        final lateRelease = reader.acquireAutomaticReadingPause();
        await tester.pumpWidget(const SizedBox());
        lateRelease();
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
  );

  for (final mode in ReaderMode.values) {
    testWidgets('progress dispatches image endpoints in ${mode.key}', (
      tester,
    ) async {
      // Leave enough horizontal content after page 2 to align its leading edge.
      // The last-page clamp below must not also clamp this intermediate page.
      await tester.binding.setSurfaceSize(const Size(700, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = await _ReaderFixture.create(tester);
      try {
        appdata.settings['readerMode'] = mode.key;
        appdata.settings['enablePageAnimation'] = false;
        appdata.settings['enableDoubleTapToZoom'] = false;
        await fixture.mount(
          tester,
          pushed: false,
          chapters: const ComicChapters({'one': 'First'}),
        );
        final reader = fixture.readerKey.currentState!;
        final bounds = tester.getRect(find.byType(ReaderImagesHost));
        final reverse =
            mode == ReaderMode.galleryRightToLeft ||
            mode == ReaderMode.continuousRightToLeft;
        await tester.tapAt(
          mode.isTopToBottom
              ? Offset(bounds.center.dx, bounds.top + bounds.height * 0.85)
              : Offset(
                  bounds.left + bounds.width * (reverse ? 0.15 : 0.85),
                  bounds.center.dy,
                ),
        );
        await tester.pump();
        expect(reader.page, 2);
        final shell = tester.state<ReaderScaffoldState>(
          find.byType(ReaderScaffold),
        );
        shell.openOrClose();
        await tester.pumpAndSettle();
        Focus.of(tester.element(find.byIcon(Icons.first_page))).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pump();
        expect(reader.page, 1);
        await tester.sendKeyEvent(
          reverse
              ? LogicalKeyboardKey.arrowLeft
              : LogicalKeyboardKey.arrowRight,
        );
        expect(
          reader.page,
          2,
          reason: 'One slider key changes exactly one image page.',
        );
        await tester.pump();
        expect(reader.page, 2);
        shell.openOrClose();
        await tester.pumpAndSettle();
        var progress = tester.widget<ReaderBottomBar>(
          find.byType(ReaderBottomBar),
        );
        progress.onPageChanged(2);
        await tester.pump();
        expect(reader.page, 2);
        progress = tester.widget<ReaderBottomBar>(find.byType(ReaderBottomBar));
        final reversed =
            mode == ReaderMode.galleryRightToLeft ||
            mode == ReaderMode.continuousRightToLeft;
        (reversed ? progress.onPrevious : progress.onNext)();
        expect(reader.page, 3);
        await tester.pump();
        // Equal-area images at the horizontal scroll end retain the requested
        // page instead of reverting to the first visible source image.
        expect(reader.page, 3);
        progress = tester.widget<ReaderBottomBar>(find.byType(ReaderBottomBar));
        (reversed ? progress.onNext : progress.onPrevious)();
        await tester.pump();
        expect(reader.page, 1);
        expect(reader.chapter, 1);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  testWidgets('moving keyboard focus into the menu stops held gallery paging', (
    tester,
  ) async {
    final fixture = await _ReaderFixture.create(tester);
    try {
      appdata.settings['enablePageAnimation'] = false;
      await fixture.mount(tester, pushed: false);
      final reader = fixture.readerKey.currentState!;
      final gallery = reader.imageViewController! as GalleryModeState;
      reader.focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      expect(gallery.keyRepeatTimer, isNotNull);
      expect(reader.page, 2);
      final shell = tester.state<ReaderScaffoldState>(
        find.byType(ReaderScaffold),
      );
      shell.openOrClose();
      await tester.pump();
      Focus.of(tester.element(find.byIcon(Icons.first_page))).requestFocus();
      await tester.pump();
      expect(gallery.keyRepeatTimer, isNull);
      await tester.pump(const Duration(milliseconds: 700));
      expect(reader.page, 2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      shell.openOrClose();
      await tester.pumpAndSettle();
      expect(reader.focusNode.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(reader.page, 1);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets(
    'moving keyboard focus into the menu releases continuous CTRL state',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      try {
        appdata.settings['readerMode'] = ReaderMode.continuousTopToBottom.key;
        await fixture.mount(tester, pushed: false);
        final reader = fixture.readerKey.currentState!;
        final flow = reader.imageViewController! as ContinuousModeState;
        reader.focusNode.requestFocus();
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        expect(flow.isCTRLPressed, isTrue);
        final shell = tester.state<ReaderScaffoldState>(
          find.byType(ReaderScaffold),
        );
        shell.openOrClose();
        await tester.pump();
        Focus.of(tester.element(find.byIcon(Icons.first_page))).requestFocus();
        await tester.pump();
        expect(flow.isCTRLPressed, isFalse);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        shell.openOrClose();
        await tester.pumpAndSettle();
        final before = flow.scrollController.offset;
        await tester.drag(find.byType(ReaderImagesHost), const Offset(0, -200));
        await tester.pumpAndSettle();
        expect(flow.scrollController.offset, greaterThan(before));
      } finally {
        await fixture.dispose(tester);
      }
    },
  );

  testWidgets(
    'progress rejects covered routes and an in-flight content reload',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      try {
        await fixture.mount(tester, pushed: false);
        final reader = fixture.readerKey.currentState!;
        final request = reader.createProgressRequest();
        final navigator = appNavigation.rootNavigatorKey.currentState!;
        unawaited(
          navigator.push<void>(
            MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('Covering page')),
            ),
          ),
        );
        expect(request.selectPage(2), isFalse);
        await tester.pumpAndSettle();
        navigator.pop();
        await tester.pumpAndSettle();
        final loading = reader.controller.beginContentLoad();
        expect(request.selectPage(2), isFalse);
        expect(reader.createProgressRequest().next(), isFalse);
        reader.controller.cancelContentLoad(loading);
        expect(reader.page, 1);
        expect(reader.createProgressRequest().selectPage(2), isTrue);
      } finally {
        await fixture.dispose(tester);
      }
    },
  );

  testWidgets('floating actions respect all seven modes and group boundaries', (
    tester,
  ) async {
    final fixture = await _ReaderFixture.create(tester);
    try {
      await fixture.mount(
        tester,
        pushed: false,
        chapters: const ComicChapters.grouped({
          'First group': {'one': 'First', 'two': 'Second'},
          'Second group': {'three': 'Third'},
        }),
      );
      final reader = fixture.readerKey.currentState!;
      for (final mode in ReaderMode.values) {
        reader.mode = mode;
        reader.controller.restoreChapter(1);
        final first = reader.createChapterNavigationRequest(
          reader.controller.content,
        )!;
        expect(first.canPrevious, false);
        expect(first.canNext, !mode.isGallery && !mode.isWaterfall);
        reader.controller.restoreChapter(2);
        final last = reader.createChapterNavigationRequest(
          reader.controller.content,
        )!;
        expect(first.isCurrent(), false);
        expect(last.canPrevious, !mode.isGallery && !mode.isWaterfall);
        expect(last.canNext, false);
        reader.controller.restoreChapter(3);
        final single = reader.createChapterNavigationRequest(
          reader.controller.content,
        )!;
        expect(single.canPrevious, false);
        expect(single.canNext, false);
      }
    } finally {
      await fixture.dispose(tester);
    }
  });

  for (final mutation in ['order', 'title', 'content']) {
    testWidgets('floating action rejects original $mutation replacement', (
      tester,
    ) async {
      final fixture = await _ReaderFixture.create(tester);
      final chapters = {'one': 'First', 'two': 'Second'};
      try {
        appdata.settings['readerMode'] = ReaderMode.continuousTopToBottom.key;
        await fixture.mount(
          tester,
          pushed: false,
          chapters: ComicChapters(chapters),
        );
        final reader = fixture.readerKey.currentState!;
        final report = tester
            .widget<ReaderContinuousView>(find.byType(ReaderContinuousView))
            .onFloatingButton;
        report(1);
        await tester.pumpAndSettle();
        final action = reader.chapterNavigation.action!;
        if (mutation == 'order') {
          chapters.remove('one');
          chapters['one'] = 'First';
        } else if (mutation == 'title') {
          chapters['one'] = 'Renamed';
        } else {
          reader.controller.replaceChapterImages(reader.images!.toList());
        }
        action.select();
        report(1);
        expect(reader.chapter, 1);
        expect(reader.chapterNavigation.action, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  testWidgets(
    'floating action cannot navigate during reader save and can resume after failure',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final saving = Completer<void>();
      try {
        appdata.settings['readerMode'] = ReaderMode.continuousTopToBottom.key;
        await fixture.mount(
          tester,
          pushed: true,
          chapters: const ComicChapters({'one': 'First', 'two': 'Second'}),
        );
        final reader = fixture.readerKey.currentState!;
        final report = tester
            .widget<ReaderContinuousView>(find.byType(ReaderContinuousView))
            .onFloatingButton;
        report(1);
        await tester.pumpAndSettle();
        final old = reader.chapterNavigation.action!;
        fixture.history.onProgress = (_) => saving.future;
        final exiting = reader.requestExit();
        await tester.pump();
        old.select();
        report(1);
        expect(reader.chapter, 1);
        expect(reader.chapterNavigation.action, isNull);
        saving.completeError(StateError('Save rejected'));
        await exiting;
        await tester.pumpAndSettle();
        report(1);
        expect(reader.chapterNavigation.action, isNotNull);
      } finally {
        if (!saving.isCompleted) saving.complete();
        await fixture.dispose(tester);
      }
    },
  );

  testWidgets('floating callbacks reject a mounted final host close', (
    tester,
  ) async {
    final fixture = await _ReaderFixture.create(tester);
    final host = await _readerHost(() {});
    try {
      appdata.settings['readerMode'] = ReaderMode.continuousTopToBottom.key;
      await fixture.mount(
        tester,
        pushed: false,
        withWindow: false,
        registry: host.selections,
        chapters: const ComicChapters({'one': 'First', 'two': 'Second'}),
      );
      final reader = fixture.readerKey.currentState!;
      final report = tester
          .widget<ReaderContinuousView>(find.byType(ReaderContinuousView))
          .onFloatingButton;
      report(1);
      await tester.pumpAndSettle();
      final action = reader.chapterNavigation.action!;
      var closed = false;
      final closing = host.close().then((_) => closed = true);
      await _pumpUntil(tester, () => closed);
      await closing;
      action.select();
      report(1);
      expect(reader.chapter, 1);
      expect(reader.chapterNavigation.action, isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets(
    'old floating viewport cannot reveal navigation after source replacement',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      var source = _ReaderCommentSource();
      final restore = _readerCommentRegistry(() => source);
      try {
        appdata.settings['readerMode'] = ReaderMode.continuousTopToBottom.key;
        await fixture.mount(
          tester,
          pushed: false,
          chapters: const ComicChapters({'one': 'First', 'two': 'Second'}),
        );
        final old = tester
            .widget<ReaderContinuousView>(find.byType(ReaderContinuousView))
            .onFloatingButton;
        source = _ReaderCommentSource();
        fixture.readerKey.currentState!.update();
        await tester.pumpAndSettle();
        old(1);
        await tester.pumpAndSettle();
        expect(
          find.byIcon(Icons.arrow_forward_ios).hitTestable(),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
        restore();
      }
    },
  );

  testWidgets('old gallery ready cannot hide current continuous navigation', (
    tester,
  ) async {
    final fixture = await _ReaderFixture.create(tester);
    try {
      await fixture.mount(
        tester,
        pushed: false,
        chapters: const ComicChapters({'one': 'First', 'two': 'Second'}),
      );
      final oldReady = tester
          .widget<ReaderGalleryView>(find.byType(ReaderGalleryView))
          .onReady;
      final reader = fixture.readerKey.currentState!;
      reader.mode = ReaderMode.continuousTopToBottom;
      reader.update();
      await tester.pumpAndSettle();
      final current = tester
          .widget<ReaderContinuousView>(find.byType(ReaderContinuousView))
          .onFloatingButton;
      current(1);
      await tester.pumpAndSettle();
      expect(
        find.byIcon(Icons.arrow_forward_ios).hitTestable(),
        findsOneWidget,
      );
      oldReady();
      await tester.pumpAndSettle();
      expect(
        find.byIcon(Icons.arrow_forward_ios).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets(
    'embedded comments exit waits for reader save and retains failed route',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final source = _ReaderCommentSource();
      final restore = _readerCommentRegistry(() => source);
      final saving = Completer<void>();
      try {
        appdata.settings['showChapterComments'] = true;
        appdata.settings['showChapterCommentsAtEnd'] = true;
        await fixture.mount(tester, pushed: true);
        final reader = fixture.readerKey.currentState!;
        reader.toPage(reader.maxPage + 1, animated: false);
        await tester.pumpAndSettle();
        final exit = find.descendant(
          of: find.byType(EmbeddedChapterCommentsPage),
          matching: find.byTooltip('Exit'),
        );
        expect(exit, findsOneWidget);
        fixture.history.onProgress = (_) => saving.future;
        await tester.tap(exit);
        await tester.pump();
        expect(fixture.readerKey.currentState, same(reader));
        saving.completeError(StateError('Comments exit save failed'));
        await tester.pumpAndSettle();
        expect(fixture.readerKey.currentState, same(reader));
        expect(find.text('Unable to close. Please try again.'), findsOneWidget);
        fixture.history.onProgress = null;
        await tester.tap(exit);
        await tester.pumpAndSettle();
        expect(fixture.readerKey.currentState, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        if (!saving.isCompleted) saving.complete();
        await fixture.dispose(tester);
        restore();
      }
    },
  );

  for (final embedded in [false, true]) {
    for (final changeSource in [false, true]) {
      testWidgets(
        'reader retires replies on original target change; embedded=$embedded source=$changeSource',
        (tester) async {
          final fixture = await _ReaderFixture.create(tester);
          final titles = {'one': 'One'};
          var source = _ReaderCommentSource()
            ..load = () async => Res([
              Comment.fromJson({
                'id': 'root',
                'userName': 'Reader',
                'content': 'Original comment',
                'replyCount': 1,
              }),
            ], subData: 1);
          final restore = _readerCommentRegistry(() => source);
          try {
            appdata.settings['showChapterComments'] = true;
            appdata.settings['showChapterCommentsAtEnd'] = true;
            await fixture.mount(
              tester,
              pushed: false,
              chapters: ComicChapters(titles),
            );
            final reader = fixture.readerKey.currentState!;
            if (embedded) {
              reader.toPage(reader.maxPage + 1, animated: false);
            } else {
              tester
                  .state<ReaderScaffoldState>(find.byType(ReaderScaffold))
                  .openChapterComments();
            }
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('Replies').hitTestable().last);
            await tester.pumpAndSettle();
            expect(
              find.byType(ChapterCommentsPage),
              findsNWidgets(embedded ? 1 : 2),
            );
            if (changeSource) {
              source = _ReaderCommentSource()
                ..load = () async =>
                    Res([_readerComment('Replacement source')], subData: 1);
              // Source publication must retire the original route without a
              // manual ReaderState.update or an unrelated widget rebuild.
              ComicSourceManager.current!.notifyStateChange();
            } else {
              titles['one'] = 'Renamed chapter';
              reader.update();
            }
            await tester.pumpAndSettle();
            expect(find.byType(ChapterCommentsPage), findsNothing);
            expect(
              appNavigation.rootNavigatorKey.currentState!.canPop(),
              false,
            );
            if (embedded && changeSource) {
              expect(find.text('Replacement source'), findsOneWidget);
            }
            expect(tester.takeException(), isNull);
          } finally {
            await fixture.dispose(tester);
            restore();
          }
        },
      );
    }
  }

  testWidgets(
    'actual gallery replaces comment source while keeping its viewport',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final pending = Completer<Res<List<Comment>>>();
      var source = _ReaderCommentSource()..load = () => pending.future;
      final restore = _readerCommentRegistry(() => source);
      try {
        appdata.settings['showChapterComments'] = true;
        appdata.settings['showChapterCommentsAtEnd'] = true;
        await fixture.mount(tester, pushed: false);
        final reader = fixture.readerKey.currentState!;
        reader.toPage(reader.maxPage + 1, animated: false);
        await tester.pump();
        final gallery = tester.state<GalleryModeState>(
          find.byType(ReaderGalleryView),
        );
        final original = reader.createChapterCommentsRequest()!;
        source = _ReaderCommentSource()
          ..load = () async =>
              Res([_readerComment('New source comment')], subData: 1);
        reader.update();
        await tester.pumpAndSettle();
        expect(
          tester.state<GalleryModeState>(find.byType(ReaderGalleryView)),
          same(gallery),
        );
        expect(original.isCurrent(), isFalse);
        expect(find.text('New source comment'), findsOneWidget);
        pending.complete(
          Res([_readerComment('Old source comment')], subData: 1),
        );
        await tester.pumpAndSettle();
        expect(find.text('Old source comment'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        if (!pending.isCompleted) pending.complete(Res([], subData: 1));
        await fixture.dispose(tester);
        restore();
      }
    },
  );

  for (final detached in [false, true]) {
    testWidgets('comment send delays actual core close; detached=$detached', (
      tester,
    ) async {
      final fixture = await _ReaderFixture.create(tester);
      final pending = Completer<Res<bool>>();
      var calls = 0, closes = 0;
      final source = _ReaderCommentSource()
        ..send = () {
          calls++;
          return pending.future;
        };
      final restore = _readerCommentRegistry(() => source);
      final host = await _readerHost(() => closes++);
      try {
        appdata.settings['showChapterComments'] = true;
        appdata.settings['showChapterCommentsAtEnd'] = true;
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          registry: host.selections,
        );
        final reader = fixture.readerKey.currentState!;
        reader.toPage(reader.maxPage + 1, animated: false);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField),
          'Pending chapter comment',
        );
        await tester.tap(find.byIcon(Icons.send));
        expect(calls, 1);
        if (detached) await tester.pumpWidget(const SizedBox());
        var closed = false;
        final closing = host.close().then((_) => closed = true);
        await tester.pump();
        expect(closed, isFalse);
        expect(closes, 0);
        pending.complete(const Res(true));
        await _pumpUntil(tester, () => closed);
        await closing;
        expect(closes, 1);
        expect(calls, 1);
        expect(tester.takeException(), isNull);
      } finally {
        if (!pending.isCompleted) pending.complete(const Res(true));
        await fixture.dispose(tester);
        restore();
        await host.close();
      }
    });
  }

  for (final change in ['chapter id', 'chapter order', 'chapter title']) {
    testWidgets('export rejects $change changed during selection', (
      tester,
    ) async {
      final fixture = await _ReaderFixture.create(tester);
      final chapters = {'one': 'One', 'two': 'Two'};
      const selector = MethodChannel('plugins.flutter.io/file_selector');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var dialogs = 0;
      messenger.setMockMethodCallHandler(selector, (_) async {
        dialogs++;
        return null;
      });
      try {
        await fixture.mount(
          tester,
          pushed: false,
          chapters: ComicChapters(chapters),
        );
        final reader = fixture.readerKey.currentState!;
        final shell = tester.state<ReaderScaffoldState>(
          find.byType(ReaderScaffold),
        );
        Future<void>? export;
        final detach = reader.imageWork.retainTasks((task) {
          export ??= task.done;
          return () {};
        });
        await tester.runAsync(() async {
          shell.saveCurrentImage();
          switch (change) {
            case 'chapter id':
              chapters.remove('one');
            case 'chapter order':
              chapters.remove('one');
              chapters['one'] = 'One';
            case 'chapter title':
              chapters['one'] = 'Renamed';
          }
          expect(export, isNotNull);
          await export;
        });
        detach();
        expect(dialogs, 0);
        expect(tester.takeException(), isNull);
      } finally {
        messenger.setMockMethodCallHandler(selector, null);
        await fixture.dispose(tester);
      }
    });
  }

  testWidgets(
    'failed favorite status offers read-only retry and preserves data',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      var renamed = false;
      try {
        await fixture.mount(tester, pushed: false);
        final shell = tester.state<ReaderScaffoldState>(
          find.byType(ReaderScaffold),
        );
        shell.openOrClose();
        fixture.history.imageFavoritesDatabase.execute(
          'ALTER TABLE image_favorites RENAME TO unavailable_favorites',
        );
        renamed = true;
        _imageOwner!.notifyChanges();
        await tester.pumpAndSettle();
        final retry = find.byTooltip('Unable to load image collection. Retry');
        expect(retry, findsOneWidget);
        expect(find.byIcon(Icons.favorite_border), findsNothing);
        fixture.history.imageFavoritesDatabase.execute(
          'ALTER TABLE unavailable_favorites RENAME TO image_favorites',
        );
        renamed = false;
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.favorite_border), findsOneWidget);
        expect(await _imageOwner!.getAll(), isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        if (renamed) {
          fixture.history.imageFavoritesDatabase.execute(
            'ALTER TABLE unavailable_favorites RENAME TO image_favorites',
          );
        }
        await fixture.dispose(tester);
      }
    },
  );

  testWidgets('export request rejects content reload and final host close', (
    tester,
  ) async {
    final fixture = await _ReaderFixture.create(tester);
    final registry = SelectionTaskRegistry();
    try {
      await fixture.mount(
        tester,
        pushed: false,
        withWindow: false,
        registry: registry,
      );
      final reader = fixture.readerKey.currentState!;
      final request = reader.createImageExportRequest()!;
      final settings = reader.createSettingsRequest()!;
      expect(request.resolve(0)?.chapterId, 'one');
      reader.controller.beginContentLoad();
      expect(request.resolve(0), isNull);
      expect(reader.createImageExportRequest(), isNull);
      final closing = registry.closeAndWait();
      expect(reader.createImageExportRequest(), isNull);
      expect(reader.createSettingsRequest(), isNull);
      expect(settings.isCurrent(), isFalse);
      await tester.pump();
      await closing;
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('settings panel applies mode to its original reader', (
    tester,
  ) async {
    final fixture = await _ReaderFixture.create(tester);
    try {
      await fixture.mount(tester, pushed: false);
      final reader = fixture.readerKey.currentState!;
      final shell = tester.state<ReaderScaffoldState>(
        find.byType(ReaderScaffold),
      );
      shell.openSetting();
      await tester.pumpAndSettle();
      final panel = tester.widget<ReaderSettingsPanel>(
        find.byType(ReaderSettingsPanel),
      );
      final settings = tester.widget<ReaderSettings>(
        find.byType(ReaderSettings),
      );
      expect(panel.work, same(reader.imageWork));
      expect(settings.comicId, 'book');
      expect(settings.comicSource, 'local');
      appdata.settings['readerMode'] = ReaderMode.continuousTopToBottom.key;
      settings.onChanged!('readerMode');
      await tester.pumpAndSettle();
      expect(reader.mode, ReaderMode.continuousTopToBottom);
      expect(settings.currentReaderMode!(), reader.mode.key);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  for (final change in ['comic', 'source', 'chapters']) {
    testWidgets(
      'reader requests reject replacement $change on the same State',
      (tester) async {
        final fixture = await _ReaderFixture.create(tester);
        try {
          await fixture.mount(tester, pushed: false);
          final reader = fixture.readerKey.currentState!;
          final export = reader.createImageExportRequest()!;
          final settings = reader.createSettingsRequest()!;
          await fixture.mount(
            tester,
            pushed: false,
            expectContent: false,
            comicId: change == 'comic' ? 'replacement' : 'book',
            comicType: change == 'source'
                ? const _OtherComicType()
                : ComicType.local,
            chapters: change == 'chapters'
                ? const ComicChapters({'one': 'Replacement chapter'})
                : _chapters,
          );
          expect(fixture.readerKey.currentState, same(reader));
          expect(export.resolve(0), isNull);
          expect(settings.isCurrent(), change == 'chapters');
          if (change != 'chapters') {
            settings.apply(
              'readerMode',
              applyShellEffect: (_) => fail('Old shell effect'),
            );
            expect(reader.mode, ReaderMode.galleryLeftToRight);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
    );
  }

  testWidgets(
    'spread selection exports the second duplicate with its source number',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      const selector = MethodChannel('plugins.flutter.io/file_selector');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final destination = File('${fixture.directory.path}/duplicate.png');
      Object? arguments;
      messenger.setMockMethodCallHandler(selector, (call) async {
        arguments = call.arguments;
        return destination.path;
      });
      try {
        appdata.settings['readerScreenPicNumberForLandscape'] = 2;
        appdata.settings['readerScreenPicNumberForPortrait'] = 2;
        appdata.settings['showSingleImageOnFirstPage'] = false;
        await fixture.mount(tester, pushed: false);
        final reader = fixture.readerKey.currentState!;
        final key = reader.images!.first;
        reader.controller.replaceChapterImages([key, key, key]);
        reader.update();
        await tester.pumpAndSettle();
        final gallery = reader.imageViewController! as GalleryModeState;
        final visible =
            gallery.imageStates.keys
                .whereType<ComicImageState>()
                .where((image) => image.visibleInReader)
                .toList()
              ..sort(
                (a, b) => tester
                    .getCenter(find.byWidget(a.widget))
                    .dx
                    .compareTo(tester.getCenter(find.byWidget(b.widget)).dx),
              );
        expect(visible, hasLength(2));
        final point = tester.getCenter(find.byWidget(visible.last.widget));
        Future<void>? exporting;
        var done = false;
        final detach = reader.imageWork.retainTasks((task) {
          exporting ??= task.done.then((_) => done = true);
          return () {};
        });
        try {
          tester
              .state<ReaderScaffoldState>(find.byType(ReaderScaffold))
              .saveCurrentImage();
          await tester.pumpAndSettle();
          await tester.tapAt(point);
          await _pumpUntil(tester, () => done);
          await exporting;
          expect(arguments.toString(), contains('Book_EP1_P2.png'));
          expect(
            destination.readAsBytesSync(),
            File(key.substring(7)).readAsBytesSync(),
          );
          expect(tester.takeException(), isNull);
        } finally {
          detach();
        }
      } finally {
        messenger.setMockMethodCallHandler(selector, null);
        await fixture.dispose(tester);
      }
    },
  );

  testWidgets('shell export saves original bytes after page navigation', (
    tester,
  ) async {
    final fixture = await _ReaderFixture.create(tester);
    const selector = MethodChannel('plugins.flutter.io/file_selector');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final selected = Completer<String?>();
    final dialog = Completer<void>();
    final destination = File('${fixture.directory.path}/export.png');
    Object? arguments;
    messenger.setMockMethodCallHandler(selector, (call) {
      arguments = call.arguments;
      dialog.complete();
      return selected.future;
    });
    try {
      await fixture.mount(tester, pushed: false);
      final reader = fixture.readerKey.currentState!;
      final source = File(reader.images!.first.substring(7)).readAsBytesSync();
      Future<void>? exporting;
      var exportDone = false;
      final detach = reader.imageWork.retainTasks((task) {
        exporting ??= task.done.then((_) => exportDone = true);
        return () {};
      });
      final shell = tester.state<ReaderScaffoldState>(
        find.byType(ReaderScaffold),
      );
      shell.saveCurrentImage();
      await _pumpUntil(tester, () => dialog.isCompleted || exportDone);
      expect(dialog.isCompleted, isTrue);
      reader.toPage(2, animated: false);
      await tester.pumpAndSettle();
      selected.complete(destination.path);
      await _pumpUntil(tester, () => exportDone);
      await exporting;
      detach();
      expect(arguments.toString(), contains('Book_EP1_P1.png'));
      expect(destination.readAsBytesSync(), source);
      expect(tester.takeException(), isNull);
    } finally {
      if (!selected.isCompleted) selected.complete(null);
      messenger.setMockMethodCallHandler(selector, null);
      await fixture.dispose(tester);
    }
  });

  for (final detached in [false, true]) {
    testWidgets(
      'shell export retains native save during host close; detached=$detached',
      (tester) async {
        final fixture = await _ReaderFixture.create(tester);
        var coreCloses = 0;
        final host = await _readerHost(() => coreCloses++);
        const selector = MethodChannel('plugins.flutter.io/file_selector');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final selected = Completer<String?>();
        final dialog = Completer<void>();
        messenger.setMockMethodCallHandler(selector, (_) {
          dialog.complete();
          return selected.future;
        });
        try {
          await fixture.mount(
            tester,
            pushed: false,
            withWindow: false,
            registry: host.selections,
          );
          final shell = tester.state<ReaderScaffoldState>(
            find.byType(ReaderScaffold),
          );
          shell.saveCurrentImage();
          await _pumpUntil(tester, () => dialog.isCompleted);
          if (detached) await tester.pumpWidget(const SizedBox());
          var closed = false;
          final closing = host.close().then((_) => closed = true);
          await tester.pump();
          expect(closed, isFalse);
          expect(coreCloses, 0);
          selected.complete(null);
          await _pumpUntil(tester, () => closed);
          await closing;
          expect(coreCloses, 1);
          expect(tester.takeException(), isNull);
        } finally {
          if (!selected.isCompleted) selected.complete(null);
          messenger.setMockMethodCallHandler(selector, null);
          await fixture.dispose(tester);
          await host.close();
        }
      },
    );
  }

  for (final detach in [false, true]) {
    testWidgets(
      'host drains queued favorite read before core close; detached=$detach',
      (tester) async {
        final fixture = await _ReaderFixture.create(tester);
        var coreCloses = 0;
        final host = await _readerHost(() => coreCloses++);
        final release = Completer<void>();
        Future<void>? barrier;
        try {
          await fixture.mount(
            tester,
            pushed: false,
            withWindow: false,
            registry: host.selections,
          );
          barrier = fixture.history.accessImageFavorites(
            (_, _) => release.future,
          );
          _imageOwner!.notifyChanges();
          await tester.pump();
          expect(find.byTooltip('Loading image collection'), findsOneWidget);
          if (detach) await tester.pumpWidget(const SizedBox());
          var closed = false;
          final closing = host.close().then((_) => closed = true);
          await tester.pump();
          expect(coreCloses, 0);
          expect(closed, isFalse);
          release.complete();
          await barrier;
          await _pumpUntil(tester, () => closed);
          await closing;
          expect(coreCloses, 1);
          expect(fixture.history.hasPendingWrites, isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          if (!release.isCompleted) release.complete();
          await barrier;
          await fixture.dispose(tester);
          await host.close();
        }
      },
    );
  }

  testWidgets(
    'favorite request rejects a replaced database and frozen reader',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final registry = SelectionTaskRegistry();
      final replacement = _ControlledHistory();
      try {
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          registry: registry,
        );
        final reader = fixture.readerKey.currentState!;
        final request = reader.createImageFavoriteRequest()!;
        expect(request.isCurrent(), isTrue);
        await _replaceHistory(tester, replacement);
        expect(request.isCurrent(), isFalse);
        await expectLater(
          Future.sync(() => request.toggle(0, () {})),
          throwsA(isA<ImageWorkTaskCancelled>()),
        );
        await _replaceHistory(tester, fixture.history, images: fixture.images);
        final closing = registry.closeAndWait();
        expect(reader.createImageFavoriteRequest(), isNull);
        expect(reader.createImageFavoriteQuery(), isNull);
        expect(request.isCurrent(), isFalse);
        await tester.pump();
        await closing;
      } finally {
        _historyOwner = fixture.history;
        _imageOwner = fixture.images;
        await fixture.dispose(tester);
      }
    },
  );

  testWidgets(
    'spread favorite status uses source image numbers and prompts for ambiguous selection',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      try {
        appdata.settings['readerScreenPicNumberForLandscape'] = 2;
        appdata.settings['readerScreenPicNumberForPortrait'] = 2;
        appdata.settings['showSingleImageOnFirstPage'] = false;
        await fixture.mount(tester, pushed: false);
        final reader = fixture.readerKey.currentState!;
        expect(reader.pageLayout.imageRange(1, 3), (0, 2));
        expect(await reader.createImageFavoriteQuery()!.read(), isNull);
        expect(find.byTooltip('Select an image to collect'), findsOneWidget);
        await _imageOwner!.toggle(
          ImageFavoriteInput(
            id: 'book',
            sourceKey: 'local',
            eid: 'one',
            ep: 1,
            epName: 'Chapter one',
            title: 'Book',
            subtitle: '',
            author: '',
            tags: [],
            translatedTags: [],
            maxPage: 3,
            page: 3,
            imageKey: reader.images![2],
            coverKey: reader.images!.first,
          ),
        );
        reader.toPage(2, animated: false);
        await tester.pumpAndSettle();
        expect(reader.pageLayout.imageRange(reader.page, 3), (2, 3));
        expect(await reader.createImageFavoriteQuery()!.read(), isTrue);
        expect(find.byTooltip('Uncollect the image'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
  );

  testWidgets('chapter drawer routes repeated IDs to their flattened chapter', (
    tester,
  ) async {
    final fixture = await _ReaderFixture.create(tester);
    try {
      await fixture.mount(
        tester,
        pushed: true,
        chapters: const ComicChapters.grouped({
          'First volume': {'one': 'First chapter'},
          'Second volume': {'one': 'Second chapter'},
        }),
      );
      final shell = tester.state<ReaderScaffoldState>(
        find.byType(ReaderScaffold),
      );
      shell.openChapterDrawer();
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.download_done_rounded), findsOneWidget);
      await tester.tap(find.text('Second volume'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second chapter'));
      await tester.pump();
      expect(fixture.readerKey.currentState!.chapter, 2);
      expect(find.byType(ReaderChaptersView), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets(
    'old menu cannot select replacement chapter data or dismiss new menu',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      try {
        const original = ComicChapters.grouped({
          'Volume': {'one': 'Original chapter'},
        });
        const replacement = ComicChapters.grouped({
          'Volume': {'one': 'Replacement chapter'},
        });
        await fixture.mount(tester, pushed: false, chapters: original);
        var shell = tester.state<ReaderScaffoldState>(
          find.byType(ReaderScaffold),
        );
        shell.openChapterDrawer();
        await tester.pumpAndSettle();
        final old = tester.widget<ReaderChaptersView>(
          find.byType(ReaderChaptersView),
        );
        final request = fixture.readerKey.currentState!.createChapterMenu()!;
        await fixture.mount(tester, pushed: false, chapters: replacement);
        expect(request.select(1), isFalse);
        old.onSelect(1);
        await tester.pumpAndSettle();
        shell = tester.state<ReaderScaffoldState>(find.byType(ReaderScaffold));
        shell.openChapterDrawer();
        await tester.pumpAndSettle();
        old.onSelect(1);
        old.onClose();
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(ReaderChaptersView),
            matching: find.text('Replacement chapter'),
          ),
          findsOneWidget,
        );
        expect(fixture.readerKey.currentState!.chapter, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
  );

  testWidgets('chapter requests reject mutated maps and final session close', (
    tester,
  ) async {
    final fixture = await _ReaderFixture.create(tester);
    final registry = SelectionTaskRegistry();
    try {
      final chapters = {'one': 'Original chapter'};
      await fixture.mount(
        tester,
        pushed: false,
        withWindow: false,
        registry: registry,
        chapters: ComicChapters(chapters),
      );
      final reader = fixture.readerKey.currentState!;
      final original = reader.createChapterMenu()!;
      chapters['one'] = 'Edited chapter';
      expect(original.select(1), isFalse);
      final current = reader.createChapterMenu()!;
      final closing = registry.closeAndWait();
      expect(reader.createChapterMenu(), isNull);
      expect(current.select(1), isFalse);
      await tester.pump();
      await closing;
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  for (final detach in [false, true]) {
    testWidgets(
      'host drains both platform effects before core close; detached=$detach',
      (tester) async {
        final fixture = await _ReaderFixture.create(tester);
        final platform = _PlatformEffectsProbe()..install();
        var coreCloses = 0;
        final host = await _readerHost(() => coreCloses++);
        final orientation = Completer<void>(), bars = Completer<void>();
        try {
          appdata.settings['showSystemStatusBar'] = false;
          await fixture.mount(
            tester,
            pushed: false,
            withWindow: false,
            registry: host.selections,
          );
          final reader = fixture.readerKey.currentState!;
          reader.cycleReaderOrientation();
          await tester.pump();
          expect(platform.orientation, contains('portraitUp'));
          expect(platform.barsVisible, isFalse);
          platform.onOrientation = (value) =>
              value.isEmpty ? orientation.future : Future.value();
          platform.onBars = (value) => value ? bars.future : Future.value();
          if (detach) await tester.pumpWidget(const SizedBox());
          var closed = false;
          final closing = host.close().then((_) => closed = true);
          reader.cycleReaderOrientation();
          await tester.pump();
          expect(closed, isFalse);
          expect(coreCloses, 0);
          orientation.complete();
          await tester.pump();
          expect(closed, isFalse);
          bars.complete();
          await _pumpUntil(tester, () => closed);
          await closing;
          expect(coreCloses, 1);
          expect(platform.orientation, isEmpty);
          expect(platform.barsVisible, isTrue);
          expect(fixture.notifications, 1);
          expect(tester.takeException(), isNull);
        } finally {
          if (!orientation.isCompleted) orientation.complete();
          if (!bars.isCompleted) bars.complete();
          await fixture.dispose(tester);
          await host.sync.closeAndWait();
          platform.uninstall();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets(
    'native effects failure blocks core and retry does not replay reader persistence',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final platform = _PlatformEffectsProbe()..install();
      var coreCloses = 0;
      final host = await _readerHost(() => coreCloses++);
      var failing = true;
      try {
        appdata.settings['showSystemStatusBar'] = false;
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          registry: host.selections,
        );
        fixture.readerKey.currentState!.cycleReaderOrientation();
        await tester.pump();
        platform.onOrientation = (_) async {
          if (failing) throw StateError('orientation restoration');
        };
        platform.onBars = (_) async {
          if (failing) throw StateError('system bars restoration');
        };
        Object? failure;
        final closing = host.close().catchError((Object error) {
          failure = error;
        });
        await _pumpUntil(tester, () => failure != null);
        await closing;
        expect(failure.toString(), contains('orientation restoration'));
        expect(failure.toString(), contains('system bars restoration'));
        expect(coreCloses, 0);
        final progress = fixture.history.progress.length,
            durations = fixture.history.durations.length;
        expect(fixture.notifications, 1);
        failing = false;
        var closed = false;
        final retry = host.close().then((_) => closed = true);
        await _pumpUntil(tester, () => closed);
        await retry;
        expect(fixture.history.progress, hasLength(progress));
        expect(fixture.history.durations, hasLength(durations));
        expect(fixture.notifications, 1);
        expect(coreCloses, 1);
        expect(tester.takeException(), isNull);
      } finally {
        failing = false;
        await fixture.dispose(tester);
        await host.sync.closeAndWait();
        platform.uninstall();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'old reader removal cannot overwrite new orientation or menu bars',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final platform = _PlatformEffectsProbe()..install();
      try {
        appdata.settings['showSystemStatusBar'] = false;
        await fixture.mount(tester, pushed: true, withWindow: false);
        final oldRoute = ModalRoute.of(fixture.readerKey.currentContext!)!;
        fixture.readerKey.currentState!.cycleReaderOrientation();
        await tester.pump();
        final nextKey = GlobalKey<_TestReaderState>();
        unawaited(
          appNavigation.rootNavigatorKey.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                body: _TestReader(key: nextKey, onClosed: () {}),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        nextKey.currentState!.cycleReaderOrientation();
        await tester.pump();
        nextKey.currentState!.cycleReaderOrientation();
        await tester.pump();
        expect(platform.orientation, contains('landscapeLeft'));
        platform.events.clear();
        appNavigation.rootNavigatorKey.currentState!.removeRoute(oldRoute);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(platform.events, isEmpty);
        final scaffold = tester.state<ReaderScaffoldState>(
          find.byType(ReaderScaffold),
        );
        scaffold.openOrClose();
        await tester.pump();
        expect(platform.barsVisible, isTrue);
        scaffold.openOrClose();
        await tester.pump();
        expect(platform.barsVisible, isFalse);
        expect(platform.orientation, contains('landscapeLeft'));
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
        platform.uninstall();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'reader back waits for native effects restoration',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final platform = _PlatformEffectsProbe()..install();
      final restored = Completer<void>();
      try {
        appdata.settings['showSystemStatusBar'] = false;
        await fixture.mount(tester, pushed: true, withWindow: false);
        final reader = fixture.readerKey.currentState!;
        reader.cycleReaderOrientation();
        await tester.pump();
        platform.onBars = (value) => value ? restored.future : Future.value();
        var left = false;
        final leaving = reader.requestExit().then((_) => left = true);
        await tester.pump();
        expect(left, isFalse);
        expect(
          ModalRoute.of(fixture.readerKey.currentContext!)!.isCurrent,
          isTrue,
        );
        restored.complete();
        await _pumpUntil(tester, () => left);
        await leaving;
        await tester.pump(const Duration(seconds: 1));
        expect(fixture.readerKey.currentState, isNull);
        expect(platform.orientation, isEmpty);
        expect(platform.barsVisible, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        if (!restored.isCompleted) restored.complete();
        await fixture.dispose(tester);
        platform.uninstall();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'reversible window failure resumes reader effects',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final platform = _PlatformEffectsProbe()..install();
      var failing = true;
      try {
        appdata.settings['showSystemStatusBar'] = false;
        await fixture.mount(
          tester,
          pushed: false,
          beforeReaderMount: (frame) {
            frame.addExitTask(() async {
              if (failing) throw StateError('other preparation');
            });
          },
        );
        fixture.readerKey.currentState!.cycleReaderOrientation();
        await tester.pump();
        platform.events.clear();
        fixture.closeWindow(tester);
        await _pumpUntil(
          tester,
          () => platform.events
              .where((event) => event == 'bars:false')
              .isNotEmpty,
        );
        expect(tester.takeException(), isA<StateError>());
        expect(
          platform.events,
          containsAllInOrder(['bars:true', 'bars:false']),
        );
        expect(platform.orientation, contains('portraitUp'));
        expect(fixture.exits, 0);
        failing = false;
        fixture.closeWindow(tester);
        await _pumpUntil(tester, () => fixture.exits == 1);
        expect(platform.orientation, isEmpty);
        expect(platform.barsVisible, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        failing = false;
        await fixture.dispose(tester);
        platform.uninstall();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'platform release remains with original registry during reparenting',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final platform = _PlatformEffectsProbe()..install();
      final original = SelectionTaskRegistry(),
          replacement = SelectionTaskRegistry();
      final registries = ValueNotifier(original);
      final restored = Completer<void>();
      try {
        appdata.settings['showSystemStatusBar'] = false;
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          registries: registries,
        );
        fixture.readerKey.currentState!.cycleReaderOrientation();
        await tester.pump();
        platform.onBars = (value) => value ? restored.future : Future.value();
        registries.value = replacement;
        await tester.pump();
        var closed = false;
        final closing = original.closeAndWait().then((_) => closed = true);
        await tester.pump();
        expect(closed, isFalse);
        restored.complete();
        await _pumpUntil(tester, () => closed);
        await closing;
        var replacementClosed = false;
        final next = replacement.closeAndWait().then(
          (_) => replacementClosed = true,
        );
        await _pumpUntil(tester, () => replacementClosed);
        await next;
        expect(fixture.notifications, 1);
        expect(tester.takeException(), isNull);
      } finally {
        if (!restored.isCompleted) restored.complete();
        await fixture.dispose(tester);
        registries.dispose();
        platform.uninstall();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'closed host rejects application defaults and reader native work',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final platform = _PlatformEffectsProbe()..install();
      final registry = SelectionTaskRegistry();
      try {
        await registry.closeAndWait();
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          registry: registry,
          expectContent: false,
        );
        expect(platform.events, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
        platform.uninstall();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'reader exit waits for platform failure and preserves independent save failure',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final platform = _PlatformEffectsProbe()..install();
      final restoring = Completer<void>();
      try {
        appdata.settings['showSystemStatusBar'] = false;
        await fixture.mount(tester, pushed: true, withWindow: false);
        final reader = fixture.readerKey.currentState!;
        final progressError = StateError('progress preparation failed');
        final progressStack = StackTrace.fromString(
          'progress preparation stack',
        );
        fixture.history.onProgress = (_) =>
            Future.error(progressError, progressStack);
        reader.toPage(2, animated: false);
        platform.onBars = (visible) =>
            visible ? restoring.future : Future.value();
        final guard = tester.widget<ReaderExitGuard>(
          find.byType(ReaderExitGuard),
        );
        Object? failure;
        var finished = false;
        final preparation = guard
            .prepare()
            .then<void>(
              (release) => release(),
              onError: (Object error, StackTrace _) {
                failure = error;
              },
            )
            .whenComplete(() => finished = true);
        await tester.pump();
        expect(finished, isFalse);
        restoring.completeError(StateError('platform preparation failed'));
        await _pumpUntil(tester, () => finished);
        await preparation;
        expect(failure, isA<ReaderWindowFailure>());
        final reading =
            (failure as ReaderWindowFailure).failures
                    .singleWhere(
                      (entry) => entry.operation == 'reading preparation',
                    )
                    .error
                as ReaderSessionFailure;
        expect(
          (reading.failures.single.error as ReaderProgressFailure).cause,
          same(progressError),
        );
        expect(
          reading.failures.single.stackTrace.toString(),
          progressStack.toString(),
        );
        expect(failure.toString(), contains('platform preparation failed'));
        expect(reader.controller.isDisposed, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        if (!restoring.isCompleted) restoring.complete();
        platform.onBars = null;
        await fixture.dispose(tester);
        platform.uninstall();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final visual in [
    (size: const Size(375, 667), dark: false, scale: 1.0),
    (size: const Size(375, 667), dark: true, scale: 2.0),
    (size: const Size(667, 375), dark: false, scale: 2.0),
    (size: const Size(667, 375), dark: true, scale: 1.0),
  ]) {
    testWidgets('reader top bar retains content through window insets $visual', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(visual.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = await _ReaderFixture.create(tester);
      final native = _NativeWindow();
      try {
        await fixture.mount(
          tester,
          pushed: false,
          windowCoordinator: native.coordinator,
          textScale: visual.scale,
          reducedMotion: visual.scale > 1,
          brightness: visual.dark ? Brightness.dark : Brightness.light,
        );
        final scaffold = tester.state<ReaderScaffoldState>(
          find.byType(ReaderScaffold),
        );
        scaffold.openOrClose();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        fixture.readerKey.currentState!.fullscreen();
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 10));
          expect(tester.takeException(), isNull);
        }
        final top = find.byType(ReaderTopBar);
        expect(
          MediaQuery.textScalerOf(tester.element(top)).scale(16),
          16 * visual.scale,
        );
        final bar = tester.getRect(top);
        for (final label in ['Book', _chapters.titles.first]) {
          final text = find.descendant(of: top, matching: find.text(label));
          expect(text, findsOneWidget);
          final bounds = tester.getRect(text);
          expect(bounds.top, greaterThanOrEqualTo(bar.top));
          expect(bounds.bottom, lessThanOrEqualTo(bar.bottom));
        }
        final back = find.descendant(
          of: top,
          matching: find.byType(BackButton),
        );
        expect(tester.getSize(back).height, greaterThanOrEqualTo(44));
        final directory = Platform.environment['WINDOW_OWNER_QA_DIRECTORY'];
        if (directory != null) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byType(RepaintBoundary).first,
            );
            final image = await boundary.toImage(pixelRatio: 1);
            try {
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '$directory/reader-${visual.size.width.toInt()}-${visual.dark ? 'dark' : 'light'}-${visual.scale.toInt()}x.png',
              ).writeAsBytes(data!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        fixture.readerKey.currentState!.fullscreen();
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 10));
          expect(tester.takeException(), isNull);
        }
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  testWidgets(
    'production window manager channel acknowledgement gates core close',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      var coreCloses = 0;
      final host = await _readerHost(() => coreCloses++);
      final restoring = Completer<void>();
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('window_manager'), (
            call,
          ) async {
            calls.add(call);
            if (call.method == 'setFullScreen' &&
                (call.arguments as Map)['isFullScreen'] == false) {
              await restoring.future;
            }
            return false;
          });
      try {
        await fixture.mount(tester, pushed: false, registry: host.selections);
        fixture.readerKey.currentState!.fullscreen();
        await _pumpUntil(
          tester,
          () => calls.any((call) => call.method == 'show'),
        );
        await tester.pump();
        var closed = false;
        final closing = host.close().then((_) => closed = true);
        await tester.pump();
        expect(
          calls.where((call) => call.method == 'setFullScreen'),
          hasLength(2),
        );
        expect(coreCloses, 0);
        expect(closed, isFalse);
        restoring.complete();
        await _pumpUntil(tester, () => closed);
        await closing;
        expect(coreCloses, 1);
        expect(tester.takeException(), isNull);
      } finally {
        if (!restoring.isCompleted) restoring.complete();
        await fixture.dispose(tester);
        await host.sync.closeAndWait();
      }
    },
  );

  for (final detach in [false, true]) {
    testWidgets('host waits for window restoration; detached=$detach', (
      tester,
    ) async {
      final fixture = await _ReaderFixture.create(tester);
      var coreCloses = 0;
      final host = await _readerHost(() => coreCloses++);
      final native = _NativeWindow();
      final restored = Completer<void>();
      try {
        await fixture.mount(
          tester,
          pushed: false,
          registry: host.selections,
          windowCoordinator: native.coordinator,
        );
        fixture.readerKey.currentState!.fullscreen();
        await _pumpUntil(tester, () => native.fullscreen);
        await tester.pump();
        native.onFullscreen = (value) =>
            value ? Future.value() : restored.future;
        if (detach) await tester.pumpWidget(const SizedBox());
        var closed = false;
        final closing = host.close().then((_) => closed = true);
        await tester.pump();
        expect(coreCloses, 0);
        expect(closed, isFalse);
        expect(native.fullscreen, isTrue);
        restored.complete();
        await _pumpUntil(tester, () => closed);
        await closing;
        expect(native.fullscreen, isFalse);
        expect(native.visible, isTrue);
        expect(coreCloses, 1);
        expect(fixture.notifications, 1);
        expect(tester.takeException(), isNull);
      } finally {
        if (!restored.isCompleted) restored.complete();
        await fixture.dispose(tester);
        await host.sync.closeAndWait();
      }
    });
  }

  testWidgets(
    'failed window show blocks core; retry only shows and preserves reader writes',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      var coreCloses = 0;
      final host = await _readerHost(() => coreCloses++);
      final native = _NativeWindow();
      var failing = true;
      try {
        await fixture.mount(
          tester,
          pushed: false,
          registry: host.selections,
          windowCoordinator: native.coordinator,
        );
        fixture.readerKey.currentState!.fullscreen();
        await _pumpUntil(tester, () => native.fullscreen && native.visible);
        await tester.pump();
        native.onShow = () async {
          if (failing) throw StateError('native window show');
        };
        Object? failure;
        final closing = host.close().catchError((Object error) {
          failure = error;
        });
        await _pumpUntil(tester, () => failure != null);
        await closing;
        expect(failure.toString(), contains('native window show'));
        expect(coreCloses, 0);
        expect(native.fullscreen, isFalse);
        expect(native.visible, isFalse);
        final progress = fixture.history.progress.length;
        final durations = fixture.history.durations.length;
        native.events.clear();
        failing = false;
        var closed = false;
        final retry = host.close().then((_) => closed = true);
        await _pumpUntil(tester, () => closed);
        await retry;
        expect(native.events, ['show']);
        expect(coreCloses, 1);
        expect(fixture.history.progress, hasLength(progress));
        expect(fixture.history.durations, hasLength(durations));
        expect(fixture.notifications, 1);
        expect(tester.takeException(), isNull);
      } finally {
        failing = false;
        await fixture.dispose(tester);
        await host.sync.closeAndWait();
      }
    },
  );

  testWidgets(
    'removing an old reader keeps newer reader fullscreen in the shared frame',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final native = _NativeWindow();
      final nextKey = GlobalKey<_TestReaderState>();
      try {
        await fixture.mount(
          tester,
          pushed: false,
          windowCoordinator: native.coordinator,
        );
        final old = fixture.readerKey.currentState!;
        final oldRoute = ModalRoute.of(old.context)!;
        old.fullscreen();
        await _pumpUntil(tester, () => native.fullscreen && native.visible);
        unawaited(
          appNavigation.rootNavigatorKey.currentState!.push<void>(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                body: _TestReader(
                  key: nextKey,
                  onClosed: () {},
                  windowCoordinator: native.coordinator,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(nextKey.currentState, isNotNull);
        native.events.clear();
        appNavigation.rootNavigatorKey.currentState!.removeRoute(oldRoute);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(fixture.readerKey.currentState, isNull);
        expect(native.fullscreen, isTrue);
        expect(native.events, isEmpty);
        expect(
          tester
              .widget<WindowFrameController>(find.byType(WindowFrameController))
              .isWindowFrameHidden,
          isTrue,
        );
        nextKey.currentState!.fullscreen();
        await _pumpUntil(tester, () => !native.fullscreen);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
  );

  testWidgets(
    'window close restores fullscreen after a later reversible preparation fails',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final native = _NativeWindow();
      var failing = true;
      Future<void> otherPreparation() async {
        if (failing) throw StateError('other window preparation');
      }

      try {
        await fixture.mount(
          tester,
          pushed: false,
          windowCoordinator: native.coordinator,
          beforeReaderMount: (frame) => frame.addExitTask(otherPreparation),
        );
        fixture.readerKey.currentState!.fullscreen();
        await _pumpUntil(tester, () => native.fullscreen && native.visible);
        native.events.clear();
        fixture.closeWindow(tester);
        await _pumpUntil(
          tester,
          () => native.events.where((e) => e == 'fullscreen:true').isNotEmpty,
        );
        await tester.pump();
        expect(tester.takeException(), isA<StateError>());
        expect(
          native.events,
          containsAllInOrder(['fullscreen:false', 'fullscreen:true']),
        );
        expect(native.fullscreen, isTrue);
        expect(fixture.exits, 0);
        failing = false;
        fixture.closeWindow(tester);
        await _pumpUntil(tester, () => fixture.exits == 1);
        expect(native.fullscreen, isFalse);
        expect(native.visible, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
  );

  testWidgets(
    'window release stays with original application after reader reparenting',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final oldRegistry = SelectionTaskRegistry();
      final newRegistry = SelectionTaskRegistry();
      final registries = ValueNotifier(oldRegistry);
      final native = _NativeWindow();
      final release = Completer<void>();
      try {
        await fixture.mount(
          tester,
          pushed: false,
          registries: registries,
          windowCoordinator: native.coordinator,
        );
        fixture.readerKey.currentState!.fullscreen();
        await _pumpUntil(tester, () => native.fullscreen && native.visible);
        native.onFullscreen = (value) =>
            value ? Future.value() : release.future;
        registries.value = newRegistry;
        await tester.pump();
        var oldClosed = false;
        var newClosed = false;
        final oldClose = oldRegistry.closeAndWait().then(
          (_) => oldClosed = true,
        );
        final newClose = newRegistry.closeAndWait().then(
          (_) => newClosed = true,
        );
        await tester.pump();
        expect(oldClosed, isFalse);
        expect(newClosed, isTrue);
        release.complete();
        await _pumpUntil(tester, () => oldClosed);
        await Future.wait([oldClose, newClose]);
        expect(native.fullscreen, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        if (!release.isCompleted) release.complete();
        await fixture.dispose(tester);
        registries.dispose();
      }
    },
  );

  for (final detach in [false, true]) {
    testWidgets(
      'host waits for native volume acknowledgement; detached=$detach',
      (tester) async {
        final fixture = await _ReaderFixture.create(tester);
        var coreCloses = 0;
        final host = await _readerHost(() => coreCloses++);
        final cancellation = Completer<void>();
        final leases = <_VolumeLease>[];
        try {
          await fixture.mount(
            tester,
            pushed: false,
            withWindow: false,
            registry: host.selections,
            volumeConnect: (send) {
              final lease = _VolumeLease(
                send,
                release: () => cancellation.future,
              );
              leases.add(lease);
              return lease;
            },
          );
          expect(leases, hasLength(1));
          final reader = fixture.readerKey.currentState!;
          if (detach) await tester.pumpWidget(const SizedBox());
          var closed = false;
          final closing = host.close().then((_) => closed = true);
          leases.single.send(2);
          await tester.pump();
          expect(reader.page, 1);
          expect(coreCloses, 0);
          expect(closed, isFalse);
          expect(leases.single.closes, 1);
          cancellation.complete();
          await _pumpUntil(tester, () => closed);
          await closing;
          expect(coreCloses, 1);
          expect(fixture.notifications, 1);
          await host.close();
          expect(leases.single.closes, 1);
          expect(tester.takeException(), isNull);
        } finally {
          if (!cancellation.isCompleted) cancellation.complete();
          await fixture.dispose(tester);
          await host.sync.closeAndWait();
        }
      },
    );
  }

  testWidgets(
    'failed native release blocks host and retry does not replay reader saves',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      var coreCloses = 0;
      final host = await _readerHost(() => coreCloses++);
      final error = StateError('native volume release');
      var failing = true;
      final leases = <_VolumeLease>[];
      try {
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          registry: host.selections,
          volumeConnect: (send) {
            final lease = _VolumeLease(
              send,
              release: () async {
                if (failing) throw error;
              },
            );
            leases.add(lease);
            return lease;
          },
        );
        fixture.readerKey.currentState!.toPage(2, animated: false);
        Object? failure;
        final closing = host.close().catchError((Object e) {
          failure = e;
        });
        await _pumpUntil(tester, () => failure != null);
        await closing;
        expect(failure.toString(), contains('native volume release'));
        expect(coreCloses, 0);
        expect(leases.single.closes, 1);
        final progressWrites = fixture.history.progress.length;
        final durationWrites = fixture.history.durations.length;
        expect(fixture.notifications, 1);
        failing = false;
        var closed = false;
        final retry = host.close().then((_) => closed = true);
        await _pumpUntil(tester, () => closed);
        await retry;
        expect(coreCloses, 1);
        expect(leases.single.closes, 2);
        expect(fixture.history.progress, hasLength(progressWrites));
        expect(fixture.history.durations, hasLength(durationWrites));
        expect(fixture.notifications, 1);
        expect(tester.takeException(), isNull);
      } finally {
        failing = false;
        await fixture.dispose(tester);
        await host.sync.closeAndWait();
      }
    },
  );

  testWidgets(
    'covered and background readers release volume and reject retired input',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final leases = <_VolumeLease>[];
      try {
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          volumeConnect: (send) {
            final lease = _VolumeLease(send);
            leases.add(lease);
            return lease;
          },
        );
        final reader = fixture.readerKey.currentState!;
        expect(leases, hasLength(1));
        unawaited(
          appNavigation.rootNavigatorKey.currentState!.push<void>(
            MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('Cover reader')),
            ),
          ),
        );
        leases.first.send(2);
        expect(reader.page, 1);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(leases.first.closes, 1);
        leases.first.send(2);
        expect(reader.page, 1);
        appNavigation.rootNavigatorKey.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(leases, hasLength(2));
        reader.didChangeAppLifecycleState(AppLifecycleState.inactive);
        leases.last.send(2);
        await tester.pump();
        expect(leases.last.closes, 1);
        expect(reader.page, 1);
        reader.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await tester.pump();
        expect(leases, hasLength(3));
        leases.first.send(2);
        expect(reader.page, 1);
        leases.last.send(2);
        expect(reader.page, 2);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
  );

  testWidgets(
    'migrated reader keeps pending volume release in its original host',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final oldRegistry = SelectionTaskRegistry();
      final newRegistry = SelectionTaskRegistry();
      final registries = ValueNotifier(oldRegistry);
      final cancellation = Completer<void>();
      final leases = <_VolumeLease>[];
      try {
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          registries: registries,
          volumeConnect: (send) {
            final lease = _VolumeLease(
              send,
              release: () => cancellation.future,
            );
            leases.add(lease);
            return lease;
          },
        );
        registries.value = newRegistry;
        await tester.pump();
        var oldClosed = false;
        var newClosed = false;
        final oldClose = oldRegistry.closeAndWait().then(
          (_) => oldClosed = true,
        );
        final newClose = newRegistry.closeAndWait().then(
          (_) => newClosed = true,
        );
        await tester.pump();
        expect(oldClosed, isFalse);
        expect(newClosed, isTrue);
        expect(leases, hasLength(1));
        expect(leases.single.closes, 1);
        cancellation.complete();
        await _pumpUntil(tester, () => oldClosed);
        await Future.wait([oldClose, newClose]);
        expect(tester.takeException(), isNull);
      } finally {
        if (!cancellation.isCompleted) cancellation.complete();
        await fixture.dispose(tester);
        registries.dispose();
      }
    },
  );

  testWidgets(
    'window waits for volume release and restores input after another prepare failure',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final cancellation = Completer<void>();
      final leases = <_VolumeLease>[];
      var otherFailing = true;
      Future<void> otherPreparation() async {
        if (otherFailing) throw StateError('other prepare');
      }

      try {
        await fixture.mount(
          tester,
          pushed: false,
          beforeReaderMount: (frame) => frame.addExitTask(otherPreparation),
          volumeConnect: (send) {
            final lease = _VolumeLease(
              send,
              release: leases.isEmpty ? () => cancellation.future : null,
            );
            leases.add(lease);
            return lease;
          },
        );
        final reader = fixture.readerKey.currentState!;
        fixture.closeWindow(tester);
        await tester.pump();
        expect(fixture.exits, 0);
        leases.first.send(2);
        expect(reader.page, 1);
        cancellation.complete();
        await _pumpUntil(tester, () => leases.length == 2);
        expect(tester.takeException(), isA<StateError>());
        await tester.pump();
        expect(fixture.exits, 0);
        expect(reader.controller.isDisposed, isFalse);
        leases.last.send(2);
        expect(reader.page, 2);
        otherFailing = false;
        fixture.closeWindow(tester);
        await _pumpUntil(tester, () => fixture.exits == 1);
        expect(leases.last.closes, 1);
        expect(tester.takeException(), isNull);
      } finally {
        if (!cancellation.isCompleted) cancellation.complete();
        await fixture.dispose(tester);
      }
    },
  );

  for (final detach in [false, true]) {
    testWidgets('application owns no-window reader saves; detached=$detach', (
      tester,
    ) async {
      final fixture = await _ReaderFixture.create(tester);
      var coreCloses = 0;
      final host = await _readerHost(() => coreCloses++);
      final progress = Completer<void>();
      final duration = Completer<void>();
      final replacement = _ControlledHistory();
      try {
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          registry: host.selections,
        );
        final reader = fixture.readerKey.currentState!;
        fixture.history.onProgress = (_) => progress.future;
        fixture.history.onDuration = (_) => duration.future;
        reader.toPage(2, animated: false);
        reader.autoReading.start();
        // A later global manager must not receive this session's final writes.
        await _replaceHistory(tester, replacement);
        if (detach) await tester.pumpWidget(const SizedBox());
        var closed = false;
        final closing = host.close().then((_) => closed = true);
        expect(reader.controller.isDisposed, isTrue);
        expect(reader.toNextPage(), isFalse);
        expect(reader.imageWork.start(), isNull);
        await tester.pump();
        expect(coreCloses, 0);
        expect(closed, isFalse);
        expect(fixture.history.progress.last.page, 2);
        expect(fixture.history.durations, isNotEmpty);
        expect(replacement.progress, isEmpty);
        expect(replacement.durations, isEmpty);
        progress.complete();
        await tester.pump();
        expect(coreCloses, 0);
        duration.complete();
        await _pumpUntil(tester, () => closed);
        await closing;
        expect(coreCloses, 1);
        expect(fixture.notifications, 1);
        // Rebuild a still-mounted closed reader, including a new images host.
        if (!detach) {
          reader.mode = ReaderMode.continuousTopToBottom;
          tester.element(find.byType(_TestReader)).markNeedsBuild();
          await tester.pump();
          expect(reader.controller.isDisposed, isTrue);
        }
        await host.close();
        expect(fixture.notifications, 1);
        expect(tester.takeException(), isNull);
      } finally {
        if (!progress.isCompleted) progress.complete();
        if (!duration.isCompleted) duration.complete();
        await _replaceHistory(tester, fixture.history, images: fixture.images);
        await fixture.dispose(tester);
        await host.sync.closeAndWait();
      }
    });
  }

  for (final earlyFinalClose in [false, true]) {
    testWidgets(
      'window preparation and application share reader close; early final=$earlyFinalClose',
      (tester) async {
        final fixture = await _ReaderFixture.create(tester);
        var closes = 0;
        final host = await _readerHost(() => closes++);
        final saving = Completer<void>();
        try {
          await fixture.mount(
            tester,
            pushed: false,
            registry: host.selections,
            finalize: (drain) => host.close(drain: drain),
          );
          final reader = fixture.readerKey.currentState!;
          fixture.history.onProgress = (_) => saving.future;
          reader.toPage(2, animated: false);
          fixture.closeWindow(tester);
          await tester.pump();
          expect(closes, 0);
          expect(fixture.exits, 0);
          expect(reader.controller.isDisposed, isFalse);
          Future<void>? earlyClose;
          if (earlyFinalClose) {
            earlyClose = host.close();
            expect(reader.controller.isDisposed, isTrue);
            await tester.pump();
            expect(closes, 0);
          }
          saving.complete();
          await _pumpUntil(tester, () => fixture.exits == 1);
          await earlyClose;
          expect(closes, 1);
          expect(reader.controller.isDisposed, isTrue);
          expect(fixture.notifications, 1);
          expect(tester.takeException(), isNull);
        } finally {
          if (!saving.isCompleted) saving.complete();
          await fixture.dispose(tester);
          await host.sync.closeAndWait();
        }
      },
    );
  }

  testWidgets(
    'application waits for real reader setting persistence after removal',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      var closes = 0;
      final host = await _readerHost(() => closes++);
      final release = Completer<void>();
      Future<void>? exclusive;
      try {
        appdata.settings['readerBrightnessEnabled'] = true;
        appdata.settings['readerBrightness'] = 50;
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          registry: host.selections,
        );
        exclusive = AppDataOperations.instance.run(() => release.future);
        tester
            .widget<ReaderBrightnessControl>(
              find.byType(ReaderBrightnessControl),
            )
            .onBrightnessChanged(20);
        await tester.pump();
        expect(appdata.settings['readerBrightness'], 50);
        await tester.pumpWidget(const SizedBox());
        var closed = false;
        final closing = host.close().then((_) => closed = true);
        await tester.pump();
        expect(closes, 0);
        expect(closed, isFalse);
        release.complete();
        await _pumpUntil(tester, () => closed);
        await closing;
        expect(closes, 1);
        expect(appdata.settings['readerBrightness'], 20);
        final stored =
            jsonDecode(
                  File(
                    '${fixture.directory.path}/appdata.json',
                  ).readAsStringSync(),
                )
                as Map;
        expect((stored['settings'] as Map)['readerBrightness'], 20);
        expect(tester.takeException(), isNull);
      } finally {
        if (!release.isCompleted) release.complete();
        if (exclusive != null) await exclusive;
        await fixture.dispose(tester);
        await host.sync.closeAndWait();
      }
    },
  );

  testWidgets(
    'initial read-later write belongs to original host before child binding',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      var closes = 0;
      final host = await _readerHost(() => closes++);
      final reading = Completer<void>();
      final favorites = _favoritesOwner! as _Favorites;
      favorites.reading = reading.future;
      try {
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          registry: host.selections,
        );
        expect(favorites.reads, 1);
        await tester.pumpWidget(const SizedBox());
        var closed = false;
        final closing = host.close().then((_) => closed = true);
        await tester.pump();
        expect(closed, isFalse);
        expect(closes, 0);
        reading.complete();
        await _pumpUntil(tester, () => closed);
        await closing;
        expect(closes, 1);
        expect(favorites.reads, 1);
        expect(tester.takeException(), isNull);
      } finally {
        if (!reading.isCompleted) reading.complete();
        await fixture.dispose(tester);
        await host.sync.closeAndWait();
      }
    },
  );

  testWidgets(
    'host retries retain uncertain duration failure without replaying the period',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      var closes = 0;
      final host = await _readerHost(() => closes++);
      final cause = StateError('uncertain duration');
      final error = PersistenceFailure(
        stackTrace: StackTrace.current,
        cause: cause,
        commitState: PersistenceCommitState.unknown,
      );
      try {
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          registry: host.selections,
        );
        fixture.history.onDuration = (_) async => throw error;
        ApplicationCloseFailure? first;
        for (var attempt = 0; attempt < 2; attempt++) {
          ApplicationCloseFailure? failure;
          var settled = false;
          final closing = host
              .close()
              .catchError((Object error) {
                failure = error as ApplicationCloseFailure;
              })
              .whenComplete(() => settled = true);
          await _pumpUntil(tester, () => settled);
          await closing;
          expect(failure, isNotNull);
          if (first == null) {
            first = failure;
          } else {
            final firstSelection =
                first.failures.first.error as SelectionCleanupFailure;
            final nextSelection =
                failure!.failures.first.error as SelectionCleanupFailure;
            expect(
              (nextSelection.failures.single
                      as ({Object error, StackTrace stack}))
                  .error,
              same(
                (firstSelection.failures.single
                        as ({Object error, StackTrace stack}))
                    .error,
              ),
            );
          }
          expect(fixture.history.durations.length, 1);
          expect(closes, 0);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
        await host.sync.closeAndWait();
      }
    },
  );

  testWidgets(
    'closed application refuses a newly mounted reader before initialization work',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final registry = SelectionTaskRegistry();
      await registry.closeAndWait();
      try {
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          registry: registry,
          expectContent: false,
          volumeConnect: (_) =>
              throw StateError('closed host must not activate volume'),
        );
        final reader = fixture.readerKey.currentState!;
        expect(reader.controller.isDisposed, isTrue);
        expect(reader.images, isNull);
        expect(reader.imageWork.start(), isNull);
        expect((_favoritesOwner! as _Favorites).reads, 0);
        expect(fixture.history.progress, isEmpty);
        expect(fixture.history.durations, isEmpty);
        expect(fixture.notifications, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
  );

  testWidgets('reparented reader remains owned by its original application', (
    tester,
  ) async {
    final fixture = await _ReaderFixture.create(tester);
    final first = SelectionTaskRegistry();
    final second = SelectionTaskRegistry();
    final registries = ValueNotifier(first);
    final saving = Completer<void>();
    try {
      await fixture.mount(
        tester,
        pushed: false,
        withWindow: false,
        registries: registries,
      );
      final reader = fixture.readerKey.currentState!;
      fixture.history.onProgress = (_) => saving.future;
      reader.toPage(2, animated: false);
      registries.value = second;
      await tester.pump();
      expect(fixture.readerKey.currentState, same(reader));
      expect(reader.controller.isDisposed, isTrue);
      await second.closeAndWait();
      var closed = false;
      final closing = first.closeAndWait().then((_) => closed = true);
      await tester.pump();
      expect(closed, isFalse);
      saving.complete();
      await _pumpUntil(tester, () => closed);
      await closing;
      expect(fixture.notifications, 1);
      expect(tester.takeException(), isNull);
    } finally {
      if (!saving.isCompleted) saving.complete();
      await fixture.dispose(tester);
      registries.dispose();
    }
  });

  testWidgets(
    'consumed reader image failure still blocks original core close',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      var closes = 0;
      final host = await _readerHost(() => closes++);
      final error = StateError('late reader image cleanup');
      final stack = StackTrace.fromString('original reader task stack');
      try {
        await fixture.mount(
          tester,
          pushed: false,
          withWindow: false,
          registry: host.selections,
        );
        final reader = fixture.readerKey.currentState!;
        final task = reader.imageWork.start()!;
        task.recordFailure(error, stack);
        task.finish();
        final reported = expectLater(
          reader.imageWork.prepareForExit(),
          throwsA(isA<ImageWorkFailure>()),
        );
        await tester.pump();
        await reported;
        await tester.pumpWidget(const SizedBox());
        for (var attempt = 0; attempt < 2; attempt++) {
          ApplicationCloseFailure? failure;
          var settled = false;
          final closing = host
              .close()
              .catchError((Object error) {
                failure = error as ApplicationCloseFailure;
              })
              .whenComplete(() => settled = true);
          await _pumpUntil(tester, () => settled);
          await closing;
          final selection =
              failure!.failures
                      .firstWhere((item) => item.owner == 'selection tasks')
                      .error
                  as SelectionCleanupFailure;
          final original =
              selection.failures
                      .whereType<({Object error, StackTrace stack})>()
                      .where((entry) => entry.error is ImageWorkFailure)
                      .single
                      .error
                  as ImageWorkFailure;
          expect(original.failures, [(error: error, stack: stack)]);
          expect(closes, 0);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
        await host.sync.closeAndWait();
      }
    },
  );

  for (final detach in [false, true]) {
    testWidgets(
      'real reader dimming previews while saving and blocks ${detach ? 'window after removal' : 'back'}',
      (tester) async {
        final fixture = await _ReaderFixture.create(tester);
        final release = Completer<void>();
        Future<void>? exclusive;
        try {
          appdata.settings['readerBrightnessEnabled'] = true;
          appdata.settings['readerBrightness'] = 50;
          appdata.settings['disableSyncFields'] = '';
          await fixture.mount(tester, pushed: true);
          final reader = fixture.readerKey.currentState!;
          exclusive = AppDataOperations.instance.run(() => release.future);
          tester
              .widget<ReaderBrightnessControl>(
                find.byType(ReaderBrightnessControl),
              )
              .onBrightnessChanged(20);
          await tester.pump();
          expect(appdata.settings['readerBrightness'], 50);
          expect(
            tester
                .widget<ReaderBrightnessOverlay>(
                  find.byType(ReaderBrightnessOverlay),
                )
                .brightness,
            20,
          );
          if (detach) {
            appNavigation.rootNavigatorKey.currentState!.pop();
            await tester.pumpAndSettle();
            expect(fixture.readerKey.currentState, isNull);
            fixture.closeWindow(tester);
          } else {
            await appNavigation.rootNavigatorKey.currentState!.maybePop();
          }
          await tester.pump();
          expect(fixture.exits, 0);
          if (!detach) expect(fixture.readerKey.currentState, same(reader));
          release.complete();
          var saved = false;
          final saving = Future.wait([
            exclusive,
            appdata.saveData(false),
          ]).then((_) => saved = true);
          await _pumpUntil(tester, () => saved);
          await saving;
          await tester.pumpAndSettle();
          expect(appdata.settings['readerBrightness'], 20);
          expect(fixture.readerKey.currentState, isNull);
          expect(fixture.exits, detach ? 1 : 0);
          expect(tester.takeException(), isNull);
        } finally {
          if (!release.isCompleted) release.complete();
          if (exclusive != null) {
            var drained = false;
            final draining = Future.wait([
              exclusive,
              appdata.saveData(false),
            ]).then((_) => drained = true);
            await _pumpUntil(tester, () => drained);
            await draining;
          }
          await fixture.dispose(tester);
        }
      },
      skip: !Platform.isWindows,
    );
  }

  for (final detach in [false, true]) {
    testWidgets(
      'favorite write blocks ${detach ? 'window after forced unmount' : 'reader back'} until real completion',
      (tester) async {
        final fixture = await _ReaderFixture.create(tester);
        final pending = Completer<void>();
        final favorites = _favoritesOwner! as _Favorites;
        favorites.reading = pending.future;
        try {
          await fixture.mount(tester, pushed: true);
          expect(favorites.reads, 1);
          if (detach) {
            appNavigation.rootNavigatorKey.currentState!.pop();
            await tester.pumpAndSettle();
            fixture.closeWindow(tester);
            await tester.pump();
            expect(fixture.exits, 0);
          } else {
            unawaited(appNavigation.rootNavigatorKey.currentState!.maybePop());
            await tester.pump(const Duration(milliseconds: 400));
            expect(fixture.readerKey.currentState, isNotNull);
          }
          pending.complete();
          await _pumpUntil(
            tester,
            () => detach
                ? fixture.exits == 1
                : fixture.readerKey.currentState == null,
          );
          expect(tester.takeException(), isNull);
        } finally {
          if (!pending.isCompleted) pending.complete();
          await fixture.dispose(tester);
        }
      },
    );
  }

  for (final nativeFrame in [false, true]) {
    for (final detachReader in [false, true]) {
      testWidgets(
        'visible PhotoView ${nativeFrame ? 'native frame' : 'file read'} blocks ${detachReader ? 'window exit after forced unmount' : 'reader back'}',
        (tester) async {
          final fixture = await _ReaderFixture.create(tester);
          final native = _NativeFrameGate();
          final read = _LocalReadGate(
            File('${LocalManager().path}/book/one/1.png'),
          );
          final previousIO = IOOverrides.current;
          try {
            appdata.settings['preloadImageCount'] = 0;
            if (nativeFrame) {
              binding.nativeGate = native;
            } else {
              IOOverrides.global = read;
            }
            await fixture.mount(tester, pushed: true, waitForImage: false);
            await _pumpUntil(
              tester,
              () => nativeFrame ? native.pendingFrames > 0 : read.reads > 0,
            );
            final reader = fixture.readerKey.currentState!;
            final originalWork = reader.imageWork;
            final gallery = tester.widget<ReaderGalleryView>(
              find.byType(ReaderGalleryView),
            );
            expect(gallery.imageWork, same(originalWork));
            final photoFinder = find.byWidgetPredicate(
              (widget) =>
                  widget is PhotoView &&
                  widget.imageProvider is ReaderDisplayImageProvider,
            );
            expect(photoFinder, findsWidgets);
            final photo = tester.widget<PhotoView>(photoFinder.first);
            expect(
              (photo.imageProvider! as ReaderDisplayImageProvider).work,
              same(originalWork),
            );
            final photoElement = tester.element(photoFinder.first);
            expect(_paintedImages(photoFinder.first), findsNothing);

            if (detachReader) {
              appNavigation.rootNavigatorKey.currentState!.removeRoute(
                ModalRoute.of(reader.context)!,
              );
              await tester.pumpAndSettle();
              expect(reader.mounted, isFalse);
              expect(photoElement.mounted, isFalse);
              fixture.closeWindow(tester);
            } else {
              unawaited(reader.requestExit());
            }
            await tester.pump(const Duration(seconds: 3));
            expect(originalWork.start(), isNull);
            expect(fixture.notifications, 0);
            expect(fixture.exits, 0);
            if (!detachReader) {
              expect(fixture.readerKey.currentState, same(reader));
              expect(tester.element(photoFinder.first), same(photoElement));
              expect(find.text('Saving...'), findsOneWidget);
              expect(_paintedImages(photoFinder.first), findsNothing);
            }
            if (nativeFrame) {
              expect(native.codecs, isNotEmpty);
              expect(
                native.codecs.every((codec) => codec.disposals == 0),
                isTrue,
              );
              expect(
                native.frames.every((frame) => !frame.image.debugDisposed),
                isTrue,
              );
            } else {
              expect(read.reads, 1);
              expect(read.completedReads, 0);
            }

            native.release();
            read.release();
            await _pumpUntil(tester, () => fixture.notifications > 0);
            await tester.pumpAndSettle();
            expect(fixture.readerKey.currentState, isNull);
            expect(find.text('Library home'), findsOneWidget);
            expect(fixture.exits, detachReader ? 1 : 0);
            expect(reader.imageWork, same(originalWork));
            if (nativeFrame) {
              expect(native.frames, isNotEmpty);
              expect(
                native.frames.every((frame) => frame.image.debugDisposed),
                isTrue,
              );
              expect(
                native.codecs.every((codec) => codec.disposals == 1),
                isTrue,
              );
            } else {
              expect(read.completedReads, 1);
            }
            expect(tester.takeException(), isNull);
          } finally {
            native.release();
            read.release();
            binding.nativeGate = null;
            IOOverrides.global = previousIO;
            await fixture.dispose(tester);
            binding.imageCache.clear();
            binding.imageCache.clearLiveImages();
            await tester.pump();
          }
        },
        skip: !Platform.isWindows,
      );
    }
  }

  for (final continuous in [false, true]) {
    testWidgets(
      'mounted ${continuous ? 'continuous ComicImage' : 'single PhotoView'} resumes after later window exit failure',
      (tester) async {
        final fixture = await _ReaderFixture.create(tester);
        final native = _NativeFrameGate();
        final laterService = Completer<void>();
        var laterCalls = 0;
        try {
          appdata.settings['preloadImageCount'] = 0;
          if (continuous) {
            appdata.settings['readerMode'] =
                ReaderMode.continuousTopToBottom.key;
          }
          binding.nativeGate = native;
          await fixture.mount(
            tester,
            pushed: false,
            waitForImage: false,
            beforeReaderMount: (frame) => frame.addExitTask(() async {
              if (++laterCalls == 1) await laterService.future;
            }),
          );
          await _pumpUntil(tester, () => native.pendingFrames > 0);
          final reader = fixture.readerKey.currentState!;
          final originalWork = reader.imageWork;
          final consumerFinder = continuous
              ? find.byType(ComicImage).first
              : find
                    .byWidgetPredicate(
                      (widget) =>
                          widget is PhotoView &&
                          widget.imageProvider is ReaderDisplayImageProvider,
                    )
                    .first;
          final consumer = tester.element(consumerFinder);
          final provider = continuous
              ? tester.widget<ComicImage>(consumerFinder).image
              : tester.widget<PhotoView>(consumerFinder).imageProvider!;
          expect(
            (provider as ReaderDisplayImageProvider).work,
            same(originalWork),
          );
          if (continuous) {
            expect(
              tester
                  .widget<ReaderContinuousView>(
                    find.byType(ReaderContinuousView),
                  )
                  .imageWork,
              same(originalWork),
            );
          } else {
            expect(
              tester
                  .widget<ReaderGalleryView>(find.byType(ReaderGalleryView))
                  .imageWork,
              same(originalWork),
            );
          }
          expect(_paintedImages(consumerFinder), findsNothing);
          fixture.closeWindow(tester);
          await tester.pump(const Duration(seconds: 3));
          expect(laterCalls, 0);
          expect(fixture.notifications, 0);
          expect(fixture.exits, 0);
          expect(originalWork.start(), isNull);
          expect(tester.element(consumerFinder), same(consumer));

          // The original native request must drain before the later service.
          // No new request may start until that service's failure releases hold.
          binding.nativeGate = null;
          native.release();
          await _pumpUntil(tester, () => laterCalls == 1);
          expect(native.frames, isNotEmpty);
          expect(
            native.frames.every((frame) => frame.image.debugDisposed),
            isTrue,
          );
          expect(native.codecs.every((codec) => codec.disposals == 1), isTrue);
          expect(_paintedImages(consumerFinder), findsNothing);
          expect(tester.element(consumerFinder), same(consumer));
          expect(originalWork.start(), isNull);
          laterService.completeError(
            StateError('later visible reader failure'),
          );
          await tester.pump();
          expect(tester.takeException(), isA<StateError>());
          await _pumpUntil(
            tester,
            () => _paintedImages(consumerFinder).evaluate().isNotEmpty,
          );
          expect(fixture.readerKey.currentState, same(reader));
          expect(tester.element(consumerFinder), same(consumer));
          expect(reader.imageWork, same(originalWork));
          expect(fixture.exits, 0);
          expect(find.text('Closing...'), findsNothing);
          expect(_paintedImages(consumerFinder), findsWidgets);
          fixture.closeWindow(tester);
          await tester.pumpAndSettle();
          expect(laterCalls, 2);
          expect(fixture.exits, 1);
          expect(tester.takeException(), isNull);
        } finally {
          binding.nativeGate = null;
          native.release();
          if (!laterService.isCompleted) laterService.complete();
          await fixture.dispose(tester);
          binding.imageCache.clear();
          binding.imageCache.clearLiveImages();
          await tester.pump();
        }
      },
      skip: !Platform.isWindows,
    );
  }

  for (final detachReader in [false, true]) {
    testWidgets(
      'prefetch cleanup blocks ${detachReader ? 'window exit after forced unmount' : 'reader back'}',
      (tester) async {
        final fixture = await _ReaderFixture.create(tester);
        final release = Completer<void>();
        var cancelled = false;
        final source = StreamController<ImageDownloadProgress>(
          onCancel: () {
            cancelled = true;
            return release.future;
          },
        );
        ReaderImageDownloads? downloads;
        try {
          await fixture.mount(tester, pushed: true);
          final reader = fixture.readerKey.currentState!;
          expect(
            tester
                .widget<ReaderGalleryView>(find.byType(ReaderGalleryView))
                .imageWork,
            same(reader.imageWork),
          );
          downloads = ReaderImageDownloads(
            work: reader.imageWork,
            loader: (_, _, _, _) => source.stream,
          );
          downloads.preload('owned-prefetch', null, 'book', 'one');
          await tester.pump();
          if (detachReader) {
            appNavigation.rootNavigatorKey.currentState!.removeRoute(
              ModalRoute.of(reader.context)!,
            );
            await tester.pumpAndSettle();
            expect(reader.mounted, isFalse);
            fixture.closeWindow(tester);
          } else {
            unawaited(reader.requestExit());
          }
          await tester.pump(const Duration(seconds: 3));
          expect(cancelled, isTrue);
          expect(fixture.notifications, 0);
          expect(fixture.exits, 0);
          if (!detachReader) {
            expect(fixture.readerKey.currentState, same(reader));
          }
          release.complete();
          await tester.pumpAndSettle();
          expect(fixture.notifications, greaterThan(0));
          expect(fixture.exits, detachReader ? 1 : 0);
          expect(find.text('Library home'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          if (!release.isCompleted) release.complete();
          final disposing = downloads?.dispose();
          await tester.pump();
          // Drain controller futures outside fake async before the next widget
          // pump. A controller never listened to has no close event to await.
          await tester.runAsync(() async {
            await disposing;
            if (cancelled) {
              await source.close();
            } else {
              unawaited(source.close());
            }
          });
          await fixture.dispose(tester);
        }
      },
      skip: !Platform.isWindows,
    );
  }

  testWidgets(
    'reader back joins layout cleanup after its cancelled result has returned',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final probe = _LayoutProbeGate();
      try {
        await fixture.mount(tester, pushed: true);
        final reader = fixture.readerKey.currentState!;
        reader.layoutProbe = probe;
        final originalLayout = appdata.settings.comicLayout('book', 'local');
        final originalMode = reader.mode;
        var resultReturned = false;
        final detecting = reader
            .detectLayout(force: true)
            .then((_) => resultReturned = true);
        expect(probe.started, isTrue);

        // Model the probe's bounded presentation result. Its real worker and
        // cancellation lifetime remains pending after this result returns.
        probe.cancel();
        await tester.pump();
        expect(resultReturned, isTrue);
        expect(reader.isDetectingLayout, isFalse);
        expect(reader.settingsSaves, 0);
        unawaited(reader.requestExit());
        await tester.pump(const Duration(seconds: 3));
        expect(fixture.readerKey.currentState, same(reader));
        expect(find.text('Saving...'), findsOneWidget);
        expect(fixture.notifications, 0);
        expect(fixture.exits, 0);
        expect(reader.mode, originalMode);
        expect(appdata.settings.comicLayout('book', 'local'), originalLayout);

        probe.finish();
        await tester.pumpAndSettle();
        await detecting;
        expect(fixture.readerKey.currentState, isNull);
        expect(find.text('Library home'), findsOneWidget);
        expect(fixture.notifications, greaterThan(0));
        expect(fixture.exits, 0);
        expect(reader.settingsSaves, 0);
        expect(tester.takeException(), isNull);
      } finally {
        probe.finish();
        await tester.pump();
        await fixture.dispose(tester);
      }
    },
    skip: !Platform.isWindows,
  );

  for (final detachReader in [false, true]) {
    testWidgets(
      'window waits for layout settings save ${detachReader ? 'handed off by an unmounted reader' : 'in its root reader'}',
      (tester) async {
        final fixture = await _ReaderFixture.create(tester);
        final probe = _LayoutProbeGate();
        final saving = Completer<void>();
        try {
          await fixture.mount(tester, pushed: detachReader);
          final reader = fixture.readerKey.currentState!;
          reader.layoutProbe = probe;
          reader.onSaveSettings = () => saving.future;
          appdata.settings['autoReaderMode'] = true;
          appdata.settings['longStripReaderMode'] =
              ReaderMode.continuousTopToBottom.key;
          final originalMode = reader.mode;
          var resultReturned = false;
          final detecting = reader
              .detectLayout(force: true)
              .then((_) => resultReturned = true);
          probe.finish(ComicLayout.longStrip);
          await tester.pump();
          expect(reader.settingsSaves, 1);
          expect(resultReturned, isFalse);
          expect(reader.mode, originalMode);

          if (detachReader) {
            appNavigation.rootNavigatorKey.currentState!.removeRoute(
              ModalRoute.of(reader.context)!,
            );
            await tester.pumpAndSettle();
            expect(fixture.readerKey.currentState, isNull);
            expect(reader.mounted, isFalse);
          }
          fixture.closeWindow(tester);
          await tester.pump(const Duration(seconds: 3));
          expect(resultReturned, isTrue);
          expect(reader.imageWork.start(), isNull);
          expect(fixture.notifications, 0);
          expect(fixture.exits, 0);
          expect(find.text('Closing...'), findsOneWidget);
          if (detachReader) {
            expect(find.text('Library home'), findsOneWidget);
          } else {
            expect(fixture.readerKey.currentState, same(reader));
          }

          saving.complete();
          await tester.pumpAndSettle();
          await detecting;
          expect(fixture.notifications, 1);
          expect(fixture.exits, 1);
          expect(reader.settingsSaves, 1);
          expect(reader.mode, originalMode);
          expect(find.textContaining('Switched to'), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          probe.finish();
          if (!saving.isCompleted) saving.complete();
          await tester.pump();
          await fixture.dispose(tester);
        }
      },
      skip: !Platform.isWindows,
    );
  }

  for (final windowClose in [false, true]) {
    testWidgets(
      'reader ${windowClose ? 'window close' : 'back'} waits for a cancelled original image read',
      (tester) async {
        final fixture = await _ReaderFixture.create(tester);
        final rawRead = Completer<Uint8List>();
        ReaderImageExporter? exporter;
        try {
          await fixture.mount(tester, pushed: true);
          final reader = fixture.readerKey.currentState!;
          var reads = 0;
          var delivered = 0;
          final errors = <Object>[];
          exporter = _exporter(
            reader,
            read: (_) {
              reads++;
              return rawRead.future;
            },
            save: (_) => delivered++,
            onError: (error, _) => errors.add(error),
          );
          final exporting = exporter.export(sharing: false);
          await tester.pump();
          expect(reads, 1);

          if (windowClose) {
            fixture.closeWindow(tester);
          } else {
            unawaited(reader.requestExit());
          }
          expect(reader.imageWork.start(), isNull);
          await tester.pump(const Duration(seconds: 3));
          expect(fixture.readerKey.currentState, same(reader));
          expect(find.text('Saving...'), findsOneWidget);
          expect(fixture.notifications, 0);
          expect(fixture.exits, 0);
          expect(delivered, 0);

          rawRead.complete(Uint8List.fromList([1, 2, 3]));
          await tester.pumpAndSettle();
          await exporting;
          expect(fixture.readerKey.currentState, isNull);
          expect(find.text('Library home'), findsOneWidget);
          expect(delivered, 0);
          expect(errors, isEmpty);
          // Route teardown can submit another progress revision after prepare.
          expect(fixture.notifications, greaterThan(0));
          expect(fixture.exits, 0);
          expect(tester.takeException(), isNull);
        } finally {
          if (!rawRead.isCompleted) rawRead.complete(Uint8List(0));
          await tester.pump();
          await exporter?.dispose();
          await fixture.dispose(tester);
        }
      },
      skip: !Platform.isWindows,
    );
  }

  testWidgets(
    'root reader waits for platform delivery and admits new exports after later exit failure',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final platform = Completer<void>();
      ReaderImageExporter? exporter;
      var laterCalls = 0;
      try {
        await fixture.mount(
          tester,
          pushed: false,
          beforeReaderMount: (frame) => frame.addExitTask(() async {
            if (++laterCalls == 1) throw StateError('later service failure');
          }),
        );
        final reader = fixture.readerKey.currentState!;
        var deliveries = 0;
        final errors = <Object>[];
        exporter = _exporter(
          reader,
          save: (_) async {
            if (++deliveries == 1) await platform.future;
          },
          onError: (error, _) => errors.add(error),
        );
        final exporting = exporter.export(sharing: false);
        await tester.pump();
        expect(deliveries, 1);
        fixture.closeWindow(tester);
        expect(reader.imageWork.start(), isNull);
        await tester.pump(const Duration(seconds: 3));
        expect(laterCalls, 0);
        expect(fixture.notifications, 0);
        expect(fixture.exits, 0);
        expect(fixture.readerKey.currentState, same(reader));

        platform.complete();
        await tester.pump();
        await exporting;
        expect(tester.takeException(), isA<StateError>());
        expect(laterCalls, 1);
        expect(fixture.exits, 0);
        expect(fixture.readerKey.currentState, same(reader));
        final admitted = reader.imageWork.start();
        expect(admitted, isNotNull);
        admitted!.finish();

        final retry = exporter.export(sharing: false);
        await tester.pump();
        await retry;
        expect(deliveries, 2);
        expect(errors, isEmpty);
        fixture.closeWindow(tester);
        await tester.pumpAndSettle();
        expect(laterCalls, 2);
        expect(fixture.exits, 1);
        expect(tester.takeException(), isNull);
      } finally {
        if (!platform.isCompleted) platform.complete();
        await tester.pump();
        await exporter?.dispose();
        await fixture.dispose(tester);
      }
    },
    skip: !Platform.isWindows,
  );

  testWidgets(
    'disposed reader retains pending platform delivery until final host exit',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final platform = Completer<void>();
      ReaderImageExporter? exporter;
      try {
        await fixture.mount(tester, pushed: true);
        final reader = fixture.readerKey.currentState!;
        var deliveries = 0;
        exporter = _exporter(
          reader,
          save: (_) {
            deliveries++;
            return platform.future;
          },
        );
        final exporting = exporter.export(sharing: false);
        await tester.pump();
        expect(deliveries, 1);

        appNavigation.rootNavigatorKey.currentState!.removeRoute(
          ModalRoute.of(reader.context)!,
        );
        await tester.pumpAndSettle();
        expect(fixture.readerKey.currentState, isNull);
        expect(reader.mounted, isFalse);
        expect(reader.imageWork.start(), isNull);
        fixture.closeWindow(tester);
        await tester.pump(const Duration(seconds: 3));
        expect(find.text('Library home'), findsOneWidget);
        expect(fixture.notifications, 0);
        expect(fixture.exits, 0);

        platform.complete();
        await tester.pumpAndSettle();
        await exporting;
        expect(fixture.notifications, 1);
        expect(fixture.exits, 1);
        expect(tester.takeException(), isNull);
      } finally {
        if (!platform.isCompleted) platform.complete();
        await tester.pump();
        await exporter?.dispose();
        await fixture.dispose(tester);
      }
    },
    skip: !Platform.isWindows,
  );

  testWidgets(
    'reader toolbar retains a failed save, then saves newer progress before pop',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      try {
        await fixture.mount(tester, pushed: true);
        final reader = fixture.readerKey.currentState!;
        final saving = Completer<void>();
        fixture.history.onProgress = (_) => saving.future;
        reader.setPage(2);
        tester
            .state<ReaderScaffoldState>(find.byType(ReaderScaffold))
            .openOrClose();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.byType(BackButton));
        await tester.pump();
        expect(find.text('Saving...'), findsOneWidget);
        expect(fixture.readerKey.currentState, same(reader));
        expect(appNavigation.rootNavigatorKey.currentState!.canPop(), isTrue);
        expect(fixture.history.progress.last.page, 2);
        saving.completeError(StateError('progress disk failure'));
        await tester.pumpAndSettle();
        expect(fixture.readerKey.currentState, same(reader));
        expect(find.text('Saving...'), findsNothing);
        expect(find.text('Unable to close. Please try again.'), findsOneWidget);

        fixture.history.onProgress = null;
        reader.setPage(3);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(fixture.readerKey.currentState, isNull);
        expect(find.text('Library home'), findsOneWidget);
        expect(fixture.history.progress.last.page, 3);
        expect(fixture.exits, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    skip: !Platform.isWindows,
  );

  testWidgets(
    'native window close waits for the current reader save before leaving its route',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      try {
        await fixture.mount(tester, pushed: true);
        final reader = fixture.readerKey.currentState!;
        final saving = Completer<void>();
        fixture.history.onProgress = (_) => saving.future;
        reader.setPage(2);
        fixture.closeWindow(tester);
        fixture.closeWindow(tester);
        await tester.pump();
        expect(find.text('Saving...'), findsOneWidget);
        expect(find.text('Closing...'), findsNothing);
        expect(fixture.readerKey.currentState, same(reader));
        expect(fixture.exits, 0);
        final acceptedWrites = fixture.history.progress.length;
        await tester.pump(const Duration(seconds: 3));
        expect(fixture.history.progress.length, acceptedWrites);
        expect(fixture.readerKey.currentState, same(reader));
        saving.complete();
        await tester.pumpAndSettle();
        expect(fixture.readerKey.currentState, isNull);
        expect(find.text('Library home'), findsOneWidget);
        expect(fixture.history.progress.last.page, 2);
        expect(fixture.exits, 0);
        fixture.closeWindow(tester);
        await tester.pumpAndSettle();
        expect(fixture.exits, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    skip: !Platform.isWindows,
  );

  testWidgets(
    'reader offers explicit leave after an uncertain duration save without replaying it',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      try {
        await fixture.mount(tester, pushed: true);
        final reader = fixture.readerKey.currentState!;
        var failedAttempts = 0;
        Duration? uncertainDuration;
        fixture.history.onDuration = (duration) async {
          uncertainDuration ??= duration;
          if (identical(duration, uncertainDuration)) {
            failedAttempts++;
            throw StateError('duration result is unknown');
          }
        };
        final exiting = reader.requestExit();
        await tester.pumpAndSettle();
        await exiting;
        expect(fixture.readerKey.currentState, same(reader));
        expect(find.text('Leave without saving'), findsOneWidget);
        expect(failedAttempts, 1);
        // Further reading can be persisted, but the uncertain earlier segment
        // remains observable and must never be replayed during final disposal.
        await tester.tap(find.text('Leave without saving'));
        await tester.pumpAndSettle();
        expect(fixture.readerKey.currentState, isNull);
        expect(find.text('Library home'), findsOneWidget);
        expect(failedAttempts, 1);
        expect(tester.takeException(), isA<ReaderSessionFailure>());
        expect(fixture.exits, 0);
      } finally {
        await fixture.dispose(tester);
      }
    },
    skip: !Platform.isWindows,
  );

  testWidgets(
    'root reader freezes before old saves drain and resumes after a later exit failure',
    (tester) async {
      final fixture = await _ReaderFixture.create(tester);
      final oldSave = Completer<void>();
      var laterCalls = 0;
      try {
        await fixture.mount(
          tester,
          pushed: false,
          beforeReaderMount: (frame) => frame.addExitTask(() async {
            laterCalls++;
            if (laterCalls == 1) throw StateError('later service failure');
          }),
        );
        final reader = fixture.readerKey.currentState!;
        expect(appNavigation.rootNavigatorKey.currentState!.canPop(), isFalse);
        reader.setPage(2);
        reader.autoReading.start();
        final progressRequest = reader.createProgressRequest();
        final durationWrites = fixture.history.durations.length;
        fixture.frame.trackExitTask(oldSave.future);
        fixture.closeWindow(tester);
        // The real session receives the synchronous window notification even
        // though a previously detached owner's save blocks its exit task.
        expect(reader.autoReading.status, AutoReadingStatus.paused);
        expect(progressRequest.selectPage(3), isFalse);
        expect(progressRequest.next(), isFalse);
        expect(reader.toggleAutomaticReading(), isFalse);
        expect(reader.readImagePickContext(), isNull);
        await tester.pump();
        expect(fixture.history.durations.length, durationWrites + 1);
        expect(laterCalls, 0);
        expect(fixture.notifications, 0);
        await tester.pump(const Duration(minutes: 3));
        expect(fixture.history.durations.length, durationWrites + 1);
        expect(reader.page, 2);
        expect(fixture.exits, 0);

        oldSave.complete();
        await tester.pump();
        expect(tester.takeException(), isA<StateError>());
        expect(laterCalls, 1);
        expect(fixture.notifications, 1);
        expect(fixture.history.progress.last.page, 2);
        expect(fixture.readerKey.currentState, same(reader));
        expect(
          reader.autoReading.status,
          isIn([AutoReadingStatus.running, AutoReadingStatus.waiting]),
        );
        expect(find.text('Closing...'), findsNothing);

        reader.autoReading.stop();
        expect(progressRequest.selectPage(3), isTrue);
        fixture.closeWindow(tester);
        // The fixture records a native exit without removing its root reader.
        // A newly visited page can keep its loading animation mounted.
        await _pumpUntil(tester, () => fixture.exits == 1);
        expect(fixture.history.progress.last.page, 3);
        expect(fixture.notifications, 2);
        expect(laterCalls, 2);
        expect(fixture.exits, 1);
        expect(tester.takeException(), isNull);
      } finally {
        if (!oldSave.isCompleted) oldSave.complete();
        await fixture.dispose(tester);
      }
    },
    skip: !Platform.isWindows,
  );

  for (final failLateSave in [false, true]) {
    testWidgets(
      'root reader drains progress arriving after its exit task; late failure=$failLateSave',
      (tester) async {
        final fixture = await _ReaderFixture.create(tester);
        final laterService = Completer<void>();
        final firstLateSave = Completer<void>();
        final lastLateSave = Completer<void>();
        var laterCalls = 0;
        try {
          await fixture.mount(
            tester,
            pushed: false,
            beforeReaderMount: (frame) => frame.addExitTask(() {
              laterCalls++;
              return laterService.future;
            }),
          );
          final reader = fixture.readerKey.currentState!;
          reader.autoReading.start();
          fixture.closeWindow(tester);
          await tester.pump();
          expect(laterCalls, 1);
          expect(fixture.notifications, 1);
          expect(reader.autoReading.status, AutoReadingStatus.paused);
          fixture.history.onProgress = (snapshot) => switch (snapshot.page) {
            2 => firstLateSave.future,
            3 => lastLateSave.future,
            _ => Future.value(),
          };

          // A completed reader preparation must acquire another hold and
          // immediately drain this late snapshot while another owner waits.
          reader.setPage(2);
          await tester.pump();
          expect(fixture.history.progress.last.page, 2);
          expect(fixture.notifications, 1);
          expect(fixture.exits, 0);
          firstLateSave.complete();
          await tester.pump();
          expect(fixture.notifications, 2);
          expect(reader.autoReading.status, AutoReadingStatus.paused);

          // Keep both successful preparation holds alive while a third drain
          // is pending; recovery must release every one of them on failure.
          reader.setPage(3);
          await tester.pump();
          expect(fixture.history.progress.last.page, 3);
          laterService.complete();
          await tester.pump(const Duration(seconds: 3));
          expect(laterCalls, 1);
          expect(fixture.exits, 0);
          expect(reader.autoReading.status, AutoReadingStatus.paused);
          expect(find.text('Closing...'), findsOneWidget);
          expect(tester.takeException(), isNull);

          if (failLateSave) {
            lastLateSave.completeError(StateError('late progress failure'));
          } else {
            lastLateSave.complete();
          }
          await tester.pump();
          expect(fixture.notifications, 3);
          if (failLateSave) {
            expect(tester.takeException(), isA<ReaderSessionFailure>());
            expect(fixture.exits, 0);
            expect(fixture.readerKey.currentState, same(reader));
            expect(find.text('Closing...'), findsNothing);
            expect(
              reader.autoReading.status,
              isIn([AutoReadingStatus.running, AutoReadingStatus.waiting]),
            );
            reader.autoReading.stop();
            fixture.history.onProgress = null;
            reader.setPage(1);
            fixture.closeWindow(tester);
            // This fixture records exit without removing the root reader. A
            // fresh page can retain a loading indicator after image admission
            // closes, so wait for shutdown itself instead of all animations.
            await _pumpUntil(tester, () => fixture.exits == 1);
            expect(fixture.history.progress.last.page, 1);
            expect(laterCalls, 2);
            expect(fixture.exits, 1);
          } else {
            expect(fixture.exits, 1);
          }
          expect(tester.takeException(), isNull);
        } finally {
          if (!laterService.isCompleted) laterService.complete();
          if (!firstLateSave.isCompleted) firstLateSave.complete();
          if (!lastLateSave.isCompleted) lastLateSave.complete();
          await fixture.dispose(tester);
        }
      },
      skip: !Platform.isWindows,
    );
  }
}

const _chapters = ComicChapters({'one': 'One'});

History _resumeHistory({
  int chapter = 1,
  int page = 1,
  int? group,
  int maxPage = 3,
}) => History.fromMap({
  'id': 'book',
  'type': 0,
  'time': 1000,
  'title': 'Book',
  'subtitle': '',
  'cover': '',
  'ep': chapter,
  'page': page,
  'max_page': maxPage,
  'chapter_group': group,
});

Finder _paintedImages(Finder consumer) => find.descendant(
  of: consumer,
  matching: find.byWidgetPredicate(
    (widget) => widget is RawImage && widget.image != null,
  ),
);

Future<void> _pumpUntil(WidgetTester tester, bool Function() finished) async {
  for (var attempt = 0; attempt < 100 && !finished(); attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(finished(), isTrue, reason: 'Reader work did not reach its gate');
}

bool _annotationImagesReady(ReaderState reader) {
  final viewport = reader.imageViewController;
  return !reader.isLoading &&
      viewport is AutoReadingViewport &&
      (viewport as AutoReadingViewport).autoReadingReady;
}

/// Flutter's decoder remains real; only completion of its native frame future
/// is controlled. No reader, host, provider, stream or image-work wiring is
/// replaced, and tests without a gate use the normal binding unchanged.
class _ReaderExitBinding extends AutomatedTestWidgetsFlutterBinding {
  _NativeFrameGate? nativeGate;

  @override
  Future<ui.Codec> instantiateImageCodecWithSize(
    ui.ImmutableBuffer buffer, {
    ui.TargetImageSizeCallback? getTargetSize,
  }) async {
    final gate = nativeGate;
    final codec = await super.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: getTargetSize,
    );
    return gate?.wrap(codec) ?? codec;
  }
}

class _NativeFrameGate {
  final _released = Completer<void>();
  final codecs = <_GatedNativeCodec>[];
  final frames = <ui.FrameInfo>[];
  int pendingFrames = 0;

  ui.Codec wrap(ui.Codec codec) {
    final owned = _GatedNativeCodec(codec, this);
    codecs.add(owned);
    return owned;
  }

  void release() {
    if (!_released.isCompleted) _released.complete();
  }
}

class _GatedNativeCodec implements ui.Codec {
  _GatedNativeCodec(this.raw, this.gate);
  final ui.Codec raw;
  final _NativeFrameGate gate;
  int disposals = 0;

  @override
  int get frameCount => raw.frameCount;
  @override
  int get repetitionCount => raw.repetitionCount;

  @override
  Future<ui.FrameInfo> getNextFrame() async {
    final frame = await raw.getNextFrame();
    gate.frames.add(frame);
    gate.pendingFrames++;
    await gate._released.future;
    gate.pendingFrames--;
    return frame;
  }

  @override
  void dispose() {
    disposals++;
    raw.dispose();
  }
}

/// Override only one fixture file. ReaderImageProvider's exists/length/read,
/// cancellation checks, native decoder and cache lifecycle still execute.
final class _LocalReadGate extends IOOverrides {
  _LocalReadGate(File file) : file = _GatedReadFile(file);
  final _GatedReadFile file;
  int get reads => file.reads;
  int get completedReads => file.completedReads;

  @override
  File createFile(String path) =>
      path.replaceAll('\\', '/') == file.path.replaceAll('\\', '/')
      ? file
      : super.createFile(path);

  void release() => file.release();
}

class _GatedReadFile implements File {
  _GatedReadFile(this.raw);
  final File raw;
  final _released = Completer<void>();
  int reads = 0;
  int completedReads = 0;
  @override
  String get path => raw.path;
  @override
  Future<bool> exists() => raw.exists();
  @override
  bool existsSync() => raw.existsSync();
  @override
  Future<int> length() => raw.length();
  @override
  int lengthSync() => raw.lengthSync();

  @override
  Future<Uint8List> readAsBytes() async {
    reads++;
    final bytes = await raw.readAsBytes();
    await _released.future;
    completedReads++;
    return bytes;
  }

  void release() {
    if (!_released.isCompleted) _released.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ReaderImageExporter _exporter(
  ReaderState reader, {
  Future<Uint8List> Function(ReaderImageSelection)? read,
  required FutureOr<void> Function(ReaderImageExport) save,
  void Function(Object, StackTrace)? onError,
}) => ReaderImageExporter(
  work: reader.imageWork,
  select: () async => const ReaderImageSelection(
    imageKey: '1.png',
    sourceKey: 'local',
    comicId: 'book',
    chapterId: 'one',
    title: 'Book',
    chapter: 1,
    imageNumber: 1,
  ),
  read: read ?? (_) async => img.encodePng(img.Image(width: 1, height: 1)),
  save: save,
  share: save,
  onError: onError ?? (error, _) => fail('Unexpected export failure: $error'),
);

Future<ApplicationHost> _readerHost(void Function() close) async {
  final core = CoreBootstrap(
    environment: () async {},
    settings: () async {},
    infrastructure: () async {},
    sources: () async {},
    stores: () async {},
    finish: () async {},
    failureCleanup: [(name: 'reader store', close: () async => close())],
  );
  await core.start();
  return ApplicationHost(
    core: core,
    sync: SyncTestFixture().controller,
    sourceUpdates: SourceUpdateService(),
    dataOperations: AppDataOperations(),
  );
}

class _ReaderFixture {
  _ReaderFixture()
    : previousSettings = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(appdata.toJson()['settings'])) as Map,
      ),
      previousFavorites = _favoritesOwner,
      previousHistory = _historyOwner,
      previousLogMuted = Log.isMuted;

  final Map<String, dynamic> previousSettings;
  final LocalFavoritesManager? previousFavorites;
  final HistoryManager? previousHistory;
  final bool previousLogMuted;
  final history = _ControlledHistory();
  late final images = ImageFavoriteManager.create(history: history);
  final previousImages = _imageOwner;
  final readerKey = GlobalKey<_TestReaderState>();
  late final Directory directory;
  late WindowFrameController frame;
  int exits = 0;
  int notifications = 0;
  int imageCount = 3;

  static Future<_ReaderFixture> create(
    WidgetTester tester, {
    int imageCount = 3,
    ComicLayout? layout,
  }) async {
    final fixture = _ReaderFixture();
    fixture.imageCount = imageCount;
    fixture.directory = Directory.systemTemp.createTempSync('reader-exit-');
    App.dataPath = fixture.directory.path;
    App.cachePath = fixture.directory.path;
    Log.isMuted = true;
    _historyOwner = fixture.history;
    _imageOwner = fixture.images;
    _favoritesOwner = _Favorites();
    final settings = appdata.settings;
    settings['comicSpecificSettings'] = <String, dynamic>{};
    settings['deviceSpecificSettings'] = <String, dynamic>{};
    settings['autoReaderMode'] = false;
    settings['readerMode'] = ReaderMode.galleryLeftToRight.key;
    settings['readerScreenPicNumberForLandscape'] = 1;
    settings['readerScreenPicNumberForPortrait'] = 1;
    settings['autoPageTurningInterval'] = 60;
    settings['autoReadingAcrossChapters'] = false;
    settings['enableClockAndBatteryInfoInReader'] = false;
    settings['showPageNumberInReader'] = false;
    settings['eInkMode'] = false;
    settings['language'] = 'en-US';
    LocalManager.current?.dispose();
    LocalManager(initializeSources: () async {});
    await tester.runAsync(() async {
      final root = fixture.directory.path;
      Directory('$root/comics').createSync();
      File('$root/local_path').writeAsStringSync('$root/comics');
      await fixture.history.init();
      await LocalManager().init();
      final png = img.encodePng(
        img.Image(
          width: 100,
          height: layout == ComicLayout.longStrip ? 400 : 150,
        ),
      );
      final cover = layout == null
          ? png
          : img.encodePng(
              img.Image(
                width: 100,
                height: layout == ComicLayout.longStrip ? 150 : 400,
              ),
            );
      final folder = Directory('${LocalManager().path}/book/one')
        ..createSync(recursive: true);
      for (var page = 1; page <= imageCount; page++) {
        File(
          '${folder.path}/$page.png',
        ).writeAsBytesSync(page == 1 ? cover : png);
      }
      await LocalManager().add(
        LocalComic(
          id: 'book',
          title: 'Book',
          subtitle: '',
          tags: const [],
          directory: 'book',
          chapters: _chapters,
          cover: '',
          comicType: ComicType.local,
          downloadedChapters: const ['one'],
          createdAt: DateTime(2026),
        ),
      );
    });
    return fixture;
  }

  Future<void> mount(
    WidgetTester tester, {
    required bool pushed,
    bool waitForImage = true,
    bool expectContent = true,
    bool withWindow = true,
    SelectionTaskRegistry? registry,
    ValueNotifier<SelectionTaskRegistry>? registries,
    WindowFinalizer? finalize,
    ReaderVolumeConnection Function(void Function(Object?))? volumeConnect,
    ReaderWindowCoordinator? windowCoordinator,
    double textScale = 1,
    bool reducedMotion = false,
    Brightness brightness = Brightness.light,
    void Function(WindowFrameController)? beforeReaderMount,
    ComicChapters? chapters = _chapters,
    String comicId = 'book',
    ComicType comicType = ComicType.local,
    History? savedHistory,
    int? initialChapter,
    int? initialPage,
    int? initialChapterGroup,
    bool persistentAnnotations = false,
    bool globalImport = false,
    ExportAnnotationNotes? exportNotes,
    String? initialAnnotationId,
    ResolveAnnotationLink? resolveLink,
  }) async {
    var registered = false;
    final importRoutes = ImportCommandRoutes();
    Widget reader() {
      final content = Scaffold(
        body: _TestReader(
          key: readerKey,
          onClosed: () => notifications++,
          volumeConnect: volumeConnect,
          windowCoordinator: windowCoordinator,
          chapters: chapters,
          comicId: comicId,
          comicType: comicType,
          savedHistory: savedHistory,
          initialChapter: initialChapter,
          initialPage: initialPage,
          initialChapterGroup: initialChapterGroup,
          initialAnnotationId: initialAnnotationId,
        ),
      );
      return persistentAnnotations
          ? AnnotationServicesScope(
              openSession: openLocalAnnotationSession,
              exportNotes: exportNotes ?? exportLocalAnnotations,
              backupNotes: backupLocalAnnotations,
              relocateOriginal: selectAnnotationOriginal,
              findRecovery: findRecoverableAnnotations,
              recoverNotes: recoverLocalAnnotations,
              findManualRecovery: findManualAnnotationRecovery,
              prepareManualRecovery: prepareManualAnnotationRecovery,
              locatePage: locateRegisteredAnnotationPage,
              resolveLink: resolveLink ?? resolveAnnotationLinkDestination,
              child: content,
            )
          : content;
    }

    if (volumeConnect != null) {
      appdata.settings['enableTurnPageByVolumeKey'] = true;
      appdata.settings['enablePageAnimation'] = false;
    }
    await tester.pumpWidget(
      _libraryView(
        MaterialApp(
          theme: ThemeData(
            brightness: brightness,
            fontFamily: Platform.environment['WINDOW_OWNER_QA_FONT'] == null
                ? null
                : 'WindowOwnerQA',
          ),
          navigatorKey: appNavigation.rootNavigatorKey,
          navigatorObservers: [if (globalImport) importRoutes],
          builder: (context, child) {
            Widget content = ReaderPlatformEffectsScope(
              child: OverlayWidget(child!),
            );
            if (globalImport) {
              content = ImportCommands(
                routes: importRoutes,
                canOpen: () => true,
                open: () =>
                    showLocalComicImportDialog(appNavigation.rootContext),
                child: content,
              );
            }
            if (withWindow) {
              content = WindowFrame(
                Builder(
                  builder: (context) {
                    frame = WindowFrame.of(context);
                    if (!registered) {
                      registered = true;
                      beforeReaderMount?.call(frame);
                    }
                    return ReaderPlatformEffectsScope(
                      child: OverlayWidget(child),
                    );
                  },
                ),
                onExit: () => exits++,
                finalize: finalize,
              );
            }
            content = MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                disableAnimations: reducedMotion,
              ),
              child: content,
            );
            if (persistentAnnotations) {
              content = AnnotationServicesScope(
                openSession: openLocalAnnotationSession,
                exportNotes: exportNotes ?? exportLocalAnnotations,
                backupNotes: backupLocalAnnotations,
                relocateOriginal: selectAnnotationOriginal,
                findRecovery: findRecoverableAnnotations,
                recoverNotes: recoverLocalAnnotations,
                findManualRecovery: findManualAnnotationRecovery,
                prepareManualRecovery: prepareManualAnnotationRecovery,
                locatePage: locateRegisteredAnnotationPage,
                resolveLink: resolveLink ?? resolveAnnotationLinkDestination,
                child: ReaderSessionScope(
                  onClosed: () => notifications++,
                  child: content,
                ),
              );
            }
            if (registries != null) {
              return ValueListenableBuilder<SelectionTaskRegistry>(
                valueListenable: registries,
                child: content,
                builder: (_, registry, child) =>
                    SelectionTasksScope(registry: registry, child: child!),
              );
            }
            return registry == null
                ? content
                : SelectionTasksScope(registry: registry, child: content);
          },
          home: pushed ? const Scaffold(body: Text('Library home')) : reader(),
        ),
      ),
    );
    if (pushed) {
      unawaited(
        appNavigation.rootNavigatorKey.currentState!.push<void>(
          MaterialPageRoute(builder: (_) => reader()),
        ),
      );
    }
    if (!expectContent) {
      await tester.pump(const Duration(seconds: 1));
      return;
    }
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      final current = readerKey.currentState;
      if (!waitForImage &&
          current?.imageViewController is AutoReadingViewport &&
          current?.isLoading == false) {
        break;
      }
      if (current?.imageViewController case AutoReadingViewport viewport
          when viewport.autoReadingReady && !current!.isLoading) {
        break;
      }
    }
    expect(readerKey.currentState?.images, hasLength(imageCount));
    expect(readerKey.currentState?.isLoading, isFalse);
    expect(
      readerKey.currentState?.imageViewController,
      isA<AutoReadingViewport>(),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  }

  void closeWindow(WidgetTester tester) =>
      (tester.state(find.byType(WindowFrame)) as WindowListener)
          .onWindowClose();

  Future<void> dispose(WidgetTester tester) async {
    history.onProgress = null;
    history.onDuration = null;
    readerKey.currentState?.autoReading.stop();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    LocalManager.current?.dispose();
    history.close();
    images.dispose();
    _imageOwner = previousImages;
    _historyOwner = previousHistory;
    _favoritesOwner = previousFavorites;
    Log.isMuted = previousLogMuted;
    previousSettings.forEach((key, value) => appdata.settings[key] = value);
    directory.deleteSync(recursive: true);
  }
}

Comment _readerComment(String text) =>
    Comment.fromJson({'id': text, 'userName': 'Reader', 'content': text});

class _ReaderCommentSource extends Fake implements ComicSource {
  Future<Res<List<Comment>>> Function() load = () async => Res([], subData: 1);
  Future<Res<bool>> Function() send = () async => const Res(true);
  @override
  String get key => 'local';
  @override
  ChapterCommentsLoader get chapterCommentsLoader =>
      (_, _, _, _) => load();
  @override
  SendChapterCommentFunc get sendChapterCommentFunc =>
      (_, _, _, _) => send();
  @override
  LikeCommentFunc? get likeCommentFunc => null;
  @override
  VoteCommentFunc? get voteCommentFunc => null;
}

class _ReaderPagesSource extends _ReaderCommentSource {
  _ReaderPagesSource(this._loadPages);
  final LoadComicPagesFunc _loadPages;
  @override
  String get key => 'replacement';
  @override
  LoadComicPagesFunc get loadComicPages => _loadPages;
}

void Function() _readerCommentRegistry(_ReaderCommentSource Function() source) {
  final manager = ComicSourceManager();
  configureComicSourceRegistry(
    all: manager.all,
    find: (key) => key == 'local' ? source() : manager.find(key),
    fromIntKey: manager.fromIntKey,
    isEmpty: () => false,
  );
  return () => configureComicSourceRegistry(
    all: manager.all,
    find: manager.find,
    fromIntKey: manager.fromIntKey,
    isEmpty: () => manager.isEmpty,
  );
}

class _OtherComicType extends ComicType {
  const _OtherComicType() : super(42);
  @override
  String get sourceKey => 'replacement';
}

class _TestReader extends Reader {
  _TestReader({
    required super.key,
    required super.onClosed,
    this.volumeConnect,
    this.windowCoordinator,
    super.chapters = _chapters,
    String comicId = 'book',
    ComicType comicType = ComicType.local,
    History? savedHistory,
    super.initialChapter,
    super.initialPage,
    super.initialChapterGroup,
    super.initialAnnotationId,
  }) : super(
         type: comicType,
         cid: comicId,
         name: 'Book',
         author: '',
         tags: const [],
         history: savedHistory ?? _resumeHistory(),
       );

  final ReaderVolumeConnection Function(void Function(Object?))? volumeConnect;
  final ReaderWindowCoordinator? windowCoordinator;

  @override
  ReaderState createState() => _TestReaderState();
}

class _TestReaderState extends ReaderState {
  ComicLayoutProbe? layoutProbe;
  Future<void> Function()? onSaveSettings;
  int settingsSaves = 0;

  @override
  ReaderWindowCoordinator get windowCoordinator =>
      (widget as _TestReader).windowCoordinator ?? super.windowCoordinator;

  @override
  bool get supportsVolumeKeys => (widget as _TestReader).volumeConnect != null;

  @override
  ReaderVolumeConnection createVolumeConnection(void Function(Object?) send) =>
      (widget as _TestReader).volumeConnect!(send);

  @override
  ComicLayoutProbe createLayoutProbe() =>
      layoutProbe ?? super.createLayoutProbe();

  @override
  Future<void> saveReadingSettings(void Function(Settings draft) edit) {
    settingsSaves++;
    if (onSaveSettings case final save?) {
      edit(appdata.settings);
      return save();
    }
    return super.saveReadingSettings(edit);
  }

  @override
  void setImageCacheSize() {}
}

class _VolumeLease implements ReaderVolumeConnection {
  _VolumeLease(this.send, {this.release});
  final void Function(Object?) send;
  final Future<void> Function()? release;
  int closes = 0;
  @override
  Future<void> get ready => Future.value();
  @override
  Future<void> closeAndWait() async {
    closes++;
    await release?.call();
  }
}

/// Separate UI and cleanup gates; the real reader/session/window owns both.
class _LayoutProbeGate extends ComicLayoutProbe {
  final _result = Completer<ComicLayoutDetection>();
  final _cleanup = Completer<void>();
  bool started = false;
  bool _cancelled = false;

  @override
  bool get isCancelled => _cancelled;
  @override
  Future<void> get done => _cleanup.future;

  @override
  Future<ComicLayoutDetection> detect({
    required List<String> images,
    required String? sourceKey,
    required String comicId,
    required String chapterId,
  }) {
    started = true;
    return _result.future;
  }

  @override
  void cancel() {
    _cancelled = true;
    if (!_result.isCompleted) {
      _result.complete(const ComicLayoutDetection(ComicLayout.unknown, 0));
    }
  }

  void finish([ComicLayout layout = ComicLayout.unknown]) {
    if (!_cleanup.isCompleted) _cleanup.complete();
    if (!_result.isCompleted) _result.complete(ComicLayoutDetection(layout, 6));
  }
}

class _ControlledHistory extends HistoryManager {
  _ControlledHistory() : super.create();

  final progress = <History>[];
  final durations = <Duration>[];
  Future<void> Function(History)? onProgress;
  Future<void> Function(Duration)? onDuration;

  @override
  Future<void> addHistory(History history) {
    final snapshot = history.copy();
    progress.add(snapshot);
    return onProgress?.call(snapshot) ?? Future.value();
  }

  @override
  Future<void> addReadDuration(History history, Duration duration) async {
    durations.add(duration);
    await onDuration?.call(duration);
  }
}

class _Favorites extends ChangeNotifier implements LocalFavoritesManager {
  @override
  int get connectionGeneration => 1;
  Future<void>? reading;
  int reads = 0;

  @override
  Future<void> onRead(
    String id,
    ComicType type, {
    int? generation,
    void Function()? checkActive,
  }) async {
    checkActive?.call();
    reads++;
    await reading;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PlatformEffectsProbe {
  final events = <String>[];
  String orientation = '';
  bool barsVisible = true;
  Future<void> Function(String)? onOrientation;
  Future<void> Function(bool)? onBars;

  void install() => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          final value = (call.arguments as List).join(',');
          events.add('orientation:$value');
          await onOrientation?.call(value);
          orientation = value;
        } else if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
          final value = call.arguments == 'SystemUiMode.edgeToEdge';
          events.add('bars:$value');
          await onBars?.call(value);
          barsVisible = value;
        }
        return null;
      });

  void uninstall() => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
}

class _NativeWindow {
  bool fullscreen = false;
  bool visible = true;
  final events = <String>[];
  Future<void> Function(bool)? onFullscreen;
  Future<void> Function()? onShow;
  late final coordinator = ReaderWindowCoordinator(
    hide: () async {
      events.add('hide');
      visible = false;
    },
    show: () async {
      events.add('show');
      await onShow?.call();
      visible = true;
    },
    setFullscreen: (value) async {
      events.add('fullscreen:$value');
      await onFullscreen?.call(value);
      fullscreen = value;
    },
  );
}

LocalFavoritesManager? _favoritesOwner;
LocalFavoritesManager _favoritesForView() =>
    _favoritesOwner ??= LocalFavoritesManager.independent();
HistoryManager? _historyOwner;
HistoryManager _historyForView() => _historyOwner ??= HistoryManager.create();
Widget? _libraryChild;
ImageFavoriteManager? _imageOwner;
Widget _libraryView(Widget child) {
  _libraryChild = child;
  return FavoritesScope(
    manager: _favoritesForView(),
    child: HistoryScope(
      manager: _historyForView(),
      imageFavorites: _imageOwner,
      child: child,
    ),
  );
}

Future<void> _replaceHistory(
  WidgetTester tester,
  HistoryManager manager, {
  ImageFavoriteManager? images,
}) async {
  _historyOwner = manager;
  final next = images ?? ImageFavoriteManager.create(history: manager);
  if (images == null) addTearDown(next.dispose);
  _imageOwner = next;
  await tester.pumpWidget(_libraryView(_libraryChild!));
}
