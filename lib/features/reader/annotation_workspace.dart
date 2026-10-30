import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;

class ReaderCanvasPalette extends InheritedWidget {
  const ReaderCanvasPalette({
    super.key,
    required this.background,
    required super.child,
  });
  final Color? background;
  static Color backgroundOf(BuildContext context, Color fallback) =>
      context
          .dependOnInheritedWidgetOfExactType<ReaderCanvasPalette>()
          ?.background ??
      fallback;
  @override
  bool updateShouldNotify(ReaderCanvasPalette oldWidget) =>
      background != oldWidget.background;
}

/// The artwork supplies the visual character. Chrome stays compact, neutral,
/// and uses the system typeface; only selection carries the system blue.
class ReaderWorkspaceTokens {
  const ReaderWorkspaceTokens(this.dark);
  final bool dark;
  Color get chrome => dark ? const Color(0xff252527) : const Color(0xfff5f5f7);
  Color get divider => dark ? const Color(0xff414145) : const Color(0xffdcdce1);
  Color get text => dark ? const Color(0xfff5f5f7) : const Color(0xff1d1d1f);
  Color get secondary =>
      dark ? const Color(0xffa1a1a6) : const Color(0xff6e6e73);
  Color get selection =>
      dark ? const Color(0xff0a84ff) : const Color(0xff007aff);
  static const inspectorWidth = 360.0;
  static const toolbarHeight = 52.0;
}

/// A layout adapter, independent of Reader State and all persistence. Changing
/// pane visibility resizes the same content element without reparenting it.
class ReaderAnnotationWorkspace extends StatefulWidget {
  const ReaderAnnotationWorkspace({
    super.key,
    required this.enabled,
    required this.title,
    this.chapterTitle,
    required this.onBack,
    required this.onSettings,
    this.onChapters,
    required this.inspectorBuilder,
    required this.canvasBuilder,
    this.onCanvasChanged,
  });
  final bool enabled;
  final String title;
  final String? chapterTitle;
  final VoidCallback onBack, onSettings;
  final VoidCallback? onChapters;
  final Widget Function(VoidCallback onClose) inspectorBuilder;
  final Widget Function(bool toolbarVisible) canvasBuilder;
  final VoidCallback? onCanvasChanged;
  @override
  State<ReaderAnnotationWorkspace> createState() =>
      ReaderAnnotationWorkspaceState();
}

class ReaderAnnotationWorkspaceState extends State<ReaderAnnotationWorkspace> {
  bool _inspectorOpen = false, _immersive = false, _available = false;
  bool _floatingInspector = false;
  Size? _lastCanvasSize;
  bool get available => _available;
  bool get inspectorOpen =>
      _available && (_immersive ? _floatingInspector : _inspectorOpen);
  void showInspector() {
    if (mounted) {
      setState(() {
        _inspectorOpen = true;
        if (_immersive) _floatingInspector = true;
      });
    }
  }

