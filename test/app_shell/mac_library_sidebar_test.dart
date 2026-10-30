import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/app_shell/mac_library_sidebar.dart';
import 'package:venera_next/components/navigation_bar.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'library sidebar selects labels and actions at large text; dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final actions = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 224,
                child: MacLibrarySidebar(
                  items: [
                    for (final name in ['首页', '收藏', '发现', '分类', '本地书库'])
                      PaneItemEntry(
                        label: name,
                        icon: Icons.book_outlined,
                        activeIcon: Icons.book,
                      ),
                  ],
                  selected: 4,
                  folders: const ['观察笔记'],
                  tags: const ['构图'],
                  selectedTag: '构图',
                  onSelect: (i) => actions.add('page:$i'),
                  onFolder: (value) => actions.add('folder:$value'),
                  onTag: (value) => actions.add('tag:$value'),
                  onImport: () => actions.add('import'),
                  onSettings: () => actions.add('settings'),
                  onRestore: () => actions.add('restore'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('本地书库'));
        await tester.tap(find.text('观察笔记'));
        await tester.ensureVisible(find.text('构图'));
        await tester.tap(find.text('构图'));
        await tester.tap(find.text('导入漫画'));
        await tester.tap(find.text('设置'));
        await tester.tap(find.text('恢复批注备份'));
        expect(actions, [
          'page:4',
          'folder:观察笔记',
          'tag:构图',
          'import',
          'settings',
          'restore',
        ]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'content revision updates the same nested navigator and returns from a pushed route',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final navigator = GlobalKey<NavigatorState>();
      final pane = GlobalKey<NaviPaneState>();
      final observer = NaviObserver();
      final revision = ValueNotifier('first');
      addTearDown(revision.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<String>(
            valueListenable: revision,
            builder: (context, value, _) => NaviPane(
              key: pane,
              navigatorKey: navigator,
              observer: observer,
              paneItems: [
                PaneItemEntry(
                  label: 'Library',
                  icon: Icons.book,
                  activeIcon: Icons.book,
                ),
              ],
              paneActions: const [],
              pageBuilder: (_) => Text(value),
              contentRevision: value,
              expandedSidebarBreakpoint: 980,
              expandedSidebarBuilder: (_, state) => Material(
                child: TextButton(
                  onPressed: () => state.updatePage(0),
                  child: const Text('Library sidebar'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = navigator.currentState;
      expect(find.text('Library sidebar'), findsOneWidget);
      expect(find.text('first'), findsOneWidget);
      revision.value = 'second';
      await tester.pumpAndSettle();
      expect(navigator.currentState, same(state));
      expect(find.text('second'), findsOneWidget);
      final route = MaterialPageRoute<void>(
        builder: (_) => const Text('Detail'),
      );
      navigator.currentState!.push(route);
      await tester.pumpAndSettle();
      expect(find.text('Detail'), findsOneWidget);
      await tester.tap(find.text('Library sidebar'));
      await tester.pumpAndSettle();
      expect(find.text('Detail'), findsNothing);
      expect(find.text('second'), findsOneWidget);
      tester.view.physicalSize = const Size(700, 800);
      await tester.pumpAndSettle();
      expect(find.text('Library sidebar'), findsNothing);
      expect(navigator.currentState, same(state));
      expect(find.text('second'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
