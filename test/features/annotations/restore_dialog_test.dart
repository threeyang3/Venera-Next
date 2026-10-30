import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/annotations/annotations.dart';
import 'package:venera_next/features/annotations/application/annotation_restore_service.dart';

class Preview extends AnnotationRestorePreview {
  int applied = 0;
  bool closed = false;
  @override
  int get documentCount => 3;
  @override
  int get annotationCount => 9;
  @override
  int get existingDocumentCount => 1;
  @override
  Future<void> dispose() async {
    closed = true;
  }

  @override
  Future<AnnotationRestoreResult> restore({
    bool Function()? isCancelled,
  }) async {
    applied++;
    return const AnnotationRestoreResult(2, 1);
  }
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    Future<AnnotationRestorePreview?> Function({
      required bool Function() isCancelled,
    })
    prepare,
  ) async {
    await tester.pumpWidget(
      AnnotationServicesScope(
        openSession:
            ({required libraryKey, required title, required sourceRoot}) =>
                AnnotationSession(),
        prepareRestore: prepare,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAnnotationRestoreDialog(context),
                child: const Text('Restore'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'review shows skip policy before explicit import and closes snapshot',
    (tester) async {
      final preview = Preview();
      await mount(tester, ({required isCancelled}) async => preview);
      expect(find.textContaining('3 册书、9 条'), findsOneWidget);
      expect(find.textContaining('现有笔记和删除记录会保留'), findsOneWidget);
      expect(preview.applied, 0);
      await tester.tap(find.text('导入缺失的批注'));
      await tester.pumpAndSettle();
      expect(preview.applied, 1);
      expect(preview.closed, isTrue);
      expect(find.textContaining('已恢复 2 册'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('cancel review never imports', (tester) async {
    final preview = Preview();
    await mount(tester, ({required isCancelled}) async => preview);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(preview.applied, 0);
    expect(preview.closed, isTrue);
  });
  testWidgets('cancel while picker is pending disposes eventual snapshot', (
    tester,
  ) async {
    final pending = Completer<AnnotationRestorePreview?>();
    final preview = Preview();
    bool Function()? cancelled;
    await tester.pumpWidget(
      AnnotationServicesScope(
        openSession:
            ({required libraryKey, required title, required sourceRoot}) =>
                AnnotationSession(),
        prepareRestore: ({required isCancelled}) {
          cancelled = isCancelled;
          return pending.future;
        },
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAnnotationRestoreDialog(context),
                child: const Text('Restore'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Restore'));
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(cancelled!(), isTrue);
    pending.complete(preview);
    await tester.pump();
    expect(preview.closed, isTrue);
    expect(preview.applied, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('validation failure stays reviewable without import action', (
    tester,
  ) async {
    await mount(
      tester,
      ({required isCancelled}) async => throw const FormatException('hash'),
    );
    expect(find.textContaining('备份验证失败'), findsOneWidget);
    expect(find.text('导入缺失的批注'), findsNothing);
  });
}
