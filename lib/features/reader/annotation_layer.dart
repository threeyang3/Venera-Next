import 'dart:convert';
import 'dart:math' as math;
import 'reader_tap_scope.dart';
import 'image_dimensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:venera_next/components/menu.dart';
import 'package:venera_next/foundation/annotation_link_contract.dart';
import 'package:photo_view/photo_view.dart';
import 'package:venera_next/features/annotations/annotations.dart';

/// A visible neighbouring image can request the owning layer's editor without
/// borrowing its page identity. This controller has only one mounted UI owner.
class AnnotationContextMenuController {
  Object? _owner;
  void Function(Annotation, Offset, bool Function()?)? _open;
  void show(Annotation note, Offset position, {bool Function()? isCurrent}) =>
      _open?.call(note, position, isCurrent);
  void _attach(
    Object owner,
    void Function(Annotation, Offset, bool Function()?) open,
  ) {
    _owner = owner;
    _open = open;
  }

  void _detach(Object owner) {
    if (identical(_owner, owner)) {
      _owner = null;
      _open = null;
    }
  }
}

/// The regular PhotoView remains mounted underneath. Anchors use original
/// dimensions; PhotoView transforms use decoded dimensions independently.
class ReaderAnnotationLayer extends StatefulWidget {
  const ReaderAnnotationLayer({
    super.key,
    required this.image,
    required this.photo,
    required this.session,
    required this.chapterId,
    required this.imageNumber,
    required this.isCurrent,
    required this.onInputChanged,
    required this.child,
    this.sourceIdentity,
    this.active = true,
    this.onExport,
    this.onOpenInspector,
    this.selectionRequests,
    this.geometryBuilder,
    this.additionalGeometries,
    this.visible,
    this.onVisibilityChanged,
    this.contextMenus,
    this.isContextCurrent,
  });
  final ImageProvider image;
  final PhotoViewController photo;
  final AnnotationSession session;
  final String chapterId;
  final int imageNumber;
  final bool Function() isCurrent;
  final bool Function()? isContextCurrent;
  final AnnotationContextMenuController? contextMenus;
  final ValueChanged<bool> onInputChanged;
  final Widget child;
  final String? sourceIdentity;
  final bool active;
  final VoidCallback? onExport;
  final VoidCallback? onOpenInspector;
  final Listenable? selectionRequests;
  final ({ViewportTransform transform, Rect clip})? Function(
    Size source,
    Size viewport,
  )?
  geometryBuilder;
  final List<({ViewportTransform transform, Rect clip})> Function()?
  additionalGeometries;
  final bool? visible;
  final ValueChanged<bool>? onVisibilityChanged;

  @override
  State<ReaderAnnotationLayer> createState() => _ReaderAnnotationLayerState();
}