  void closeInspector() {
    if (mounted) {
      setState(() {
        if (_immersive) {
          _floatingInspector = false;
        } else {
          _inspectorOpen = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.enabled
      ? SafeArea(bottom: false, child: _buildWorkspace(context))
      : _buildWorkspace(context);

  // WindowFrame exposes its draggable title bar as MediaQuery top padding.
  // Consume it before placing workspace chrome or measuring the image canvas.
  Widget _buildWorkspace(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _available =
          widget.enabled &&
          constraints.maxWidth >= 980 &&
          constraints.maxHeight >= 480;
      final tokens = ReaderWorkspaceTokens(
        Theme.of(context).brightness == Brightness.dark,
      );
      final toolbar = _available && !_immersive;
      final dock = toolbar && _inspectorOpen;
      final floating = _available && _immersive && _floatingInspector;
      final scaler = MediaQuery.textScalerOf(context);
      final top = toolbar
          ? math.max(
              ReaderWorkspaceTokens.toolbarHeight,
              scaler.scale(13) +
                  (widget.chapterTitle == null ? 0 : scaler.scale(11)) +
                  12,
            )
          : 0.0;
      final canvasSize = Size(
        constraints.maxWidth -
            (dock ? ReaderWorkspaceTokens.inspectorWidth : 0),
        constraints.maxHeight - top,
      );
      if (widget.enabled && _lastCanvasSize != canvasSize) {
        _lastCanvasSize = canvasSize;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _lastCanvasSize == canvasSize) {
            widget.onCanvasChanged?.call();
          }
        });
      }
      final base = Theme.of(context);
      final neutral = base.colorScheme.copyWith(
        primary: tokens.selection,
        primaryContainer: tokens.dark
            ? const Color(0xff163c68)
            : const Color(0xffdeedff),
        onPrimaryContainer: tokens.text,
        secondaryContainer: tokens.dark
            ? const Color(0xff3c3c40)
            : const Color(0xffe7e7ec),
        onSecondaryContainer: tokens.text,
        surface: tokens.chrome,
        surfaceTint: Colors.transparent,
        onSurface: tokens.text,
        onSurfaceVariant: tokens.secondary,
        outlineVariant: tokens.divider,
        surfaceContainerLow: tokens.chrome,
        surfaceContainer: tokens.chrome,
        surfaceContainerHigh: tokens.dark
            ? const Color(0xff303033)
            : const Color(0xffededf0),
        surfaceContainerHighest: tokens.dark
            ? const Color(0xff3a3a3c)
            : const Color(0xffe5e5ea),
        surfaceContainerLowest: tokens.dark
            ? const Color(0xff1c1c1e)
            : Colors.white,
      );
      return Theme(
        data: _available ? base.copyWith(colorScheme: neutral) : base,
        child: ReaderCanvasPalette(
          background: _available ? const Color(0xff151515) : null,
          child: Stack(
            children: [
              Positioned.fill(
                top: top,
                right: dock ? ReaderWorkspaceTokens.inspectorWidth : 0,
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(size: canvasSize),
                  child: widget.canvasBuilder(toolbar),
                ),
              ),
              if (toolbar)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: top,
                  child: Material(
                    color: tokens.chrome,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: tokens.divider, width: .5),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: '返回书库',
                              onPressed: widget.onBack,
                              icon: const Icon(
                                CupertinoIcons.chevron_left,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: tokens.text,
                                    ),
                                  ),
                                  if (widget.chapterTitle != null)
                                    Text(
                                      widget.chapterTitle!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: tokens.secondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (widget.onChapters != null)
                              IconButton(
                                tooltip: '章节目录',
                                onPressed: widget.onChapters,
                                icon: const Icon(
                                  CupertinoIcons.list_bullet,
                                  size: 18,
                                ),
                              ),
                            IconButton(
                              tooltip: '阅读设置',
                              onPressed: widget.onSettings,
                              icon: const Icon(
                                CupertinoIcons.slider_horizontal_3,
                                size: 18,
                              ),
                            ),
                            IconButton(
                              tooltip: '专注阅读',
                              onPressed: () => setState(() {
                                _immersive = true;
                                _floatingInspector = false;
                              }),
                              icon: const Icon(
                                CupertinoIcons.fullscreen,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: _inspectorOpen ? '收起批注栏' : '展开批注栏',
                              isSelected: _inspectorOpen,
                              color: tokens.secondary,
                              selectedIcon: Icon(
                                CupertinoIcons.sidebar_right,
                                size: 18,
                                color: tokens.selection,
                              ),
                              onPressed: () => setState(
                                () => _inspectorOpen = !_inspectorOpen,
                              ),
                              icon: const Icon(
                                CupertinoIcons.sidebar_right,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (dock || floating)
                Positioned(
                  top: floating ? 64 : top,
                  right: floating ? 12 : 0,
                  bottom: floating ? 12 : 0,
                  width: ReaderWorkspaceTokens.inspectorWidth,
                  child: Material(
                    color: tokens.chrome,
                    elevation: floating ? 4 : 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(floating ? 10 : 0),
                      side: floating
                          ? BorderSide(color: tokens.divider, width: .5)
                          : BorderSide.none,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: floating
                            ? null
                            : Border(
                                left: BorderSide(
                                  color: tokens.divider,
                                  width: .5,
                                ),
                              ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.only(left: floating ? 0 : .5),
                        child: widget.inspectorBuilder(closeInspector),
                      ),
                    ),
                  ),
                ),
              if (_available && _immersive)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Material(
                    color: tokens.chrome,
                    borderRadius: BorderRadius.circular(6),
                    child: IconButton(
                      tooltip: '显示工作台',
                      onPressed: () => setState(() {
                        _immersive = false;
                        _floatingInspector = false;
                      }),
                      icon: const Icon(
                        CupertinoIcons.rectangle_split_3x1,
                        size: 18,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
