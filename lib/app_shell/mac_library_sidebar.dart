import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:venera_next/components/navigation_bar.dart';

/// Library chrome consumes navigation callbacks and labels, never a database.
class MacLibrarySidebar extends StatelessWidget {
  const MacLibrarySidebar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
    required this.folders,
    required this.tags,
    required this.onFolder,
    required this.onTag,
    required this.onImport,
    required this.onSettings,
    this.onRestore,
    this.selectedFolder,
    this.selectedTag,
  });
  final List<PaneItemEntry> items;
  final int selected;
  final ValueChanged<int> onSelect;
  final List<String> folders, tags;
  final ValueChanged<String> onFolder, onTag;
  final VoidCallback onImport, onSettings;
  final VoidCallback? onRestore;
  final String? selectedFolder, selectedTag;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xff292929) : const Color(0xffececec);
    final foreground = dark ? const Color(0xfff5f5f7) : const Color(0xff1d1d1f);
    final secondary = dark ? const Color(0xffa1a1a6) : const Color(0xff6e6e73);
    final blue = dark ? const Color(0xff0a84ff) : const Color(0xff007aff);
    Widget row(
      String label,
      IconData icon,
      VoidCallback onTap, {
      bool active = false,
    }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: active ? blue : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: ListTile(
          dense: true,
          minTileHeight: 30,
          horizontalTitleGap: 8,
          minLeadingWidth: 18,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          leading: Icon(
            icon,
            size: 16,
            color: active ? Colors.white : secondary,
          ),
          title: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: active ? Colors.white : foreground,
              fontWeight: FontWeight.normal,
            ),
          ),
          selected: active,
          onTap: onTap,
        ),
      ),
    );
    Widget section(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 5),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: secondary,
        ),
      ),
    );
    return Material(
      color: background,
      child: SafeArea(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: dark ? const Color(0xff414145) : const Color(0xffdcdce1),
                width: .5,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 16, 0),
                child: Text(
                  'ComicNotes',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    section('书库'),
                    // Local reading is the primary desktop destination; all original
                    // discovery destinations remain reachable and keep their old IDs.
                    for (final i in [
                      4,
                      0,
                      1,
                      2,
                      3,
                    ].where((i) => i < items.length))
                      row(
                        items[i].label,
                        switch (i) {
                          4 => CupertinoIcons.book,
                          0 => CupertinoIcons.house,
                          1 => CupertinoIcons.star,
                          2 => CupertinoIcons.compass,
                          _ => CupertinoIcons.square_grid_2x2,
                        },
                        () => onSelect(i),
                        active:
                            selected == i &&
                            selectedFolder == null &&
                            selectedTag == null,
                      ),
                    section('收藏夹'),
                    if (folders.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 6, 16, 8),
                        child: Text(
                          '还没有收藏夹',
                          style: TextStyle(fontSize: 12, color: secondary),
                        ),
                      ),
                    for (final folder in folders)
                      row(
                        folder,
                        CupertinoIcons.folder,
                        () => onFolder(folder),
                        active: selectedFolder == folder,
                      ),
                    section('标签'),
                    if (tags.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 6, 16, 8),
                        child: Text(
                          '漫画标签会显示在这里',
                          style: TextStyle(fontSize: 12, color: secondary),
                        ),
                      ),
                    for (final tag in tags)
                      row(
                        tag,
                        CupertinoIcons.tag,
                        () => onTag(tag),
                        active: selectedTag == tag,
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              row('导入漫画', CupertinoIcons.plus, onImport),
              if (onRestore != null)
                row(
                  '恢复批注备份',
                  CupertinoIcons.arrow_counterclockwise,
                  onRestore!,
                ),
              row('设置', CupertinoIcons.gear, onSettings),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
