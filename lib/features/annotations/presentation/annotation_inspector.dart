import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoIcons, CupertinoSlidingSegmentedControl;
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:venera_next/foundation/annotation_link_contract.dart';
import '../application/annotation_session.dart';
import '../domain/annotation.dart';
import 'annotation_editor.dart';
import '../domain/source_document.dart';

/// Book-wide notes. Storage is injected through this reader's session; no
/// global database, navigation, or reader State is accessed from this panel.
class AnnotationInspector extends StatefulWidget {
  const AnnotationInspector({
    super.key,
    required this.session,
    required this.isCurrent,
    required this.onOpen,
    required this.onChanged,
    this.onExport,
    this.onRestoreReading,
    this.onBackup,
    this.onRelocate,
    this.findRecovery,
    this.onRecover,
    this.findManualRecovery,
    this.onManualRecover,
    this.onClose,
    this.onInputChanged,
    this.keepOpenOnActions = false,
    this.searchRequest = 0,
  });
  final AnnotationSession session;
  final bool Function() isCurrent;
  final Future<void> Function(Annotation) onOpen;
  final VoidCallback onChanged;
  final VoidCallback? onExport;
  final VoidCallback? onRestoreReading;
  final VoidCallback? onBackup;
  final Future<String?> Function()? onRelocate;
  final Future<List<RecoverableAnnotationDocument>> Function()? findRecovery;
  final Future<void> Function(String)? onRecover;
  final Future<List<RecoverableAnnotationDocument>> Function()?
  findManualRecovery;
  final Future<void> Function(String)? onManualRecover;
  final VoidCallback? onClose;
  final ValueChanged<bool>? onInputChanged;
  final bool keepOpenOnActions;
  final int searchRequest;
  @override
  State<AnnotationInspector> createState() => _AnnotationInspectorState();
}

class _AnnotationInspectorState extends State<AnnotationInspector> {
  final _searchFocus = FocusNode(debugLabel: 'Annotation search');
  final _notesFocus = FocusNode(debugLabel: 'Annotation list');
  final _noteScroll = ItemScrollController();
  final _notePositions = ItemPositionsListener.create();

  List<Annotation> _visibleNotes() {
    final query = _query.trim().toLowerCase();
    return widget.session.all
        .where(
          (note) =>
              (_kind == null || note.kind == _kind) &&
              (_tag == null || note.tags.contains(_tag)) &&
              (query.isEmpty ||
                  note.text.toLowerCase().contains(query) ||
                  note.tags.any((tag) => tag.toLowerCase().contains(query)) ||
                  note.anchor.chapterId.toLowerCase().contains(query)),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  KeyEventResult _navigateNotes(KeyEvent event, List<Annotation> notes) {
    if (!_notesFocus.hasPrimaryFocus ||
        _editing ||
        !widget.isCurrent() ||
        notes.isEmpty ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final current = notes.indexWhere(
      (note) => note.id == (_selected ?? widget.session.selectedId),
    );
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent && current >= 0) _open(notes[current]);
      return KeyEventResult.handled;
    }
    final int next;
    if (key == LogicalKeyboardKey.arrowDown) {
      next = current < 0 ? 0 : (current + 1).clamp(0, notes.length - 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      next = current < 0
          ? notes.length - 1
          : (current - 1).clamp(0, notes.length - 1);
    } else if (key == LogicalKeyboardKey.home) {
      next = 0;
    } else if (key == LogicalKeyboardKey.end) {
      next = notes.length - 1;
    } else {
      return KeyEventResult.ignored;
    }
    final id = notes[next].id;
    setState(() => _selected = id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.isCurrent() ||
          _selected != id ||
          !_noteScroll.isAttached) {
        return;
      }
      final index = _visibleNotes().indexWhere((note) => note.id == id);
      if (index < 0) return;
      final visible = _notePositions.itemPositions.value.any(
        (item) =>
            item.index == index &&
            item.itemLeadingEdge >= 0 &&
            item.itemTrailingEdge <= 1,
      );
      if (!visible) _noteScroll.jumpTo(index: index, alignment: .15);
    });
    return KeyEventResult.handled;
  }