class _ReaderAnnotationLayerState extends State<ReaderAnnotationLayer> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _size;
  Size? _decodedSize;
  bool _selecting = false, _visible = true, _editing = false;
  bool _listing = false, _contextOpen = false;
  final _contextRoutes = MenuRouteController();
  bool _geometryAvailable = false;
  bool get _showAnnotations => widget.visible ?? _visible;
  ContentRect? _draft;
  final _focus = FocusNode();
  FocusNode? _keyboardSelectionFocus;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.contextMenus?._attach(this, _showContextMenu);
    widget.selectionRequests?.addListener(_selectFromKeyboard);
  }

  void _selectFromKeyboard() {
    if (mounted &&
        widget.active &&
        widget.isCurrent() &&
        _size != null &&
        (widget.geometryBuilder == null || _geometryAvailable) &&
        !_editing &&
        !_listing &&
        !widget.session.inputActive) {
      _keyboardSelectionFocus = FocusManager.instance.primaryFocus;
      _mode(true);
    }
  }

  void _restoreKeyboardFocus() {
    if (_selecting || _editing || _listing) return;
    final previous = _keyboardSelectionFocus;
    _keyboardSelectionFocus = null;
    if (mounted &&
        widget.active &&
        widget.isCurrent() &&
        previous?.context?.mounted == true) {
      previous!.requestFocus();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(ReaderAnnotationLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contextMenus != widget.contextMenus) {
      oldWidget.contextMenus?._detach(this);
      widget.contextMenus?._attach(this, _showContextMenu);
    }
    if (oldWidget.selectionRequests != widget.selectionRequests) {
      oldWidget.selectionRequests?.removeListener(_selectFromKeyboard);
      widget.selectionRequests?.addListener(_selectFromKeyboard);
    }
    if (oldWidget.active && !widget.active) {
      _generation++;
      _keyboardSelectionFocus = null;
      _selecting = false;
      _draft = null;
      _focus.unfocus();
      if (_editing || widget.session.inputActive) widget.onInputChanged(false);
    }
    if (oldWidget.image != widget.image ||
        !identical(oldWidget.session, widget.session)) {
      _generation++;
      _resolve();
    }
    _contextRoutes.revalidate();
  }

  void _resolve() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (_stream?.key == stream.key) return;
    _detach();
    _size = null;
    _decodedSize = null;
    _stream = stream;
    _listener = ImageStreamListener(
      (info, sync) {
        try {
          if (!mounted || !identical(_stream, stream)) return;
          final size = decodedOriginalSize(stream, info);
          final decoded = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          );
          void updateSize() {
            _size = size;
            _decodedSize = decoded;
          }

          if (sync) {
            updateSize();
          } else {
            setState(updateSize);
          }
        } finally {
          info.dispose();
        }
      },
      onError: (Object error, StackTrace? stack) {
        if (mounted && identical(_stream, stream)) setState(() => _size = null);
      },
    );
    stream.addListener(_listener!);
  }

  void _detach() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _stream = null;
    _listener = null;
  }

  void _mode(bool value) {
    setState(() => _selecting = value);
    widget.onInputChanged(value || _editing || _listing || _contextOpen);
    if (value) {
      _focus.requestFocus();
    } else {
      _restoreKeyboardFocus();
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.contextMenus?._detach(this);
    _contextRoutes.dispose();
    widget.selectionRequests?.removeListener(_selectFromKeyboard);
    _detach();
    _focus.dispose();
    if (_selecting || _editing || _listing) widget.onInputChanged(false);
    super.dispose();
  }

  void _showContextMenu(
    Annotation note,
    Offset position, [
    bool Function()? visibleTarget,
  ]) {
    final targetCurrent =
        visibleTarget ?? widget.isContextCurrent ?? widget.isCurrent;
    if (!mounted ||
        _selecting ||
        _editing ||
        _listing ||
        _contextOpen ||
        !targetCurrent() ||
        note.anchor.documentId != widget.session.documentId) {
      return;
    }
    final generation = _generation;
    final session = widget.session;
    bool valid() =>
        mounted &&
        generation == _generation &&
        identical(widget.session, session) &&
        targetCurrent() &&
        session.all.any((current) => identical(current, note));
    if (!valid()) return;
    _contextOpen = true;
    session.selectedId = note.id;
    _mode(false);
    void closed() {
      _contextOpen = false;
      if (mounted) widget.onInputChanged(_selecting || _editing || _listing);
    }

    Future<void> invoke(Future<void> Function() action) async {
      if (!valid()) return;
      _listing = true;
      widget.onInputChanged(true);
      try {
        await action();
      } catch (error) {
        if (!mounted || !targetCurrent()) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('批注操作失败'),
            content: SelectableText('$error'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      } finally {
        _listing = false;
        if (mounted) {
          widget.onInputChanged(_selecting || _editing || _contextOpen);
          _restoreKeyboardFocus();
        }
      }
    }

    final handle = _contextRoutes.show(
      context,
      position,
      [
        MenuEntry(
          icon: Icons.edit_outlined,
          text: '编辑批注',
          onClick: () => invoke(
            () => _edit(
              note.anchor,
              note.kind,
              rect: note.rect,
              existing: note,
              isTargetCurrent: valid,
              showDraft: false,
            ),
          ),
        ),
        MenuEntry(
          icon: Icons.copy_outlined,
          text: '复制批注文字',
          onClick: () =>
              invoke(() => Clipboard.setData(ClipboardData(text: note.text))),
        ),
        if (session.persistent)
          MenuEntry(
            icon: Icons.link,
            text: '复制批注引用',
            onClick: () => invoke(
              () => Clipboard.setData(
                ClipboardData(
                  text: AnnotationLink(
                    documentId: session.documentId,
                    annotationId: note.id,
                  ).toUri().toString(),
                ),
              ),
            ),
          ),
        MenuEntry(
          icon: Icons.delete_outline,
          text: '删除批注',
          onClick: () => invoke(() async {
            session.remove(note.id);
            if (mounted) setState(() {});
          }),
        ),
      ],
      isValid: valid,
      onClosed: closed,
    );
    if (handle == null) closed();
  }

  Future<void> _edit(
    PageAnchor page,
    AnnotationKind kind, {
    ContentRect? rect,
    Annotation? existing,
    bool Function()? isTargetCurrent,
    bool showDraft = true,
  }) async {
    final targetCurrent = isTargetCurrent ?? widget.isCurrent;
    if (_editing || !targetCurrent()) return;
    final generation = _generation;
    _editing = true;
    _draft = showDraft ? rect : null;
    _mode(false);
    try {
      var draftText = existing?.text ?? '';
      String? errorText;
      while (mounted && generation == _generation && targetCurrent()) {
        final value = await showDialog<String>(
          context: context,
          builder: (_) => AnnotationEditor(
            page: page,
            kind: kind,
            rect: rect,
            initialText: draftText,
            persistent: widget.session.persistent,
            errorText: errorText,
          ),
        );
        // Never rebind an asynchronous editor to the reader's new current page.
        if (value == null ||
            !mounted ||
            generation != _generation ||
            !targetCurrent()) {
          break;
        }
        draftText = value;
        try {
          setState(() {
            if (existing != null) {
              widget.session.update(existing.id, value);
            } else {
              widget.session.add(page, kind, value, rect: rect);
            }
          });
          break;
        } catch (error) {
          errorText = '保存失败，文字仍保留，请重试或取消。\n$error';
        }
      }
    } finally {
      _editing = false;
      if (mounted) {
        setState(() => _draft = null);
        widget.onInputChanged(_listing);
        _restoreKeyboardFocus();
      }
    }
  }

  Future<void> _list(PageAnchor page) async {
    if (!mounted || !widget.isCurrent() || _listing) return;
    _listing = true;
    _mode(false);
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, refresh) {
            final notes = widget.session.forPage(page);
            return AlertDialog(
              title: const Text('本页批注'),
              content: SizedBox(
                width: 440,
                height: 320,
                child: notes.isEmpty
                    ? const Center(child: Text('还没有批注，拖拽框选画面试试。'))
                    : ListView(
                        children: notes
                            .map(
                              (note) => ListTile(
                                leading: Icon(
                                  note.kind == AnnotationKind.region
                                      ? Icons.crop
                                      : note.kind == AnnotationKind.bookmark
                                      ? Icons.bookmark_outline
                                      : Icons.notes,
                                ),
                                title: Text(
                                  note.text.isEmpty ? '未填写文字' : note.text,
                                ),
                                subtitle: Text(note.kind.name),
                                onTap: () async {
                                  await _edit(
                                    page,
                                    note.kind,
                                    rect: note.rect,
                                    existing: note,
                                  );
                                  if (context.mounted) refresh(() {});
                                  if (mounted) widget.onInputChanged(true);
                                },
                                trailing: IconButton(
                                  tooltip: '删除批注',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    try {
                                      if (!mounted) return;
                                      widget.session.remove(note.id);
                                      refresh(() {});
                                      setState(() {});
                                    } catch (error) {
                                      if (!context.mounted) return;
                                      await showDialog<void>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text('删除失败，批注仍保留'),
                                          content: Text('$error'),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              child: const Text('关闭'),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ),
                            )
                            .toList(),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(
                        text: const JsonEncoder.withIndent('  ').convert(
                          widget.session
                              .forPage(page)
                              .map((n) => n.toJson())
                              .toList(),
                        ),
                      ),
                    );
                  },
                  child: const Text('复制坐标 JSON'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      _listing = false;
      if (mounted) {
        widget.onInputChanged(false);
        _restoreKeyboardFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final macChrome =
        Theme.of(context).platform == TargetPlatform.macOS &&
        const bool.fromEnvironment('COMICNOTES_WORKSPACE');
    IconData glyph(IconData standard, IconData mac) =>
        macChrome ? mac : standard;
    final size = _size;
    if (size == null) return widget.child;
    late final PageAnchor page;
    try {
      page = widget.session.anchor(
        chapterId: widget.chapterId,
        imageNumber: widget.imageNumber,
        width: size.width,
        height: size.height,
        sourceIdentity: widget.sourceIdentity,
      );
    } catch (error) {
      return Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (widget.active)
            Positioned(
              top: 72,
              right: 16,
              child: Material(
                child: TextButton.icon(
                  icon: const Icon(Icons.error_outline),
                  label: const Text('批注暂不可用'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('无法打开批注'),
                      content: SelectableText('$error'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }
    final focused = widget.session
        .forPage(page)
        .where((note) => note.id == widget.session.selectedId)
        .firstOrNull;
    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            _selecting) {
          _mode(false);
          return KeyEventResult.handled;
        }
        return _selecting ? KeyEventResult.handled : KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, constraints) => StreamBuilder(
          stream: widget.photo.outputStateStream,
          initialData: widget.photo.value,
          builder: (context, snapshot) {
            final value = widget.photo.value;
            final decoded = _decodedSize ?? size;
            final scale =
                value.scale ??
                math.min(
                  constraints.maxWidth / decoded.width,
                  constraints.maxHeight / decoded.height,
                );
            final geometry = widget.geometryBuilder?.call(
              size,
              constraints.biggest,
            );
            final extraGeometries =
                widget.additionalGeometries?.call() ??
                const <({ViewportTransform transform, Rect clip})>[];
            _geometryAvailable =
                widget.geometryBuilder == null ||
                geometry != null ||
                extraGeometries.isNotEmpty;
            if (!_geometryAvailable) return widget.child;
            final transform =
                geometry?.transform ??
                ViewportTransform.centered(
                  sourceWidth: decoded.width,
                  sourceHeight: decoded.height,
                  viewportWidth: constraints.maxWidth,
                  viewportHeight: constraints.maxHeight,
                  scale: scale,
                  panX: value.position.dx,
                  panY: value.position.dy,
                  rotation: value.rotation,
                );
            return Stack(
              fit: StackFit.expand,
              children: [
                AbsorbPointer(
                  absorbing: _selecting || _editing,
                  child: widget.child,
                ),
                for (final projection in [
                  ?geometry,
                  ...extraGeometries,
                  if (widget.geometryBuilder == null)
                    (
                      transform: transform,
                      clip: Offset.zero & constraints.biggest,
                    ),
                ])
                  Positioned.fill(
                    child: ClipRect(
                      clipper: _AnnotationViewportClip(projection.clip),
                      child: AnnotationOverlay(
                        page: page,
                        transform: projection.transform,
                        annotations: widget.session.forPage(page),
                        selecting: _selecting && widget.active,
                        visible: _showAnnotations,
                        draft: _draft,
                        selectedId: widget.session.selectedId,
                        onContextMenu: _showContextMenu,
                        onSelected: (anchor, rect) =>
                            _edit(anchor, AnnotationKind.region, rect: rect),
                      ),
                    ),
                  ),
                if (widget.active)
                  Positioned(
                    top: macChrome ? 16 : 72,
                    right: 16,
                    child: Listener(
                      onPointerDown: (_) =>
                          ReaderTapScope.maybeOf(context)?.ignoreNextTap(),
                      child: Material(
                        elevation: macChrome ? 0 : 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                            width: .5,
                          ),
                        ),
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: math.max(48, constraints.maxWidth - 32),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Wrap(
                              children: [
                                IconButton(
                                  tooltip: _selecting
                                      ? '取消框选'
                                      : widget.session.persistent
                                      ? '区域批注'
                                      : '区域批注（临时）',
                                  isSelected: _selecting,
                                  onPressed: () => _mode(!_selecting),
                                  icon: Icon(
                                    glyph(Icons.crop, CupertinoIcons.crop),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '整页笔记',
                                  onPressed: () =>
                                      _edit(page, AnnotationKind.pageNote),
                                  icon: Icon(
                                    glyph(
                                      Icons.note_add_outlined,
                                      CupertinoIcons.doc_text,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '添加书签',
                                  onPressed: () =>
                                      _edit(page, AnnotationKind.bookmark),
                                  icon: Icon(
                                    glyph(
                                      Icons.bookmark_add_outlined,
                                      CupertinoIcons.bookmark,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip:
                                      '本页批注 (${widget.session.forPage(page).length})',
                                  onPressed: () => _list(page),
                                  icon: Icon(
                                    glyph(
                                      Icons.list_alt,
                                      CupertinoIcons.list_bullet,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: _showAnnotations ? '隐藏标注' : '显示标注',
                                  onPressed: () {
                                    final next = !_showAnnotations;
                                    setState(() => _visible = next);
                                    widget.onVisibilityChanged?.call(next);
                                  },
                                  icon: Icon(
                                    _showAnnotations
                                        ? glyph(
                                            Icons.visibility_outlined,
                                            CupertinoIcons.eye,
                                          )
                                        : glyph(
                                            Icons.visibility_off_outlined,
                                            CupertinoIcons.eye_slash,
                                          ),
                                  ),
                                ),
                                if (widget.onExport != null)
                                  IconButton(
                                    tooltip: '导出图文笔记',
                                    onPressed: () {
                                      if (_selecting) _mode(false);
                                      widget.onExport?.call();
                                    },
                                    icon: Icon(
                                      glyph(
                                        Icons.ios_share_outlined,
                                        CupertinoIcons.square_arrow_up,
                                      ),
                                    ),
                                  ),
                                if (widget.onOpenInspector != null)
                                  IconButton(
                                    tooltip: '全书批注',
                                    icon: Icon(
                                      glyph(
                                        Icons.note_alt_outlined,
                                        CupertinoIcons.sidebar_right,
                                      ),
                                    ),
                                    onPressed: () {
                                      if (_selecting) _mode(false);
                                      widget.onOpenInspector!();
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (widget.active && _selecting)
                  Positioned(
                    bottom: 24,
                    left: 16,
                    right: 16,
                    child: IgnorePointer(
                      child: Center(
                        child: Material(
                          borderRadius: BorderRadius.circular(6),
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Text('拖拽框选 · Esc 取消'),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (widget.active &&
                    !_selecting &&
                    _showAnnotations &&
                    focused != null)
                  Positioned(
                    bottom: 24,
                    left: 16,
                    right: 16,
                    child: IgnorePointer(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: Material(
                            elevation: 1,
                            borderRadius: BorderRadius.circular(6),
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.location_on_outlined,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      focused.text.isEmpty
                                          ? '已定位到批注'
                                          : focused.text,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AnnotationViewportClip extends CustomClipper<Rect> {
  const _AnnotationViewportClip(this.clip);
  final Rect clip;
  @override
  Rect getClip(Size size) => clip.intersect(Offset.zero & size);
  @override
  bool shouldReclip(_AnnotationViewportClip oldClipper) =>
      clip != oldClipper.clip;
}
