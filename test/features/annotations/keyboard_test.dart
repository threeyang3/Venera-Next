import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/annotations/annotations.dart';

Future<void> chord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
}) async {
  final modifier = control
      ? LogicalKeyboardKey.controlLeft
      : LogicalKeyboardKey.metaLeft;
  await tester.sendKeyDownEvent(modifier);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

void main() {
  PageAnchor page() => AnnotationSession().anchor(
    chapterId: '1',
    imageNumber: 1,
    width: 100,
    height: 200,
  );
  for (final modifier in ['plain', 'meta', 'control']) {
    testWidgets('$modifier Enter saves exact editor text', (tester) async {
      String? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showDialog<String>(
                  context: context,
                  builder: (_) => AnnotationEditor(
                    page: page(),
                    kind: AnnotationKind.pageNote,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'one\ntwo');
      if (modifier == 'plain') {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
      } else {
        await chord(
          tester,
          LogicalKeyboardKey.enter,
          control: modifier == 'control',
        );
      }
      expect(saved, 'one\ntwo');
      expect(find.byType(AnnotationEditor), findsNothing);
    });
  }
  testWidgets(
    'Shift Enter keeps the multiline editor open and IME composing Enter never commits a note',
    (tester) async {
      String? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showDialog<String>(
                  context: context,
                  builder: (_) => AnnotationEditor(
                    page: page(),
                    kind: AnnotationKind.region,
                    rect: ContentRect(.1, .1, .5, .5),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'draft');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(find.byType(AnnotationEditor), findsOneWidget);
      expect(saved, isNull);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'pinyin',
          selection: TextSelection.collapsed(offset: 6),
          composing: TextRange(start: 0, end: 6),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(AnnotationEditor), findsOneWidget);
      expect(saved, isNull);
      await chord(tester, LogicalKeyboardKey.enter);
      expect(find.byType(AnnotationEditor), findsOneWidget);
      expect(saved, isNull);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '拼音',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(saved, '拼音');
    },
  );
  testWidgets(
    'inspector search request and scoped find shortcut focus the actual search input',
    (tester) async {
      final session = AnnotationSession();
      var request = 1;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return AnnotationInspector(
                session: session,
                searchRequest: request,
                isCurrent: () => true,
                onOpen: (_) async {},
                onChanged: () {},
                onClose: () {},
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('annotation-search')),
      );
      expect(field.focusNode!.hasFocus, isTrue);
      await tester.enterText(find.byType(TextField), 'draft search');
      field.focusNode!.unfocus();
      await tester.pump();
      rebuild(() => request++);
      await tester.pumpAndSettle();
      expect(field.focusNode!.hasFocus, isTrue);
      await chord(tester, LogicalKeyboardKey.keyF);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'draft search',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('double click opens the selected stable annotation once', (
    tester,
  ) async {
    final session = AnnotationSession();
    final note = session.add(
      session.anchor(chapterId: '1', imageNumber: 1, width: 100, height: 200),
      AnnotationKind.pageNote,
      'Double click note',
    );
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AnnotationInspector(
          session: session,
          isCurrent: () => true,
          onOpen: (note) async => opened.add(note.id),
          onChanged: () {},
          onClose: () {},
        ),
      ),
    );
    await tester.tap(find.text('Double click note'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.text('Double click note'));
    await tester.pumpAndSettle();
    expect(opened, [note.id]);
    expect(tester.takeException(), isNull);
  });
}
