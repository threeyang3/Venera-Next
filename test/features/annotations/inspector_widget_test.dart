import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/annotations/annotations.dart';

void main() {
  late AnnotationSession session;
  setUp(() {
    session = AnnotationSession();
  });
  testWidgets(
    'recovery requires choosing a candidate and cancellation leaves the panel intact',
    (tester) async {
      String? restored;
      var closes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AnnotationInspector(
            session: session,
            isCurrent: () => true,
            onOpen: (_) async {},
            onChanged: () {},
            onClose: () => closes++,
            findRecovery: () async => [
              const RecoverableAnnotationDocument(
                documentId: 'old-id',
                title: 'Old notes',
                annotationCount: 3,
              ),
            ],
            onRecover: (id) async => restored = id,
          ),
        ),
      );
      await tester.tap(find.text('恢复旧批注'));
      await tester.pumpAndSettle();
      expect(find.text('恢复同一原件的旧批注'), findsOneWidget);
      expect(restored, isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(closes, 0);
      expect(restored, isNull);
      await tester.tap(find.text('恢复旧批注'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Old notes'));
      await tester.pumpAndSettle();
      expect(restored, 'old-id');
      expect(closes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('retired recovery lookup cannot present a candidate dialog', (
    tester,
  ) async {
    var active = true;
    final candidates = Completer<List<RecoverableAnnotationDocument>>();
    await tester.pumpWidget(
      MaterialApp(
        home: AnnotationInspector(
          session: session,
          isCurrent: () => active,
          onOpen: (_) async {},
          onChanged: () {},
          findRecovery: () => candidates.future,
          onRecover: (_) async => fail('Retired recovery submitted'),
        ),
      ),
    );
    await tester.tap(find.text('恢复旧批注'));
    await tester.pump();
    active = false;
    candidates.complete([
      const RecoverableAnnotationDocument(
        documentId: 'old-id',
        title: 'Old notes',
        annotationCount: 3,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('恢复同一原件的旧批注'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'relocation keeps the inspector mounted, reports errors, and allows retry',
    (tester) async {
      final pending = Completer<String?>();
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AnnotationInspector(
            session: session,
            isCurrent: () => true,
            onOpen: (_) async {},
            onChanged: () {},
            onRelocate: () {
              attempts++;
              return attempts == 1 ? pending.future : Future.value('原件已重新关联');
            },
          ),
        ),
      );
      await tester.tap(find.text('重新关联原件'));
      await tester.pump();
      expect(find.text('正在校验原件…'), findsOneWidget);
      expect(attempts, 1);
      pending.completeError(StateError('版本不一致'));
      await tester.pumpAndSettle();
      expect(find.textContaining('关联失败：'), findsOneWidget);
      expect(find.byType(AnnotationInspector), findsOneWidget);
      await tester.tap(find.text('重新关联原件'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text('原件已重新关联'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('tags can be edited and used to filter notes', (tester) async {
    final page = session.anchor(
      chapterId: 'one',
      imageNumber: 1,
      width: 100,
      height: 200,
    );
    final note = session.add(page, AnnotationKind.pageNote, '待整理');
    session.add(page, AnnotationKind.bookmark, '其他笔记');
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 380,
          child: AnnotationInspector(
            session: session,
            isCurrent: () => true,
            onOpen: (_) async {},
            onChanged: () {},
          ),
        ),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('annotation-note:${note.id}')),
        matching: find.byTooltip('编辑标签'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('annotation-tags-editor')),
      '构图，人物，构图',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(session.all.firstWhere((n) => n.id == note.id).tags, ['人物', '构图']);
    await tester.tap(find.widgetWithText(ActionChip, '构图'));
    await tester.pump();
    expect(find.text('待整理'), findsOneWidget);
    expect(find.text('其他笔记'), findsNothing);
    // Exact tag filter stays active until its explicit clear action is used.
    await tester.tap(find.byTooltip('清除标签筛选'));
    await tester.pump();
    expect(find.text('其他笔记'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('annotation-search')),
      '人物',
    );
    await tester.pump();
    expect(find.text('待整理'), findsOneWidget);
    expect(find.text('其他笔记'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Mac docked note selection exposes working edit actions', (
    tester,
  ) async {
    var backups = 0, relocations = 0;
    final page = session.anchor(
      chapterId: 'one',
      imageNumber: 1,
      width: 100,
      height: 200,
    );
    session.add(page, AnnotationKind.pageNote, '待编辑');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: AnnotationInspector(
          session: session,
          isCurrent: () => true,
          onOpen: (_) async {},
          onChanged: () {},
          keepOpenOnActions: true,
          onBackup: () => backups++,
          onRelocate: () async {
            relocations++;
            return '原件已重新关联';
          },
        ),
      ),
    );
    if (const bool.fromEnvironment('COMICNOTES_WORKSPACE')) {
      expect(find.byTooltip('编辑批注'), findsNothing);
      await tester.tap(find.text('整页 · 第 1 页'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('编辑批注'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AnnotationEditor),
        matching: find.byType(TextField),
      ),
      '已编辑',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(session.all.single.text, '已编辑');
    expect(find.byType(AnnotationInspector), findsOneWidget);
    session.add(page, AnnotationKind.bookmark, '回看这一页');
    if (const bool.fromEnvironment('COMICNOTES_WORKSPACE')) {
      await tester.tap(find.text('书签'));
      await tester.pumpAndSettle();
      expect(find.text('已编辑'), findsNothing);
      expect(find.text('回看这一页'), findsOneWidget);
      expect(find.text('找到 1 条批注'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('annotation-search')),
        '不存在的文字',
      );
      await tester.pumpAndSettle();
      expect(find.text('找到 0 条批注'), findsOneWidget);
      await tester.tap(find.byTooltip('清除批注搜索'));
      await tester.pumpAndSettle();
      expect(find.text('回看这一页'), findsOneWidget);
      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();
      expect(find.text('已编辑'), findsOneWidget);
      await tester.tap(find.byTooltip('更多批注操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('备份全部批注'));
      await tester.pumpAndSettle();
      expect(backups, 1);
      await tester.tap(find.byTooltip('更多批注操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重新关联原件'));
      await tester.pumpAndSettle();
      expect(relocations, 1);
      expect(find.text('原件已重新关联'), findsOneWidget);
      expect(find.byType(AnnotationInspector), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Mac note keys navigate offscreen items without taking search input',
    (tester) async {
      final page = session.anchor(
        chapterId: 'one',
        imageNumber: 1,
        width: 100,
        height: 200,
      );
      for (var i = 1; i <= 40; i++) {
        session.add(
          page,
          AnnotationKind.pageNote,
          'Keyboard note ${i.toString().padLeft(2, '0')}',
        );
      }
      final ordered = session.all.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final opened = <String>[];
      var inputHeld = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: AnnotationInspector(
            session: session,
            isCurrent: () => true,
            onOpen: (note) async => opened.add(note.id),
            onChanged: () {},
            keepOpenOnActions: true,
            onInputChanged: (active) => inputHeld = active,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(ordered.first.text));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(inputHeld, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(find.text(ordered.last.text).hitTestable(), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(opened, [ordered.last.id]);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(opened.last, ordered[ordered.length - 2].id);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(find.text(ordered.first.text).hitTestable(), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('annotation-search')),
        ordered.last.text,
      );
      await tester.pumpAndSettle();
      final beforeSearchEnter = opened.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(opened.length, beforeSearchEnter);
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey('annotation-note:${ordered.last.id}')),
          matching: find.text(ordered.last.text),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(opened.last, ordered.last.id);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(inputHeld, isFalse);
    },
    skip: !const bool.fromEnvironment('COMICNOTES_WORKSPACE'),
  );

  testWidgets('book-wide notes filter by text and kind across pages', (
    tester,
  ) async {
    final first = session.anchor(
      chapterId: 'one',
      imageNumber: 1,
      width: 100,
      height: 200,
    );
    final second = session.anchor(
      chapterId: 'two',
      imageNumber: 2,
      width: 100,
      height: 200,
    );
    session.add(first, AnnotationKind.pageNote, '第一页的对白');
    session.add(second, AnnotationKind.bookmark, '第二页书签');
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 380,
          child: AnnotationInspector(
            session: session,
            isCurrent: () => true,
            onOpen: (_) async {},
            onChanged: () {},
          ),
        ),
      ),
    );
    expect(find.text('全书批注 · 2'), findsOneWidget);
    expect(find.text('第一页的对白'), findsOneWidget);
    expect(find.text('第二页书签'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('annotation-search')),
      '对白',
    );
    await tester.pump();
    expect(find.text('第一页的对白'), findsOneWidget);
    expect(find.text('第二页书签'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('annotation-search')), '');
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, '书签'));
    await tester.pump();
    expect(find.text('第一页的对白'), findsNothing);
    expect(find.text('第二页书签'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'an inspector cannot save edits after its source session retires',
    (tester) async {
      final page = session.anchor(
        chapterId: 'one',
        imageNumber: 1,
        width: 100,
        height: 200,
      );
      session.add(page, AnnotationKind.pageNote, '旧文字');
      var current = true;
      await tester.pumpWidget(
        MaterialApp(
          home: AnnotationInspector(
            session: session,
            isCurrent: () => current,
            onOpen: (_) async {},
            onChanged: () {},
          ),
        ),
      );
      await tester.tap(find.byTooltip('编辑批注'));
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byType(AnnotationEditor),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, '迟到的编辑');
      current = false;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(session.all.single.text, '旧文字');
      expect(tester.takeException(), isNull);
    },
  );
}
