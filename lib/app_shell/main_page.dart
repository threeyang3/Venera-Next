import 'package:venera_next/features/annotations/annotations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:venera_next/features/discovery/discovery.dart';
import 'package:venera_next/features/favorites/favorites.dart';
import 'package:venera_next/features/search/search.dart';
import 'package:venera_next/features/settings/settings.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/application_preferences.dart';
import 'package:venera_next/foundation/global_preference_store.dart';
import 'package:venera_next/foundation/translations.dart';

import '../components/navigation_bar.dart';
import 'package:venera_next/routing/app_navigation.dart';
import '../foundation/context.dart';
import 'home_page.dart';
import 'mac_library_sidebar.dart';
import 'package:venera_next/features/local_comics/local_comics.dart';
import 'package:venera_next/features/favorites/favorites_scope.dart';
import 'package:venera_next/foundation/app.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  bool get _macWorkspace =>
      App.isMacOS &&
      const bool.fromEnvironment('COMICNOTES_POC') &&
      const bool.fromEnvironment('COMICNOTES_WORKSPACE');
  LocalManager? _local;
  LocalFavoritesManager? _favorites;
  String? _selectedTag, _selectedFolder;
  List<String> get _tags => {
    for (final comic in _local?.getComics(LocalSortType.name) ?? <LocalComic>[])
      ...comic.tags.where((tag) => tag.trim().isNotEmpty),
  }.toList()..sort();
  void _libraryChanged() {
    if (!mounted) return;
    setState(() {
      if (_selectedTag != null && !_tags.contains(_selectedTag)) {
        _selectedTag = null;
      }
      if (_selectedFolder != null &&
          !_favorites!.existsFolder(_selectedFolder!)) {
        _selectedFolder = null;
      }
    });
  }

  late final NaviObserver _observer;

  GlobalKey<NavigatorState>? _navigatorKey;

  void to(Widget Function() widget, {bool preventDuplicate = false}) async {
    if (preventDuplicate) {
      var page = widget();
      if ("/${page.runtimeType}" == _observer.routes.last.toString()) return;
    }
    _navigatorKey!.currentContext!.to(widget);
  }

  @override
  void initState() {
    _observer = NaviObserver();
    _navigatorKey = GlobalKey();
    appNavigation.mainNavigatorKey = _navigatorKey;
    index = int.parse(
      GlobalPreferenceStore(
        appdata.settings,
      ).read(DiscoveryPreferences.initialPage),
    );
    if (_macWorkspace) {
      index = 4;
      _local = LocalManager()..addListener(_libraryChanged);
      _favorites = FavoritesScope.read(context)..addListener(_libraryChanged);
    }
    super.initState();
  }

  List<Widget> get _pages => [
    const HomePage(),
    FavoritesPage(
      useLibrarySidebar: _macWorkspace,
      key: const PageStorageKey('favorites'),
      initialLocalFolder: _selectedFolder,
      onFolderChanged: _macWorkspace
          ? (network, folder) =>
                setState(() => _selectedFolder = network ? null : folder)
          : null,
    ),
    const ExplorePage(key: PageStorageKey('explore')),
    const CategoriesPage(key: PageStorageKey('categories')),
    if (_macWorkspace)
      LocalComicsPage(
        key: const PageStorageKey('mac-local-library'),
        libraryRoot: true,
        tagFilter: _selectedTag,
        onImport: _openImport,
      ),
  ];

  @override
  void dispose() {
    _local?.removeListener(_libraryChanged);
    _favorites?.removeListener(_libraryChanged);
    super.dispose();
  }

  bool _importOpen = false;
  Future<void> _openImport() async {
    if (!mounted || _importOpen || ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    _importOpen = true;
    try {
      await showLocalComicImportDialog(appNavigation.rootContext);
    } finally {
      _importOpen = false;
    }
  }

  var index = 0;

  @override
  Widget build(BuildContext context) {
    final pane = NaviPane(
      initialPage: index,
      observer: _observer,
      navigatorKey: _navigatorKey!,
      contentRevision: (_selectedFolder, _selectedTag),
      expandedSidebarBreakpoint: _macWorkspace ? 980 : null,
      expandedSidebarBuilder: _macWorkspace
          ? (context, pane) => MacLibrarySidebar(
              items: pane.widget.paneItems,
              selected: index,
              folders: _favorites!.folderNames,
              tags: _tags,
              selectedFolder: _selectedFolder,
              selectedTag: _selectedTag,
              onSelect: (value) {
                setState(() {
                  _selectedFolder = null;
                  _selectedTag = null;
                });
                pane.updatePage(value);
              },
              onFolder: (folder) {
                pane.updatePage(1);
                setState(() {
                  _selectedTag = null;
                  _selectedFolder = folder;
                });
              },
              onTag: (tag) {
                pane.updatePage(4);
                setState(() {
                  _selectedFolder = null;
                  _selectedTag = tag;
                });
              },
              onImport: _openImport,
              onRestore:
                  AnnotationServicesScope.maybeOf(context)?.prepareRestore ==
                      null
                  ? null
                  : () => showAnnotationRestoreDialog(context),
              onSettings: () =>
                  to(() => const SettingsPage(), preventDuplicate: true),
            )
          : null,
      paneItems: [
        PaneItemEntry(
          label: 'Home'.tl,
          icon: Icons.home_outlined,
          activeIcon: Icons.home,
        ),
        PaneItemEntry(
          label: 'Favorites'.tl,
          icon: Icons.local_activity_outlined,
          activeIcon: Icons.local_activity,
        ),
        PaneItemEntry(
          label: 'Explore'.tl,
          icon: Icons.explore_outlined,
          activeIcon: Icons.explore,
        ),
        PaneItemEntry(
          label: 'Categories'.tl,
          icon: Icons.category_outlined,
          activeIcon: Icons.category,
        ),
        if (_macWorkspace)
          PaneItemEntry(
            label: '本地书库',
            icon: Icons.library_books_outlined,
            activeIcon: Icons.library_books,
          ),
      ],
      onPageChanged: (i) {
        setState(() {
          index = i;
          _selectedTag = null;
          _selectedFolder = null;
        });
      },
      paneActions: [
        if (_macWorkspace &&
            AnnotationServicesScope.maybeOf(context)?.prepareRestore != null)
          PaneActionEntry(
            icon: Icons.restore_outlined,
            label: '恢复批注备份',
            onTap: () => showAnnotationRestoreDialog(context),
          ),
        if (index != 0)
          PaneActionEntry(
            icon: Icons.search,
            label: "Search".tl,
            onTap: () {
              to(() => const SearchPage(), preventDuplicate: true);
            },
          ),
        PaneActionEntry(
          icon: Icons.settings,
          label: "Settings".tl,
          onTap: () {
            to(() => const SettingsPage(), preventDuplicate: true);
          },
        ),
      ],
      pageBuilder: (index) {
        return _pages[index];
      },
    );
    if (!_macWorkspace) return pane;
    final base = Theme.of(context),
        dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = base.colorScheme.copyWith(
      primary: dark ? const Color(0xff0a84ff) : const Color(0xff007aff),
      primaryContainer: dark
          ? const Color(0xff163c68)
          : const Color(0xffdeedff),
      onPrimaryContainer: dark
          ? const Color(0xfff5f5f7)
          : const Color(0xff1d1d1f),
      secondaryContainer: dark
          ? const Color(0xff3c3c40)
          : const Color(0xffe7e7ec),
      surface: dark ? const Color(0xff1c1c1e) : const Color(0xfffafafa),
      surfaceContainerLow: dark
          ? const Color(0xff252527)
          : const Color(0xfff5f5f7),
      surfaceContainerHigh: dark
          ? const Color(0xff303033)
          : const Color(0xffededf0),
      surfaceTint: Colors.transparent,
      outlineVariant: dark ? const Color(0xff414145) : const Color(0xffdcdce1),
    );
    return Theme(
      data: base.copyWith(
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
      ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyO, meta: true):
              _openImport,
          const SingleActivator(LogicalKeyboardKey.keyO, control: true):
              _openImport,
        },
        child: Focus(autofocus: true, child: pane),
      ),
    );
  }
}