  void _focusSearch() {
    if (mounted && !_editing && !_relocating && widget.isCurrent()) {
      _searchFocus.requestFocus();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.searchRequest > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusSearch());
    }
  }

  @override
  void didUpdateWidget(AnnotationInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchRequest != widget.searchRequest) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusSearch());
    }
  }

  String _query = '', _message = '';
  AnnotationKind? _kind;
  String? _tag;
  String? _selected;
  final _searchText = TextEditingController();
  bool _editing = false;
  bool _searchFocused = false;
  bool _notesFocused = false;
  bool _relocating = false;
  Future<void> _recover({bool manual = false}) async {
    if (_relocating || !widget.isCurrent()) return;
    setState(() => _relocating = true);
    try {
      final candidates = await (manual
          ? widget.findManualRecovery!()
          : widget.findRecovery!());
      if (!mounted || !widget.isCurrent()) return;
      if (candidates.isEmpty) {
        setState(
          () => _message = manual
              ? '没有失去书库绑定且包含批注的旧文档'
              : '没有可恢复的同原件旧批注；可另选手工逐页关联',
        );
        return;
      }
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(manual ? '选择需要手工关联的旧批注' : '恢复同一原件的旧批注'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    manual
                        ? '选择旧文档后需逐页比较目标内容。不会按名称或页码自动绑定。'
                        : '选择一份旧批注。将校验每张原图并保留旧批注 ID，不会合并多份记录。',
                  ),
                  for (final candidate in candidates)
                    ListTile(
                      title: Text(candidate.title),
                      subtitle: Text(
                        '${candidate.annotationCount} 条批注\n${candidate.documentId}',
                      ),
                      isThreeLine: true,
                      onTap: () => Navigator.pop(context, candidate.documentId),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        ),
      );
      if (selected == null || !mounted || !widget.isCurrent()) return;
      final recover = manual ? widget.onManualRecover! : widget.onRecover!;
      _close();
      await recover(selected);
    } catch (error) {
      if (mounted && widget.isCurrent()) {
        setState(() => _message = '恢复失败：$error');
      }
    } finally {
      if (mounted) setState(() => _relocating = false);
    }
  }

  Future<void> _relocate() async {
    if (_relocating || !widget.isCurrent()) return;
    setState(() => _relocating = true);
    try {
      final message = await widget.onRelocate!();
      if (mounted && widget.isCurrent()) {
        setState(() => _message = message ?? '未修改原件关联');
      }
    } catch (error) {
      if (mounted && widget.isCurrent()) {
        setState(() => _message = '关联失败：$error');
      }
    } finally {
      if (mounted) setState(() => _relocating = false);
    }
  }

  void _reportInput() =>
      widget.onInputChanged?.call(_editing || _searchFocused || _notesFocused);
  void _close() {
    if (widget.onClose case final close?) {
      close();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    widget.onInputChanged?.call(false);
    _searchFocus.dispose();
    _notesFocus.dispose();
    _searchText.dispose();
    super.dispose();
  }

  Future<void> _editTags(Annotation note) async {
    if (_editing || !widget.isCurrent()) return;
    _editing = true;
    _reportInput();
    var text = note.tags.join('，');
    String? error;
    try {
      while (mounted && widget.isCurrent()) {
        final next = await showDialog<String>(
          context: context,
          builder: (_) => _TagEditor(initialText: text, error: error),
        );
        if (next == null || !mounted || !widget.isCurrent()) break;
        text = next;
        try {
          widget.session.setTags(note.id, text.split(RegExp('[,，]')));
          widget.onChanged();
          setState(() {});
          break;
        } catch (failure) {
          error = '保存失败，标签仍保留。\n$failure';
        }
      }
    } finally {
      _editing = false;
      _reportInput();
    }
  }

  Future<void> _edit(Annotation note) async {
    if (_editing || !widget.isCurrent()) return;
    _editing = true;
    _reportInput();
    var text = note.text;
    String? error;
    try {
      while (mounted && widget.isCurrent()) {
        final next = await showDialog<String>(
          context: context,
          builder: (_) => AnnotationEditor(
            page: note.anchor,
            kind: note.kind,
            rect: note.rect,
            initialText: text,
            persistent: widget.session.persistent,
            errorText: error,
          ),
        );
        if (next == null || !mounted || !widget.isCurrent()) break;
        text = next;
        try {
          widget.session.update(note.id, text);
          widget.onChanged();
          setState(() {});
          break;
        } catch (failure) {
          error = '保存失败，文字仍保留。\n$failure';
        }
      }
    } finally {
      _editing = false;
      _reportInput();
    }
  }

  void _open(Annotation note) {
    if (!widget.isCurrent()) return;
    if (!widget.keepOpenOnActions) _close();
    unawaited(widget.onOpen(note));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final macChrome =
        widget.keepOpenOnActions &&
        const bool.fromEnvironment('COMICNOTES_WORKSPACE') &&
        Theme.of(context).platform == TargetPlatform.macOS;
    IconData glyph(IconData standard, IconData mac) =>
        macChrome ? mac : standard;
    final all = widget.session.all;
    final query = _query.trim().toLowerCase();
    final notes = _visibleNotes();
    final body = Material(
      color: colors.surfaceContainerLow,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '全书批注 · ${all.length}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (widget.onExport != null)
                    IconButton(
                      tooltip: '导出图文笔记',
                      icon: Icon(
                        glyph(
                          Icons.ios_share_outlined,
                          CupertinoIcons.square_arrow_up,
                        ),
                      ),
                      onPressed: () {
                        if (!widget.keepOpenOnActions) _close();
                        widget.onExport!();
                      },
                    ),
                  if (widget.onBackup != null && !macChrome)
                    IconButton(
                      tooltip: '备份全部批注',
                      icon: Icon(
                        glyph(
                          Icons.backup_outlined,
                          CupertinoIcons.tray_arrow_down,
                        ),
                      ),
                      onPressed: () {
                        if (!widget.keepOpenOnActions) _close();
                        widget.onBackup!();
                      },
                    ),
                  if (macChrome &&
                      (widget.onBackup != null || widget.onRelocate != null))
                    PopupMenuButton<String>(
                      tooltip: '更多批注操作',
                      icon: const Icon(CupertinoIcons.ellipsis, size: 18),
                      onSelected: (value) {
                        if (value == 'backup') widget.onBackup!();
                        if (value == 'relocate') unawaited(_relocate());
                      },
                      itemBuilder: (_) => [
                        if (widget.onBackup != null)
                          const PopupMenuItem(
                            value: 'backup',
                            child: Text('备份全部批注'),
                          ),
                        if (widget.onRelocate != null)
                          PopupMenuItem(
                            value: 'relocate',
                            enabled: !_relocating,
                            child: Text(_relocating ? '正在校验原件…' : '重新关联原件'),
                          ),
                      ],
                    ),
                  IconButton(
                    tooltip: '关闭批注面板',
                    onPressed: _close,
                    icon: Icon(glyph(Icons.close, CupertinoIcons.xmark)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Focus(
                onFocusChange: (value) {
                  _searchFocused = value;
                  _reportInput();
                },
                child: TextField(
                  key: const ValueKey('annotation-search'),
                  controller: _searchText,
                  focusNode: _searchFocus,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(CupertinoIcons.search, size: 14),
                    prefixIconConstraints: const BoxConstraints(minWidth: 30),
                    hintText: macChrome ? '查找批注或标签' : '查找文字或章节',
                    border: const OutlineInputBorder(),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除批注搜索',
                            icon: const Icon(
                              CupertinoIcons.xmark_circle_fill,
                              size: 13,
                            ),
                            onPressed: () {
                              _searchText.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                ),
              ),
            ),
            if (widget.onRestoreReading != null)
              TextButton.icon(
                onPressed: () {
                  _close();
                  widget.onRestoreReading!();
                },
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('返回阅读布局'),
              ),
            if (widget.onRelocate != null && !macChrome)
              TextButton.icon(
                onPressed: _relocating ? null : _relocate,
                icon: const Icon(Icons.link),
                label: Text(_relocating ? '正在校验原件…' : '重新关联原件'),
              ),
            if (macChrome && _relocating)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('正在校验原件…', style: TextStyle(fontSize: 11)),
              ),
            if (widget.findRecovery != null &&
                widget.onRecover != null &&
                all.isEmpty)
              TextButton.icon(
                onPressed: _relocating ? null : () => _recover(),
                icon: const Icon(Icons.history),
                label: const Text('恢复旧批注'),
              ),
            if (widget.findManualRecovery != null &&
                widget.onManualRecover != null &&
                all.isEmpty)
              TextButton.icon(
                onPressed: _relocating ? null : () => _recover(manual: true),
                icon: const Icon(Icons.compare_outlined),
                label: const Text('手工逐页关联旧批注'),
              ),
            if (_tag != null)
              InputChip(
                label: Text('标签：$_tag'),
                deleteButtonTooltipMessage: '清除标签筛选',
                onDeleted: () => setState(() => _tag = null),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: macChrome
                  ? SizedBox(
                      width: double.infinity,
                      child: CupertinoSlidingSegmentedControl<int>(
                        groupValue: _kind == null ? 0 : _kind!.index + 1,
                        backgroundColor: colors.onSurface.withValues(
                          alpha: .06,
                        ),
                        thumbColor:
                            Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xff555555)
                            : Colors.white,
                        children: {
                          0: const Text('全部', style: TextStyle(fontSize: 12)),
                          for (final kind in AnnotationKind.values)
                            kind.index + 1: Text(
                              _label(kind),
                              style: const TextStyle(fontSize: 12),
                            ),
                        },
                        onValueChanged: (value) {
                          if (value == null) return;
                          setState(
                            () => _kind = value == 0
                                ? null
                                : AnnotationKind.values[value - 1],
                          );
                        },
                      ),
                    )
                  : Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          label: const Text('全部'),
                          selected: _kind == null,
                          onSelected: (_) => setState(() => _kind = null),
                        ),
                        for (final kind in AnnotationKind.values)
                          ChoiceChip(
                            label: Text(_label(kind)),
                            selected: _kind == kind,
                            onSelected: (_) => setState(() => _kind = kind),
                          ),
                      ],
                    ),
            ),
            const Divider(height: 1),
            if (macChrome &&
                (query.isNotEmpty || _kind != null || _tag != null))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '找到 ${notes.length} 条批注',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            if (widget.session.persistenceFailure != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '批注库暂不可用，笔记未被删除。请重新打开漫画以重试。\n${widget.session.persistenceFailure}',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.error),
                ),
              ),
            Expanded(
              child: Focus(
                focusNode: _notesFocus,
                canRequestFocus: macChrome,
                onFocusChange: (value) {
                  _notesFocused = value;
                  _reportInput();
                },
                onKeyEvent: (_, event) => _navigateNotes(event, notes),
                child: notes.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            all.isEmpty
                                ? '还没有批注。框选画面或添加整页笔记后，会出现在这里。'
                                : '没有匹配的批注。',
                          ),
                        ),
                      )
                    : ScrollablePositionedList.separated(
                        scrollControllerCallback: null,
                        itemScrollController: _noteScroll,
                        itemPositionsListener: _notePositions,
                        itemCount: notes.length,
                        separatorBuilder: (_, _) => macChrome
                            ? const SizedBox(height: 0)
                            : const Divider(height: 1, indent: 16),
                        itemBuilder: (context, index) {
                          final note = notes[index];
                          final selected =
                              (_selected ?? widget.session.selectedId) ==
                              note.id;
                          return Padding(
                            padding: macChrome
                                ? const EdgeInsets.fromLTRB(8, 6, 8, 0)
                                : EdgeInsets.zero,
                            child: Material(
                              color: macChrome && selected
                                  ? colors.primary.withValues(alpha: .1)
                                  : macChrome
                                  ? colors.surfaceContainerLowest
                                  : Colors.transparent,
                              shape: macChrome
                                  ? RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(
                                        color: colors.outlineVariant.withValues(
                                          alpha: .5,
                                        ),
                                        width: .5,
                                      ),
                                    )
                                  : null,
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () {
                                  if (macChrome) _notesFocus.requestFocus();
                                  setState(() => _selected = note.id);
                                },
                                child: Padding(
                                  key: ValueKey('annotation-note:${note.id}'),
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    8,
                                    8,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            _icon(note.kind),
                                            size: 16,
                                            color: colors.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              macChrome
                                                  ? '${_label(note.kind)} · 第 ${note.anchor.sourceImageNumber} 页'
                                                  : '${_label(note.kind)} · ${note.anchor.chapterId} · 第 ${note.anchor.sourceImageNumber} 张原图',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.labelMedium,
                                            ),
                                          ),
                                          if ((_selected ??
                                                  widget.session.selectedId) ==
                                              note.id)
                                            Icon(
                                              Icons.location_on,
                                              size: 16,
                                              color: colors.primary,
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      if (note.tags.isNotEmpty)
                                        Wrap(
                                          spacing: 4,
                                          children: [
                                            for (final tag in note.tags)
                                              ActionChip(
                                                label: Text(tag),
                                                onPressed: () =>
                                                    setState(() => _tag = tag),
                                              ),
                                          ],
                                        ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onDoubleTap: () => _open(note),
                                          child: Text(
                                            note.text.isEmpty
                                                ? '（无文字）'
                                                : note.text,
                                            maxLines: 5,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      if (!macChrome || selected)
                                        Wrap(
                                          alignment: WrapAlignment.spaceBetween,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            TextButton.icon(
                                              onPressed: () => _open(note),
                                              icon: const Icon(
                                                Icons.my_location,
                                                size: 16,
                                              ),
                                              label: const Text('定位原图'),
                                            ),
                                            IconButton(
                                              tooltip: '编辑标签',
                                              icon: Icon(
                                                glyph(
                                                  Icons.sell_outlined,
                                                  CupertinoIcons.tag,
                                                ),
                                                size: 16,
                                              ),
                                              onPressed: () => _editTags(note),
                                            ),
                                            IconButton(
                                              tooltip: '编辑批注',
                                              icon: Icon(
                                                glyph(
                                                  Icons.edit_outlined,
                                                  CupertinoIcons.pencil,
                                                ),
                                                size: 16,
                                              ),
                                              onPressed: () => _edit(note),
                                            ),
                                            IconButton(
                                              tooltip: '复制引用链接',
                                              icon: const Icon(
                                                Icons.link,
                                                size: 18,
                                              ),
                                              onPressed: () async {
                                                await Clipboard.setData(
                                                  ClipboardData(
                                                    text: AnnotationLink(
                                                      documentId: note
                                                          .anchor
                                                          .documentId,
                                                      annotationId: note.id,
                                                    ).toUri().toString(),
                                                  ),
                                                );
                                                if (mounted) {
                                                  setState(
                                                    () => _message = '引用链接已复制',
                                                  );
                                                }
                                              },
                                            ),
                                            IconButton(
                                              tooltip: '删除批注',
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                size: 18,
                                              ),
                                              onPressed: () {
                                                if (!widget.isCurrent()) return;
                                                try {
                                                  widget.session.remove(
                                                    note.id,
                                                  );
                                                  widget.onChanged();
                                                  setState(() => _message = '');
                                                } catch (error) {
                                                  setState(
                                                    () => _message =
                                                        '删除失败，批注仍保留：$error',
                                                  );
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _message.isEmpty
                    ? widget.session.persistent
                          ? macChrome
                                ? '更改保存在本机 · ↑↓ 选择 · 回车定位'
                                : '更改保存在本机 · 双击批注可定位'
                          : '临时预览 · 退出阅读后不会保留'
                    : _message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            _focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _focusSearch,
      },
      child: body,
    );
  }

  static String _label(AnnotationKind kind) => switch (kind) {
    AnnotationKind.region => '区域',
    AnnotationKind.pageNote => '整页',
    AnnotationKind.bookmark => '书签',
  };
  static IconData _icon(AnnotationKind kind) => switch (kind) {
    AnnotationKind.region => Icons.crop,
    AnnotationKind.pageNote => Icons.notes,
    AnnotationKind.bookmark => Icons.bookmark_outline,
  };
}

class _TagEditor extends StatefulWidget {
  const _TagEditor({required this.initialText, this.error});
  final String initialText;
  final String? error;
  @override
  State<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<_TagEditor> {
  late final input = TextEditingController(text: widget.initialText);
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('批注标签'),
    content: SizedBox(
      width: 360,
      child: TextField(
        key: const ValueKey('annotation-tags-editor'),
        controller: input,
        autofocus: true,
        decoration: InputDecoration(
          labelText: '标签',
          hintText: '用逗号分隔，例如：构图，人物',
          errorText: widget.error,
          errorMaxLines: 4,
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, input.text),
        child: const Text('保存'),
      ),
    ],
  );
}
