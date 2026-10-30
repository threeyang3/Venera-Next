import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/reader/annotation_workspace.dart';

void main() {
  for (final enabled in [true, false]) {
    testWidgets(
      'respects window title bar only for workspace; enabled=$enabled',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey<_CanvasProbeState>();
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(padding: const EdgeInsets.only(top: 36)),
              child: child!,
            ),
            home: ReaderAnnotationWorkspace(
              enabled: enabled,
              title: 'Book',
              onBack: () {},
              onSettings: () {},
              inspectorBuilder: (_) =>
                  const SizedBox.expand(key: ValueKey('inspector')),
              canvasBuilder: (_) => _CanvasProbe(key: key),
            ),
          ),
        );
        if (enabled) {
          expect(
            tester.getTopLeft(find.byTooltip('返回书库')).dy,
            greaterThanOrEqualTo(36),
          );
          expect(tester.getTopLeft(find.byKey(key)).dy, 88);
          expect(key.currentState!.mediaSize, const Size(1280, 812));
          await tester.tap(find.byTooltip('展开批注栏'));
          await tester.pumpAndSettle();
          expect(
            tester.getTopLeft(find.byKey(const ValueKey('inspector'))).dy,
            88,
          );
          expect(key.currentState!.mediaSize, const Size(920, 812));
          await tester.tap(find.byTooltip('专注阅读'));
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(find.byKey(key)).dy, 36);
          expect(key.currentState!.mediaSize, const Size(1280, 864));
        } else {
          expect(tester.getTopLeft(find.byKey(key)).dy, 0);
          expect(key.currentState!.mediaSize, const Size(1280, 900));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'dock and focus mode retain the canvas and update its local MediaQuery',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey<_CanvasProbeState>();
      final workspace = GlobalKey<ReaderAnnotationWorkspaceState>();
      var viewportChanges = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderAnnotationWorkspace(
            key: workspace,
            onCanvasChanged: () => viewportChanges++,
            enabled: true,
            title: '漫画观察',
            chapterTitle: '第一章',
            onBack: () {},
            onSettings: () {},
            inspectorBuilder: (close) => Material(
              child: TextButton(onPressed: close, child: const Text('关闭检查栏')),
            ),
            canvasBuilder: (_) => _CanvasProbe(key: key),
          ),
        ),
      );
      final state = key.currentState!;
      expect(tester.getSize(find.byKey(key)), const Size(1280, 848));
      expect(state.mediaSize, const Size(1280, 848));
      await tester.tap(find.byTooltip('展开批注栏'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(key)), const Size(920, 848));
      expect(state.mediaSize, const Size(920, 848));
      expect(key.currentState, same(state));
      await tester.tap(find.byTooltip('专注阅读'));
      await tester.pumpAndSettle();
      expect(find.text('关闭检查栏'), findsNothing);
      expect(tester.getSize(find.byKey(key)), const Size(1280, 900));
      final changesBeforeFloating = viewportChanges;
      workspace.currentState!.showInspector();
      await tester.pumpAndSettle();
      expect(find.text('关闭检查栏'), findsOneWidget);
      expect(tester.getSize(find.byKey(key)), const Size(1280, 900));
      expect(state.mediaSize, const Size(1280, 900));
      expect(key.currentState, same(state));
      expect(viewportChanges, changesBeforeFloating);
      await tester.tap(find.text('关闭检查栏'));
      await tester.pumpAndSettle();
      expect(find.text('关闭检查栏'), findsNothing);
      expect(find.byTooltip('显示工作台'), findsOneWidget);
      workspace.currentState!.showInspector();
      await tester.pumpAndSettle();
      expect(workspace.currentState!.inspectorOpen, isTrue);
      expect(find.text('关闭检查栏'), findsOneWidget);
      expect(state.mediaSize, const Size(1280, 900));
      expect(viewportChanges, changesBeforeFloating);
      await tester.tap(find.byTooltip('显示工作台'));
      await tester.pumpAndSettle();
      expect(find.text('关闭检查栏'), findsOneWidget);
      await tester.tap(find.text('关闭检查栏'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(key)), const Size(1280, 848));
      expect(key.currentState, same(state));
      expect(tester.takeException(), isNull);
    },
  );
  for (final enabled in [true, false]) {
    testWidgets('narrow layout retains full canvas; enabled=$enabled', (
      tester,
    ) async {
      final key = GlobalKey<ReaderAnnotationWorkspaceState>();
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderAnnotationWorkspace(
            key: key,
            enabled: enabled,
            title: 'Book',
            onBack: () {},
            onSettings: () {},
            inspectorBuilder: (_) => const Text('Inspector'),
            canvasBuilder: (_) =>
                const SizedBox.expand(key: ValueKey('canvas')),
          ),
        ),
      );
      expect(key.currentState!.available, isFalse);
      expect(find.byTooltip('展开批注栏'), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('canvas'))),
        const Size(800, 600),
      );
      expect(tester.takeException(), isNull);
    });
  }
}

class _CanvasProbe extends StatefulWidget {
  const _CanvasProbe({super.key});
  @override
  State<_CanvasProbe> createState() => _CanvasProbeState();
}

class _CanvasProbeState extends State<_CanvasProbe> {
  Size? mediaSize;
  @override
  Widget build(BuildContext context) {
    mediaSize = MediaQuery.sizeOf(context);
    return const ColoredBox(color: Colors.black);
  }
}
