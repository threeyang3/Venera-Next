import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/app_shell/import_commands.dart';

void main() {
  testWidgets(
    'root open command follows pushed routes and respects popups and admission',
    (tester) async {
      final routes = ImportCommandRoutes();
      final navigator = GlobalKey<NavigatorState>();
      var allowed = true, opens = 0;
      final textFocus = FocusNode();
      addTearDown(textFocus.dispose);
      Future<void> command({bool control = false}) async {
        final modifier = control
            ? LogicalKeyboardKey.controlLeft
            : LogicalKeyboardKey.metaLeft;
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [routes],
          builder: (_, child) => ImportCommands(
            routes: routes,
            canOpen: () => allowed,
            open: () async {
              opens++;
              await showDialog<void>(
                context: navigator.currentContext!,
                builder: (context) => AlertDialog(
                  title: const Text('Import existing files'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              );
            },
            child: child!,
          ),
          home: const Scaffold(body: Text('Library')),
        ),
      );
      await command();
      expect(opens, 1);
      await command();
      expect(opens, 1);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: TextField(focusNode: textFocus, autofocus: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Reader search stays');
      await command(control: true);
      expect(opens, 2);
      expect(find.text('Import existing files'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Reader search stays'), findsOneWidget);
      unawaited(
        showDialog<void>(
          context: navigator.currentContext!,
          builder: (_) => const AlertDialog(title: Text('Editing note')),
        ),
      );
      await tester.pumpAndSettle();
      await command();
      expect(opens, 2);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      allowed = false;
      textFocus.requestFocus();
      await tester.pump();
      await command();
      expect(opens, 2);
      allowed = true;
      await command();
      expect(opens, 3);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pending open cannot repeat before a popup route is created', (
    tester,
  ) async {
    final routes = ImportCommandRoutes();
    final pending = Completer<void>();
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [routes],
        builder: (_, child) => ImportCommands(
          routes: routes,
          canOpen: () => true,
          open: () {
            opens++;
            return pending.future;
          },
          child: child!,
        ),
        home: const Scaffold(body: Text('Reader')),
      ),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(opens, 1);
    pending.complete();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
