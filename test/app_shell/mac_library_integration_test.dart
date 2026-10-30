import 'dart:async';
import 'dart:convert';
import 'package:venera_next/app_shell/import_commands.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:venera_next/app_shell/main_page.dart';
import 'package:venera_next/app_shell/mac_library_sidebar.dart';
import 'package:venera_next/components/navigation_bar.dart';
import 'package:venera_next/components/settings_save_state.dart';
import 'package:venera_next/features/comic_widgets/comic_list.dart';
import 'package:venera_next/features/comic_widgets/comic_tile.dart';
import 'package:venera_next/features/favorites/favorites_scope.dart';
import 'package:venera_next/features/favorites/favorites_manager.dart';
import 'package:venera_next/features/favorites/local_favorites_page.dart';
import 'package:venera_next/features/favorites/favorites_page.dart';
import 'package:venera_next/features/local_comics/local_comics.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/routing/app_navigation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LocalFavoritesManager favorites;
  late AppdataImportCheckpoint before;
  setUpAll(() async {
    final font = Platform.environment['COMICNOTES_LIBRARY_QA_FONT'];
    if (font != null) {
      await (FontLoader(
        'LibraryQA',
      )..addFont(File(font).readAsBytes().then(ByteData.sublistView))).load();
      await (FontLoader('MaterialIcons')..addFont(
            File(
              'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            File(
              'build/unit_test_assets/packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  setUp(() async {
    before = appdata.captureImportCheckpoint();
    root = Directory.systemTemp.createTempSync('mac-library-');
    App.dataPath = root.path;
    App.cachePath = root.path;
    appdata.settings['language'] = 'en-US';
    appdata.settings['initialPage'] = '1';
    appdata.settings['favoriteFolder'] = null;
    appdata.implicitData.remove('favoriteFolder');
    appdata.implicitData['local_sort'] = 'name';
    appdata.implicitData.remove('mac_library_view');
    LocalManager.current?.dispose();
    await LocalManager(initializeSources: () async {}).init();
    configureComicWidgets(
      tileImageProviderResolver: (comic) =>
          FileImage(LocalManager().find(comic.id, ComicType.local)!.coverFile),
    );
    favorites = LocalFavoritesManager();
    await favorites.init();
    await favorites.createFolder('Observations');
    await favorites.createFolder('Panels');
    for (final (i, tag) in ['Composition', 'Character'].indexed) {
      final directory = Directory('${LocalManager().path}/book$i')
        ..createSync(recursive: true);
      final pixels = image.Image(width: 240, height: 360);
      for (var y = 0; y < 360; y++) {
        for (var x = 0; x < 240; x++) {
          final panel = (x < 110 ? 0 : 1) + (y < 170 ? 0 : 2);
          pixels.setPixelRgb(
            x,
            y,
            30 + i * 35 + panel * 25,
            45 + panel * 25,
            70 + i * 40 + panel * 10,
          );
        }
      }
      File(
        '${directory.path}/cover.png',
      ).writeAsBytesSync(image.encodePng(pixels));
      final comic = LocalComic(
        id: 'book$i',
        title: 'Book $i',
        subtitle: '',
        tags: [tag],
        directory: 'book$i',
        cover: 'cover.png',
        comicType: ComicType.local,
        chapters: null,
        downloadedChapters: const [],
        createdAt: DateTime(2026, 10, 29, i),
      );
      await LocalManager().add(comic, comic.id);
    }
  });
  tearDown(() async {
    configureComicWidgets();
    await LocalManager().pendingDownloadTaskWrites;
    LocalManager.current?.dispose();
    await favorites.closeAndWait();
    await appdata.writeImplicitData();
    await appdata.restoreImportCheckpoint(before, persist: false);
    appNavigation.mainNavigatorKey = null;
    root.deleteSync(recursive: true);
  });
  testWidgets(
    'actual Mac library filters tags, retains navigator on resize and opens existing import dialog',
    (tester) async {
      Future<void> settle() async {
        for (var i = 0; i < 250; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          final saving = tester
              .stateList<SettingsSaveState>(find.byType(FavoritesPage))
              .any((state) => state.savingSettings);
          if (!saving && !tester.binding.hasScheduledFrame) return;
        }
        expect(
          tester
              .stateList<SettingsSaveState>(find.byType(FavoritesPage))
              .any((state) => state.savingSettings),
          isFalse,
        );
        await tester.pumpAndSettle();
      }

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final importRoutes = ImportCommandRoutes();
      await tester.pumpWidget(
        FavoritesScope(
          manager: favorites,
          child: MaterialApp(
            theme: ThemeData(
              brightness:
                  Platform.environment['COMICNOTES_LIBRARY_QA_DARK'] == 'true'
                  ? Brightness.dark
                  : Brightness.light,
              fontFamily:
                  Platform.environment['COMICNOTES_LIBRARY_QA_FONT'] == null
                  ? null
                  : 'LibraryQA',
            ),
            navigatorKey: appNavigation.rootNavigatorKey,
            navigatorObservers: [importRoutes],
            builder: (_, child) => ImportCommands(
              routes: importRoutes,
              canOpen: () => true,
              open: () => showLocalComicImportDialog(appNavigation.rootContext),
              child: child!,
            ),
            home: const MainPage(),
          ),
        ),
      );
      await settle();
      expect(tester.takeException(), isNull);
      expect(find.byType(MacLibrarySidebar), findsOneWidget);
      expect(find.byType(LocalComicsPage), findsOneWidget);
      List<String> ids() => tester
          .widget<SliverGridComics>(find.byType(SliverGridComics))
          .comics
          .map((comic) => comic.id)
          .toList();
      expect(ids(), ['book1', 'book0']);
      await tester.tap(find.byTooltip('切换列表视图'));
      await settle();
      expect(
        tester
            .widget<SliverGridComics>(find.byType(SliverGridComics))
            .displayMode,
        ComicTileDisplayMode.compactList,
      );
      final firstRow = tester.getRect(find.text('Book 0'));
      final secondRow = tester.getRect(find.text('Book 1'));
      expect(firstRow.left, secondRow.left);
      expect((firstRow.top - secondRow.top).abs(), greaterThan(50));
      await tester.runAsync(() async {
        await appdata.writeImplicitData();
        final saved = jsonDecode(
          await File('${root.path}/implicitData.json').readAsString(),
        );
        expect(saved['mac_library_view'], 'list');
      });
      await tester.tap(find.widgetWithText(ListTile, 'Favorites'));
      await settle();
      await tester.tap(find.widgetWithText(ListTile, '本地书库'));
      await settle();
      expect(
        tester
            .widget<SliverGridComics>(find.byType(SliverGridComics))
            .displayMode,
        ComicTileDisplayMode.compactList,
      );
      await tester.tap(find.byTooltip('切换封面视图'));
      await settle();
      expect(
        tester
            .widget<SliverGridComics>(find.byType(SliverGridComics))
            .displayMode,
        ComicTileDisplayMode.gallery,
      );
      final librarySearch = find.widgetWithText(TextField, '搜索书库');
      expect(librarySearch, findsOneWidget);
      await tester.enterText(librarySearch, 'no-matching-book');
      await settle();
      expect(find.text('0 本漫画'), findsOneWidget);
      expect(find.text('Book 0'), findsNothing);
      expect(find.text('Book 1'), findsNothing);
      await tester.tap(find.byTooltip('清除搜索'));
      await settle();
      expect(ids(), ['book1', 'book0']);
      final qaDirectory = Platform.environment['COMICNOTES_LIBRARY_QA_DIR'];
      if (qaDirectory != null) {
        final listPreview =
            Platform.environment['COMICNOTES_LIBRARY_QA_LIST'] == 'true';
        if (listPreview) {
          await tester.tap(find.byTooltip('切换列表视图'));
          await settle();
        }
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byType(RepaintBoundary).first,
          );
          final snapshot = await boundary.toImage(pixelRatio: 1);
          try {
            final bytes = await snapshot.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(qaDirectory).create(recursive: true);
            await File(
              '$qaDirectory/library-${listPreview ? 'list-' : ''}${Platform.environment['COMICNOTES_LIBRARY_QA_DARK'] == 'true' ? 'dark' : 'light'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            snapshot.dispose();
          }
        });
        if (listPreview) {
          await tester.tap(find.byTooltip('切换封面视图'));
          await settle();
        }
      }
      await tester.tap(
        find.descendant(
          of: find.byType(MacLibrarySidebar),
          matching: find.text('Observations'),
        ),
      );
      await settle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<LocalFavoritesPage>(find.byType(LocalFavoritesPage))
            .folder,
        'Observations',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(MacLibrarySidebar),
          matching: find.text('Panels'),
        ),
      );
      await tester.pump();
      final saving = tester.state<SettingsSaveState>(
        find.byType(FavoritesPage),
      );
      for (var i = 0; i < 200 && saving.savingSettings; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(saving.savingSettings, isFalse);
      await settle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<LocalFavoritesPage>(find.byType(LocalFavoritesPage))
            .folder,
        'Panels',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(MacLibrarySidebar),
          matching: find.text('本地书库'),
        ),
      );
      await settle();
      expect(tester.takeException(), isNull);
      final navigator = appNavigation.mainNavigatorKey!.currentState;
      await tester.longPress(find.text('Book 1'));
      await settle();
      expect(
        tester
            .widget<SliverGridComics>(find.byType(SliverGridComics))
            .selections,
        hasLength(1),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(MacLibrarySidebar),
          matching: find.text('Composition'),
        ),
      );
      await settle();
      expect(tester.takeException(), isNull);
      expect(ids(), ['book0']);
      expect(
        tester
            .widget<SliverGridComics>(find.byType(SliverGridComics))
            .selections,
        isEmpty,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(MacLibrarySidebar),
          matching: find.text('Character'),
        ),
      );
      await settle();
      expect(tester.takeException(), isNull);
      expect(ids(), ['book1']);
      expect(appNavigation.mainNavigatorKey!.currentState, same(navigator));
      final changed = LocalManager().find('book1', ComicType.local)!;
      await tester.runAsync(
        () => LocalManager().add(
          LocalComic(
            id: changed.id,
            title: changed.title,
            subtitle: changed.subtitle,
            tags: const ['Updated'],
            directory: changed.directory,
            chapters: changed.chapters,
            cover: changed.cover,
            comicType: changed.comicType,
            downloadedChapters: changed.downloadedChapters,
            createdAt: changed.createdAt,
          ),
          changed.id,
        ),
      );
      await settle();
      expect(ids(), ['book1', 'book0']);
      expect(
        find.descendant(
          of: find.byType(MacLibrarySidebar),
          matching: find.text('Character'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(MacLibrarySidebar),
          matching: find.text('Updated'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(MacLibrarySidebar),
          matching: find.text('本地书库'),
        ),
      );
      await settle();
      expect(tester.takeException(), isNull);
      expect(ids(), ['book1', 'book0']);
      await tester.tap(
        find.descendant(
          of: find.byType(MacLibrarySidebar),
          matching: find.text('导入漫画'),
        ),
      );
      await settle();
      expect(tester.takeException(), isNull);
      expect(find.text('Import Comics'), findsOneWidget);
      appNavigation.rootNavigatorKey.currentState!.pop();
      await settle();
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(700, 900);
      await settle();
      expect(tester.takeException(), isNull);
      expect(find.byType(MacLibrarySidebar), findsNothing);
      expect(appNavigation.mainNavigatorKey!.currentState, same(navigator));
      expect(tester.state<NaviPaneState>(find.byType(NaviPane)).currentPage, 4);
      expect(ids(), ['book1', 'book0']);
      expect(tester.takeException(), isNull);
      Future<void> command(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await settle();
      }

      Focus.of(tester.element(find.byType(SliverGridComics))).requestFocus();
      await tester.pump();
      await command(LogicalKeyboardKey.keyF);
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
      await tester.enterText(find.byType(TextField), 'Book 0');
      await settle();
      expect(ids(), ['book0']);
      await command(LogicalKeyboardKey.keyF);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 6),
      );
      await command(LogicalKeyboardKey.keyO);
      expect(find.text('Import Comics'), findsOneWidget);
      await command(LogicalKeyboardKey.keyO);
      expect(find.text('Import Comics'), findsOneWidget);
      appNavigation.rootNavigatorKey.currentState!.pop();
      await settle();
      expect(ids(), ['book0']);
      unawaited(
        appNavigation.rootNavigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: TextField(autofocus: true)),
          ),
        ),
      );
      await settle();
      await tester.enterText(find.byType(TextField), 'Reader page search');
      await command(LogicalKeyboardKey.keyO);
      expect(find.text('Import Comics'), findsOneWidget);
      final repeated = showLocalComicImportDialog(appNavigation.rootContext);
      await command(LogicalKeyboardKey.keyO);
      expect(find.text('Import Comics'), findsOneWidget);
      appNavigation.rootNavigatorKey.currentState!.pop();
      await settle();
      await repeated;
      expect(find.text('Reader page search'), findsOneWidget);
      appNavigation.rootNavigatorKey.currentState!.pop();
      await settle();
      expect(ids(), ['book0']);
      await tester.enterText(find.byType(TextField), '');
      await settle();
      expect(ids(), ['book1', 'book0']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle();
      expect(tester.takeException(), isNull);
    },
    skip:
        !Platform.isMacOS ||
        !const bool.fromEnvironment('COMICNOTES_POC') ||
        !const bool.fromEnvironment('COMICNOTES_WORKSPACE'),
  );

  testWidgets(
    'disabled workspace preserves original destinations and saved initial page',
    (tester) async {
      await tester.pumpWidget(
        FavoritesScope(
          manager: favorites,
          child: MaterialApp(
            navigatorKey: appNavigation.rootNavigatorKey,
            home: const MainPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MacLibrarySidebar), findsNothing);
      final pane = tester.widget<NaviPane>(find.byType(NaviPane));
      expect(pane.paneItems, hasLength(4));
      expect(pane.expandedSidebarBuilder, isNull);
      expect(tester.state<NaviPaneState>(find.byType(NaviPane)).currentPage, 1);
      expect(find.byType(LocalComicsPage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    skip:
        Platform.isMacOS &&
        const bool.fromEnvironment('COMICNOTES_POC') &&
        const bool.fromEnvironment('COMICNOTES_WORKSPACE'),
  );
}
