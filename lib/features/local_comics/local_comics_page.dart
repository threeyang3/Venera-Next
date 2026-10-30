import 'import_export/comic_export_service.dart';
import 'package:venera_next/components/window_selection_task.dart';
import 'package:venera_next/foundation/selection_operation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoIcons, CupertinoSlidingSegmentedControl;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:venera_next/routing/local_reading.dart';
import 'package:venera_next/components/appbar.dart';
import 'package:venera_next/components/button.dart';
import 'package:venera_next/components/menu.dart';
import 'package:venera_next/components/message.dart';
import 'package:venera_next/components/pop_up_widget.dart';
import 'package:venera_next/components/scroll.dart';
import 'package:venera_next/features/comic_widgets/comic_widgets.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/routing/app_navigation.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/features/local_comics/downloading_page.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/features/comic_details/comic_details.dart';
import 'package:venera_next/features/favorites/favorites.dart';
import 'package:venera_next/features/local_comics/import_export/import_export.dart';
import 'package:venera_next/features/sync/sync.dart';
import 'package:venera_next/foundation/file_interaction.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:zip_flutter/zip_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

class LocalComicsPage extends StatefulWidget {
  const LocalComicsPage({
    super.key,
    this.libraryRoot = false,
    this.tagFilter,
    this.onImport,
  });
  final bool libraryRoot;
  final String? tagFilter;
  final VoidCallback? onImport;

  @override
  State<LocalComicsPage> createState() => _LocalComicsPageState();
}

class _LocalComicsPageState extends State<LocalComicsPage> {
  late List<LocalComic> comics;

  late LocalSortType sortType;

  String keyword = "";

  bool searchMode = false;
  bool _galleryView = true;
  int _viewSaveRevision = 0;
  Future<void> _setGalleryView(bool value) async {
    if (_galleryView == value) return;
    setState(() => _galleryView = value);
    final revision = ++_viewSaveRevision;
    try {
      await appdata.updateImplicit((draft) {
        draft['mac_library_view'] = value ? 'gallery' : 'list';
      });
    } catch (error, stack) {
      Log.error('Local library view', error, stack);
      if (mounted && revision == _viewSaveRevision) {
        context.showMessage(message: '视图已切换，但未能记住选择。请稍后重新切换以重试。');
      }
    }
  }

