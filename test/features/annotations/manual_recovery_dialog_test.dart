import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:venera_next/features/annotations/annotations.dart';

class Preview extends AnnotationManualRecoveryPreview {
  Preview({int count = 2, double targetWidth = 20, double targetHeight = 30}) {
    for (var i = 1; i <= count; i++) {
      final old = PageAnchor(
        documentId: 'old',
        pageId: 'old-$i',
        chapterId: 'old',
        sourceImageNumber: i,
        sourceWidth: 20,
        sourceHeight: 30,
      );
      previousPages.add(
        AnnotationSourcePage(
          anchor: old,
          sourceIdentity: 'old/$i.png',
          assetUri: null,
          locator: const {},
        ),
      );
      targets.add(
        AnnotationManualTargetPage(
          page: AnnotationSourcePage(
            anchor: PageAnchor(
              documentId: 'new',
              pageId: 'new-$i',
              chapterId: 'new',
              sourceImageNumber: i,
              sourceWidth: targetWidth,
              sourceHeight: targetHeight,
            ),
            sourceIdentity: 'target/$i.png',
            assetUri: 'file:///target/$i.png',
            locator: const {},
          ),
          thumbnail: Uint8List.fromList(
            image.encodePng(image.Image(width: 20, height: 30)),
          ),
        ),
      );
      annotations.add(
        Annotation(
          id: 'note-$i',
          anchor: old,
          kind: AnnotationKind.region,
          text: 'Old note $i',
          rect: ContentRect(.1, .2, .7, .8),
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
    }
  }
  @override
  final previous = const AnnotationSourceDocument(
    documentId: 'old',
    title: 'Old book',
    libraryKey: 'orphan:old',
    status: 'unlinked',
  );
  @override
  final previousPages = <AnnotationSourcePage>[];
  @override
  final annotations = <Annotation>[];
  @override
  final targets = <AnnotationManualTargetPage>[];
  int commits = 0, disposals = 0;
  bool fail = false;
  Completer<void>? pending;
  Map<String, String>? mapping;
  Set<String>? reviewedDifferentDimensions;
  @override
  Future<bool> commit({
    required Map<String, String> pageMapping,
    Set<String> reviewedDifferentDimensions = const {},
    required bool Function() isCurrent,
  }) async {
    commits++;
    mapping = Map.of(pageMapping);
    this.reviewedDifferentDimensions = Set.of(reviewedDifferentDimensions);
    await pending?.future;
    if (!isCurrent()) return false;
    if (fail) throw StateError('write failed');
    return true;
  }

  @override
  Future<void> dispose() async {
    await pending?.future;
    disposals++;
  }
}

void main() {
  late Future<bool> result;
  Future<void> mount(
    WidgetTester tester,
    Future<AnnotationManualRecoveryPreview?> Function({
      required bool Function() isCurrent,
    })
    prepare,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Manual'),
              onPressed: () => result = showAnnotationManualRecoveryDialog(
                context,
                prepare: prepare,
                isCurrent: () => true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Manual'));
    await tester.pump();
  }

  Future<void> choose(WidgetTester tester, int index) async {
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('new · $index · target/$index.png').last);
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('确认恢复旧批注'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'all pages need unique explicit choices and confirmation; preview shows original rectangles',
    (tester) async {
      final preview = Preview();
      await mount(tester, ({required isCurrent}) async => preview);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.textContaining('旧原图未自动验证'), findsOneWidget);
      await choose(tester, 1);
      final overlay = tester.widget<AnnotationOverlay>(
        find.byType(AnnotationOverlay),
      );
      expect(overlay.page.pageId, 'new-1');
      expect(overlay.annotations.single.rect!.x0, .1);
      await tester.tap(find.byTooltip('下一张旧页'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.text('new · 1 · target/1.png'), findsNothing);
      await tester.tap(find.text('new · 2 · target/2.png').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await confirm(tester);
      expect(await result, isTrue);
      expect(preview.mapping, {'old-1': 'new-1', 'old-2': 'new-2'});
      expect(preview.disposals, 1);
    },
  );
  testWidgets(
    'clear mapping allows correcting a choice; write error retains mapping for retry',
    (tester) async {
      final preview = Preview(count: 1)..fail = true;
      await mount(tester, ({required isCurrent}) async => preview);
      await tester.pumpAndSettle();
      await choose(tester, 1);
      await tester.tap(find.text('清除此页关联'));
      await tester.pumpAndSettle();
      expect(find.byType(AnnotationOverlay), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await choose(tester, 1);
      await confirm(tester);
      expect(find.textContaining('旧批注仍保留'), findsOneWidget);
      expect(preview.commits, 1);
      expect(preview.disposals, 0);
      preview.fail = false;
      await tester.tap(find.text('确认恢复旧批注'));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
      expect(preview.commits, 2);
      expect(preview.disposals, 1);
    },
  );
  testWidgets(
    'closing during prepare cancels its target and drains late preview',
    (tester) async {
      final pending = Completer<AnnotationManualRecoveryPreview?>();
      late bool Function() current;
      await mount(tester, ({required isCurrent}) {
        current = isCurrent;
        return pending.future;
      });
      expect(find.text('正在校验目标页…'), findsOneWidget);
      await tester.tap(find.text('取消校验'));
      await tester.pumpAndSettle();
      expect(current(), isFalse);
      final preview = Preview();
      pending.complete(preview);
      await tester.pumpAndSettle();
      expect(await result, isFalse);
      expect(preview.disposals, 1);
      expect(preview.commits, 0);
    },
  );
  testWidgets(
    'cancel in-flight commit drains preview and never reports success',
    (tester) async {
      final preview = Preview(count: 1)..pending = Completer<void>();
      await mount(tester, ({required isCurrent}) async => preview);
      await tester.pumpAndSettle();
      await choose(tester, 1);
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('确认恢复旧批注'));
      await tester.pump();
      expect(preview.commits, 1);
      await tester.tap(find.text('取消校验'));
      await tester.pumpAndSettle();
      preview.pending!.complete();
      await tester.pumpAndSettle();
      expect(await result, isFalse);
      expect(preview.disposals, 1);
    },
  );
  testWidgets(
    'narrow large-text review scrolls controls and preserves explicit confirmation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 667);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final preview = Preview(count: 1);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Manual'),
                onPressed: () => result = showAnnotationManualRecoveryDialog(
                  context,
                  prepare: ({required isCurrent}) async => preview,
                  isCurrent: () => true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Manual'));
      await tester.pumpAndSettle();
      await choose(tester, 1);
      await confirm(tester);
      expect(await result, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'owner cancellation closes only its manual preview route and drains it',
    (tester) async {
      final preview = Preview(count: 1);
      final cancelled = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => result = showAnnotationManualRecoveryDialog(
                  context,
                  prepare: ({required isCurrent}) async => preview,
                  isCurrent: () => true,
                  cancelSignal: cancelled.future,
                ),
                child: const Text('Manual'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Manual'));
      await tester.pumpAndSettle();
      expect(find.text('逐页关联旧批注'), findsOneWidget);
      cancelled.complete();
      await tester.pumpAndSettle();
      expect(await result, isFalse);
      expect(preview.commits, 0);
      expect(preview.disposals, 1);
      expect(find.text('Manual'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a retired preparation removes its own route while another popup stays',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      final pending = Completer<AnnotationManualRecoveryPreview?>();
      var current = true;
      final preview = Preview(count: 1);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => result = showAnnotationManualRecoveryDialog(
                  context,
                  prepare: ({required isCurrent}) => pending.future,
                  isCurrent: () => current,
                ),
                child: const Text('Manual'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Manual'));
      await tester.pump();
      unawaited(
        showDialog<void>(
          context: navigator.currentContext!,
          builder: (_) => const AlertDialog(title: Text('Unrelated popup')),
        ),
      );
      await tester.pump();
      current = false;
      pending.complete(preview);
      await tester.pumpAndSettle();
      expect(await result, isFalse);
      expect(find.text('Unrelated popup'), findsOneWidget);
      expect(preview.disposals, 1);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Manual'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'prepare errors stay readable and close without leaking exceptions',
    (tester) async {
      await mount(
        tester,
        ({required isCurrent}) async => throw StateError('bad source'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('bad source'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('different dimensions require a per-page coordinate review', (
    tester,
  ) async {
    final preview = Preview(count: 1, targetWidth: 40, targetHeight: 60);
    await mount(tester, ({required isCurrent}) async => preview);
    await tester.pumpAndSettle();
    await choose(tester, 1);
    expect(find.textContaining('不同尺寸页面上的每个选区'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.ensureVisible(find.textContaining('不同尺寸页面上的每个选区'));
    await tester.tap(find.textContaining('不同尺寸页面上的每个选区'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.ensureVisible(find.text('我已逐页核对目标内容和所有选区'));
    await tester.tap(find.text('我已逐页核对目标内容和所有选区'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认恢复旧批注'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect(preview.reviewedDifferentDimensions, {'old-1'});
  });
}