  final _searchText = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Local library search');
  void _openSearch() {
    if (!mounted ||
        multiSelectMode ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    setState(() => searchMode = !widget.libraryRoot);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (searchMode || widget.libraryRoot)) {
        _searchFocus.requestFocus();
        if (widget.libraryRoot) {
          _searchText.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _searchText.text.length,
          );
        }
      }
    });
  }

  bool multiSelectMode = false;

  Map<LocalComic, bool> selectedComics = {};

  void update() {
    if (keyword.isEmpty) {
      setState(() {
        comics = LocalManager().getComics(sortType);
        _applyTag();
      });
    } else {
      setState(() {
        comics = LocalManager().search(keyword);
        _applyTag();
      });
    }
  }

  void _applyTag() {
    if (widget.tagFilter case final tag?) {
      comics = comics.where((comic) => comic.tags.contains(tag)).toList();
    }
  }

  @override
  void didUpdateWidget(LocalComicsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tagFilter != widget.tagFilter) {
      multiSelectMode = false;
      selectedComics.clear();
      update();
    }
  }

  @override
  void initState() {
    if (widget.libraryRoot) {
      _galleryView = appdata.implicitData['mac_library_view'] != 'list';
    }
    var sort = appdata.implicitData["local_sort"] ?? "name";
    sortType = LocalSortType.fromString(sort);
    comics = LocalManager().getComics(sortType);
    _applyTag();
    LocalManager().addListener(update);
    super.initState();
  }

  @override
  void dispose() {
    LocalManager().removeListener(update);
    _searchFocus.dispose();
    _searchText.dispose();
    super.dispose();
  }

  void sort() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return ContentDialog(
              title: "Sort".tl,
              content: RadioGroup<LocalSortType>(
                groupValue: sortType,
                onChanged: (v) {
                  setState(() {
                    sortType = v ?? sortType;
                  });
                },
                child: Column(
                  children: [
                    RadioListTile<LocalSortType>(
                      title: Text("Name".tl),
                      value: LocalSortType.name,
                    ),
                    RadioListTile<LocalSortType>(
                      title: Text("Date".tl),
                      value: LocalSortType.timeAsc,
                    ),
                    RadioListTile<LocalSortType>(
                      title: Text("Date Desc".tl),
                      value: LocalSortType.timeDesc,
                    ),
                  ],
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () {
                    appdata.implicitData["local_sort"] = sortType.value;
                    appdata.writeImplicitData();
                    Navigator.pop(context);
                    update();
                  },
                  child: Text("Confirm".tl),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget buildMultiSelectMenu() {
    final selection = selectedComics.keys.toList();
    bool currentSelection() =>
        mounted &&
        multiSelectMode &&
        listEquals(selectedComics.keys.toList(), selection);
    return MenuButton(
      entries: [
        MenuEntry(
          icon: Icons.delete_outline,
          text: "Delete".tl,
          onClick: () {
            deleteComics(selectedComics.keys.toList()).then((value) {
              if (value) {
                setState(() {
                  multiSelectMode = false;
                  selectedComics.clear();
                });
              }
            });
          },
        ),
        MenuEntry(
          icon: Icons.favorite_border,
          text: "Add to favorites".tl,
          onClick: () {
            if (!currentSelection()) return;
            addFavorite(context, selection, isCurrent: currentSelection);
          },
        ),
        if (selectedComics.length == 1)
          MenuEntry(
            icon: Icons.folder_open,
            text: "Open Folder".tl,
            onClick: () {
              if (!currentSelection()) return;
              openComicFolder(context, selection.single);
            },
          ),
        if (selectedComics.length == 1)
          MenuEntry(
            icon: Icons.chrome_reader_mode_outlined,
            text: "View Detail".tl,
            onClick: () {
              context.to(
                () => ComicPage(
                  id: selectedComics.keys.first.id,
                  sourceKey: selectedComics.keys.first.sourceKey,
                ),
              );
            },
          ),
        if (selectedComics.isNotEmpty)
          MenuEntry(
            icon: Icons.cloud_upload_outlined,
            text: "Archive to WebDAV".tl,
            onClick: () {
              archiveComics(selectedComics.keys.toList()).then((value) {
                if (value) {
                  setState(() {
                    multiSelectMode = false;
                    selectedComics.clear();
                  });
                }
              });
            },
          ),
        if (selectedComics.isNotEmpty)
          ...exportActions(selectedComics.keys.toList()),
      ],
    );
  }

  void selectAll() {
    setState(() {
      selectedComics = comics.asMap().map((k, v) => MapEntry(v, true));
    });
  }

  void deSelect() {
    setState(() {
      selectedComics.clear();
    });
  }

  void invertSelection() {
    setState(() {
      comics.asMap().forEach((k, v) {
        selectedComics[v] = !selectedComics.putIfAbsent(v, () => false);
      });
      selectedComics.removeWhere((k, v) => !v);
    });
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> selectActions = [
      IconButton(
        icon: const Icon(Icons.select_all),
        tooltip: "Select All".tl,
        onPressed: selectAll,
      ),
      IconButton(
        icon: const Icon(Icons.deselect),
        tooltip: "Deselect".tl,
        onPressed: deSelect,
      ),
      IconButton(
        icon: const Icon(Icons.flip),
        tooltip: "Invert Selection".tl,
        onPressed: invertSelection,
      ),
      buildMultiSelectMenu(),
    ];

    List<Widget> normalActions = [
      if (widget.onImport != null)
        IconButton(
          tooltip: '导入漫画',
          icon: Icon(
            widget.libraryRoot ? CupertinoIcons.plus : Icons.add_box_outlined,
          ),
          onPressed: widget.onImport,
        ),
      const PdfImportTasksButton(),
      if (!widget.libraryRoot)
        Tooltip(
          message: "Search".tl,
          child: IconButton(
            icon: const Icon(Icons.search),
            onPressed: _openSearch,
          ),
        ),
      Tooltip(
        message: "Sort".tl,
        child: IconButton(
          icon: Icon(
            widget.libraryRoot
                ? CupertinoIcons.line_horizontal_3_decrease
                : Icons.sort,
          ),
          onPressed: sort,
        ),
      ),
      Tooltip(
        message: "Downloading".tl,
        child: IconButton(
          icon: const Icon(Icons.download),
          onPressed: () {
            showPopUpWidget(context, const DownloadingPage());
          },
        ),
      ),
    ];

    var body = Scaffold(
      body: SmoothCustomScrollView(
        slivers: [
          if (widget.libraryRoot)
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).dividerColor,
                        width: .5,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (multiSelectMode) ...[
                        IconButton(
                          onPressed: () => setState(() {
                            multiSelectMode = false;
                            selectedComics.clear();
                          }),
                          icon: const Icon(CupertinoIcons.xmark),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              multiSelectMode
                                  ? '已选择 ${selectedComics.length} 本'
                                  : widget.tagFilter ?? '本地书库',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${comics.length} 本漫画',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (!multiSelectMode) ...[
                        SizedBox(
                          width: (MediaQuery.sizeOf(context).width * .2).clamp(
                            140,
                            230,
                          ),
                          height: 30,
                          child: TextField(
                            controller: _searchText,
                            focusNode: _searchFocus,
                            style: const TextStyle(fontSize: 12),
                            decoration: InputDecoration(
                              hintText: '搜索书库',
                              prefixIcon: const Icon(
                                CupertinoIcons.search,
                                size: 14,
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 30,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              suffixIcon: keyword.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: '清除搜索',
                                      icon: const Icon(
                                        CupertinoIcons.xmark_circle_fill,
                                        size: 13,
                                      ),
                                      onPressed: () {
                                        _searchText.clear();
                                        keyword = '';
                                        update();
                                      },
                                    ),
                            ),
                            onChanged: (value) {
                              keyword = value;
                              update();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        CupertinoSlidingSegmentedControl<bool>(
                          groupValue: _galleryView,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: .06),
                          thumbColor:
                              Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xff555555)
                              : Colors.white,
                          children: const {
                            true: Tooltip(
                              message: '切换封面视图',
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 5),
                                child: Icon(
                                  CupertinoIcons.square_grid_2x2,
                                  size: 16,
                                ),
                              ),
                            ),
                            false: Tooltip(
                              message: '切换列表视图',
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 5),
                                child: Icon(
                                  CupertinoIcons.rectangle_grid_1x2,
                                  size: 16,
                                ),
                              ),
                            ),
                          },
                          onValueChanged: (value) {
                            if (value != null) {
                              _setGalleryView(value);
                            }
                          },
                        ),
                        const SizedBox(width: 6),
                      ],
                      ...multiSelectMode ? selectActions : normalActions,
                    ],
                  ),
                ),
              ),
            )
          else if (!searchMode)
            SliverAppbar(
              leading: widget.libraryRoot && !multiSelectMode
                  ? null
                  : Tooltip(
                      message: multiSelectMode ? "Cancel".tl : "Back".tl,
                      child: IconButton(
                        onPressed: () {
                          if (multiSelectMode) {
                            setState(() {
                              multiSelectMode = false;
                              selectedComics.clear();
                            });
                          } else {
                            context.pop();
                          }
                        },
                        icon: multiSelectMode
                            ? const Icon(Icons.close)
                            : const Icon(Icons.arrow_back),
                      ),
                    ),
              title: multiSelectMode
                  ? Text(selectedComics.length.toString())
                  : Text(widget.tagFilter ?? "Local".tl),
              actions: multiSelectMode ? selectActions : normalActions,
            )
          else if (searchMode)
            SliverAppbar(
              leading: Tooltip(
                message: multiSelectMode ? "Cancel".tl : "Cancel".tl,
                child: IconButton(
                  icon: multiSelectMode
                      ? const Icon(Icons.close)
                      : const Icon(Icons.close),
                  onPressed: () {
                    if (multiSelectMode) {
                      setState(() {
                        multiSelectMode = false;
                        selectedComics.clear();
                      });
                    } else {
                      setState(() {
                        searchMode = false;
                        keyword = "";
                        update();
                      });
                    }
                  },
                ),
              ),
              title: multiSelectMode
                  ? Text(selectedComics.length.toString())
                  : TextField(
                      focusNode: _searchFocus,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: "Search".tl,
                        border: InputBorder.none,
                      ),
                      onChanged: (v) {
                        keyword = v;
                        update();
                      },
                    ),
              actions: multiSelectMode ? selectActions : null,
            ),
          if (widget.libraryRoot && comics.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        keyword.isEmpty
                            ? CupertinoIcons.book
                            : CupertinoIcons.search,
                        size: 40,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: .5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        keyword.isEmpty ? '开始你的漫画书库' : '没有找到漫画',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        keyword.isEmpty
                            ? '导入漫画，阅读时随手记录值得回看的画面。'
                            : '试试其他书名，或清除搜索。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (keyword.isEmpty && widget.onImport != null) ...[
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: widget.onImport,
                          icon: const Icon(CupertinoIcons.plus, size: 14),
                          label: const Text('导入第一本漫画'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            )
          else
            SliverGridComics(
              comics: comics,
              displayMode: widget.libraryRoot
                  ? (_galleryView
                        ? ComicTileDisplayMode.gallery
                        : ComicTileDisplayMode.compactList)
                  : null,
              listSubtitleBuilder: widget.libraryRoot
                  ? (comic) {
                      final local = comic as LocalComic;
                      final date = local.createdAt;
                      return [
                        if (local.subtitle.trim().isNotEmpty)
                          local.subtitle.trim(),
                        if (local.tags.isNotEmpty) local.tags.take(3).join('、'),
                        '添加于 ${date.year}/${date.month}/${date.day}',
                      ].join(' · ');
                    }
                  : null,
              galleryColumns: widget.libraryRoot && _galleryView
                  ? (MediaQuery.sizeOf(context).width ~/ 220).clamp(2, 8)
                  : null,
              selections: selectedComics,
              onLongPressed: (c, heroID) {
                setState(() {
                  multiSelectMode = true;
                  selectedComics[c as LocalComic] = true;
                });
              },
              onTap: (c, heroID) {
                if (multiSelectMode) {
                  setState(() {
                    if (selectedComics.containsKey(c as LocalComic)) {
                      selectedComics.remove(c);
                    } else {
                      selectedComics[c] = true;
                    }
                    if (selectedComics.isEmpty) {
                      multiSelectMode = false;
                    }
                  });
                } else {
                  // prevent dirty data
                  var comic = LocalManager().find(
                    c.id,
                    ComicType.fromKey(c.sourceKey),
                  )!;
                  openLocalComic(comic);
                }
              },
              menuBuilder: (c) {
                return [
                  MenuEntry(
                    icon: Icons.watch_later_outlined,
                    text:
                        LocalFavoritesManager().isInReadLater(
                          c.id,
                          (c as LocalComic).comicType,
                        )
                        ? 'Remove from read later'.tl
                        : 'Read later'.tl,
                    onClick: () async {
                      final manager = LocalFavoritesManager();
                      final included = manager.isInReadLater(c.id, c.comicType);
                      try {
                        await manager.setReadLater(
                          FavoriteItem(
                            id: c.id,
                            name: c.title,
                            coverPath: c.cover,
                            author: c.subtitle,
                            type: c.comicType,
                            tags: c.tags,
                          ),
                          included: !included,
                          folderName: 'Read later'.tl,
                        );
                        if (context.mounted) {
                          context.showMessage(
                            message: included
                                ? 'Removed from read later'.tl
                                : 'Added to read later'.tl,
                          );
                        }
                      } catch (error) {
                        if (context.mounted) {
                          context.showMessage(message: error.toString());
                        }
                      }
                    },
                  ),
                  MenuEntry(
                    icon: Icons.folder_open,
                    text: "Open Folder".tl,
                    onClick: () {
                      openComicFolder(context, c);
                    },
                  ),
                  MenuEntry(
                    icon: Icons.delete,
                    text: "Delete".tl,
                    onClick: () {
                      deleteComics([c]).then((value) {
                        if (value && multiSelectMode) {
                          setState(() {
                            multiSelectMode = false;
                            selectedComics.clear();
                          });
                        }
                      });
                    },
                  ),
                  MenuEntry(
                    icon: Icons.cloud_upload_outlined,
                    text: "Archive to WebDAV".tl,
                    onClick: () {
                      archiveComics([c]);
                    },
                  ),
                  ...exportActions([c]),
                ];
              },
            ),
        ],
      ),
    );

    final page = PopScope(
      canPop: !multiSelectMode && !searchMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (multiSelectMode) {
          setState(() {
            multiSelectMode = false;
            selectedComics.clear();
          });
        } else if (searchMode) {
          setState(() {
            searchMode = false;
            keyword = "";
            update();
          });
        }
      },
      child: body,
    );
    if (!widget.libraryRoot) return page;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openSearch,
      },
      child: Focus(autofocus: true, child: page),
    );
  }

  Future<bool> deleteComics(List<LocalComic> comics) async {
    bool isDeleted = false;
    await showDialog(
      context: appNavigation.rootContext,
      builder: (context) {
        bool removeComicFile = true;
        bool removeFavoriteAndHistory = true;
        return StatefulBuilder(
          builder: (context, state) {
            return ContentDialog(
              title: "Delete".tl,
              content: Column(
                children: [
                  CheckboxListTile(
                    title: Text("Remove local favorite and history".tl),
                    value: removeFavoriteAndHistory,
                    onChanged: (v) {
                      state(() {
                        removeFavoriteAndHistory = !removeFavoriteAndHistory;
                      });
                    },
                  ),
                  CheckboxListTile(
                    title: Text("Also remove files on disk".tl),
                    value: removeComicFile,
                    onChanged: (v) {
                      state(() {
                        removeComicFile = !removeComicFile;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                if (comics.length == 1 && comics.first.hasChapters)
                  TextButton(
                    child: Text("Delete Chapters".tl),
                    onPressed: () {
                      context.pop();
                      showDeleteChaptersPopWindow(context, comics.first);
                    },
                  ),
                FilledButton(
                  onPressed: () async {
                    try {
                      await LocalManager().batchDeleteComics(
                        comics,
                        removeComicFile,
                        removeFavoriteAndHistory,
                      );
                      isDeleted = true;
                      if (context.mounted) context.pop();
                    } catch (error) {
                      if (context.mounted) {
                        context.showMessage(message: error.toString().tl);
                      }
                    }
                  },
                  child: Text("Confirm".tl),
                ),
              ],
            );
          },
        );
      },
    );
    return isDeleted;
  }

  Future<bool> archiveComics(List<LocalComic> comics) async {
    if (comics.isEmpty) return false;
    final config = BackupConfig.fromSettings();
    if (!config.isValid) {
      context.showMessage(message: "Invalid WebDAV archive configuration".tl);
      return false;
    }

    var canceled = false;
    var loadingController = showLoadingDialog(
      context,
      allowCancel: true,
      message: "${"Archive to WebDAV".tl} 0/${comics.length}",
      withProgress: true,
      onCancel: () {
        canceled = true;
      },
    );
    try {
      final result = await ComicBackupManager.instance.backup(
        comics,
        onProgress: (current, total, title) {
          loadingController.setMessage(
            "${"Archive to WebDAV".tl} $current/$total\n$title",
          );
          loadingController.setProgress(current / total);
        },
        isCancelled: () => canceled,
      );
      if (canceled) return false;
      if (result.errors.isNotEmpty) {
        Log.error("Archive Comics", result.errors.join('\n'));
      }
      if (mounted) {
        context.showMessage(
          message: 'Success: @a, Skipped: @b, Failed: @c'.tlParams({
            'a': result.success,
            'b': result.skipped,
            'c': result.failed,
          }),
        );
      }
      return result.success > 0 || result.skipped > 0;
    } catch (e, s) {
      Log.error("Archive Comics", e, s);
      if (mounted) context.showMessage(message: e.toString());
      return false;
    } finally {
      loadingController.close();
    }
  }

  List<MenuEntry> exportActions(List<LocalComic> comics) {
    return [
      MenuEntry(
        icon: Icons.outbox_outlined,
        text: "Export as cbz".tl,
        onClick: () async {
          await exportComics(comics, CBZ.export, ".cbz");
        },
      ),
      MenuEntry(
        icon: Icons.picture_as_pdf_outlined,
        text: "Export as pdf".tl,
        onClick: () async {
          await exportComics(comics, createPdfFromComicIsolate, ".pdf");
        },
      ),
      MenuEntry(
        icon: Icons.import_contacts_outlined,
        text: "Export as epub".tl,
        onClick: () async {
          await exportComics(comics, createEpubWithLocalComic, ".epub");
        },
      ),
    ];
  }

  /// Export given comics to a file
  Future<void> exportComics(
    List<LocalComic> comics,
    ExportComicFunc export,
    String ext,
  ) async {
    if (comics.isEmpty) return;
    final task = WindowSelectionTask(context);
    var canceled = false;
    final loadingController = showLoadingDialog(
      context,
      allowCancel: true,
      message: "${"Exporting".tl} 0/${comics.length}",
      withProgress: comics.length > 1,
      onCancel: () {
        canceled = true;
        task.cancel();
      },
    );
    task.retainPresentation(
      loadingController.close,
      isCurrent: () => loadingController.isCurrent,
    );
    try {
      await task.run(
        (operation) => exportLocalComics(
          comics,
          operation: operation,
          cachePath: App.cachePath,
          extension: ext,
          export: export,
          compress: ZipFile.compressFolderAsync,
          save: (file, name) =>
              saveFile(operation: operation, file: file, filename: name),
          isCancelled: () => canceled || !task.active,
          onProgress: (current, total) {
            if (total > 1) {
              loadingController.setMessage("${"Exporting".tl} $current/$total");
              loadingController.setProgress(current / total);
            }
          },
          onCompress: () {
            loadingController.setProgress(null);
            loadingController.setMessage('Compressing'.tl);
          },
        ),
      );
    } on SelectionCancelled {
      return;
    } catch (error, stack) {
      Log.error('Export Comics', error, stack);
      if (mounted && task.canPresent) {
        context.showMessage(message: error.toString());
      }
    }
  }
}

/// Opens the folder containing the comic in the system file explorer
Future<void> openComicFolder(
  BuildContext context,
  LocalComic comic, {
  Future<void> Function(String path)? openDirectory,
}) async {
  if (!context.mounted) return;
  final owner = WindowSelectionTask(context);
  if (!owner.canPresent) return;
  try {
    final folderPath = comic.baseDir;
    await owner.run<void>((operation) async {
      operation.checkActive();
      if (openDirectory != null) {
        await openDirectory(folderPath);
        return;
      }
      if (App.isWindows) {
        await Process.run('explorer', [folderPath]);
      } else if (App.isMacOS) {
        await Process.run('open', [folderPath]);
      } else {
        if (App.isLinux) {
          for (final command in ['xdg-open', 'nautilus', 'dolphin', 'thunar']) {
            operation.checkActive();
            try {
              await Process.run(command, [folderPath]);
              return;
            } catch (_) {
              // Keep the existing fallback order while the original caller lives.
              operation.checkActive();
            }
          }
        }
        operation.checkActive();
        await launchUrlString('file://$folderPath');
      }
    }, reportFailureOnClose: true);
  } on SelectionCancelled {
    // Do not launch fallback applications for a retired caller.
  } catch (e, s) {
    Log.error("Open Folder", "Failed to open comic folder: $e", s);
    if (context.mounted && owner.canPresent) {
      context.showMessage(message: '${"Failed to open folder".tl}: $e');
    }
  }
}

void showDeleteChaptersPopWindow(BuildContext context, LocalComic comic) {
  var chapters = <String>[];

  showPopUpWidget(
    context,
    PopUpWidgetScaffold(
      title: "Delete Chapters".tl,
      body: StatefulBuilder(
        builder: (context, setState) {
          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: comic.downloadedChapters.length,
                  itemBuilder: (context, index) {
                    var id = comic.downloadedChapters[index];
                    var chapter = comic.chapters![id] ?? "Unknown Chapter";
                    return CheckboxListTile(
                      title: Text(chapter),
                      value: chapters.contains(id),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            chapters.add(id);
                          } else {
                            chapters.remove(id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton(
                      onPressed: () async {
                        try {
                          await LocalManager().deleteComicChapters(
                            comic,
                            chapters,
                          );
                          if (context.mounted) context.pop();
                        } catch (error) {
                          if (context.mounted) {
                            context.showMessage(message: error.toString().tl);
                          }
                        }
                      },
                      child: Text("Submit".tl),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
