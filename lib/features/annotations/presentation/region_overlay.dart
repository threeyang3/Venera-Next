import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../domain/annotation.dart';
import '../domain/geometry.dart';

/// Geometry-only canvas. It never reads a database or reader State.
class AnnotationOverlay extends StatefulWidget {
  const AnnotationOverlay({
    super.key,
    required this.page,
    required this.transform,
    required this.annotations,
    required this.selecting,
    required this.onSelected,
    this.visible = true,
    this.draft,
    this.selectedId,
    this.onContextMenu,
  });
  final PageAnchor page;
  final ViewportTransform transform;
  final List<Annotation> annotations;
  final bool selecting, visible;
  final ContentRect? draft;
  final String? selectedId;
  final void Function(PageAnchor, ContentRect) onSelected;
  final void Function(Annotation, Offset)? onContextMenu;

  @override
  State<AnnotationOverlay> createState() => _AnnotationOverlayState();
}

class _AnnotationOverlayState extends State<AnnotationOverlay> {
  ContentPoint? _start, _end;
  Offset? _hoverPosition;
  PageAnchor? _page;
  ViewportTransform? _transform;

  Annotation? _at(Offset position) {
    if (widget.selecting || !widget.visible) return null;
    final point = widget.transform.toSource(
      ContentPoint(position.dx, position.dy),
    );
    return widget.annotations.reversed
        .where((note) => note.rect?.contains(point) ?? false)
        .firstOrNull;
  }

  String? get _hoveredId =>
      _hoverPosition == null ? null : _at(_hoverPosition!)?.id;

  void _hover(Offset? position) {
    final previous = _hoveredId;
    _hoverPosition = position;
    if (previous != _hoveredId) setState(() {});
  }

  void _clear() {
    _start = _end = null;
    _page = null;
    _transform = null;
  }

  @override
  void didUpdateWidget(AnnotationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A resize, pan, zoom, page replacement or mode exit retires the drag.
    final a = oldWidget.transform, b = widget.transform;
    if (widget.selecting || oldWidget.page.pageId != widget.page.pageId) {
      _hoverPosition = null;
    }
    if (oldWidget.page.pageId != widget.page.pageId ||
        !widget.selecting ||
        a.a != b.a ||
        a.b != b.b ||
        a.c != b.c ||
        a.d != b.d ||
        a.tx != b.tx ||
        a.ty != b.ty) {
      _clear();
    }
  }

  ContentPoint _source(Offset point) => (_transform ?? widget.transform)
      .toSource(ContentPoint(point.dx, point.dy));

  @override
  Widget build(BuildContext context) {
    final preview = _start == null || _end == null
        ? null
        : ContentRect.between(_start!, _end!);
    return MouseRegion(
      opaque: widget.selecting,
      hitTestBehavior: HitTestBehavior.translucent,
      onEnter: (event) => _hover(event.localPosition),
      onHover: (event) => _hover(event.localPosition),
      onExit: (_) => _hover(null),
      cursor: widget.selecting ? SystemMouseCursors.precise : MouseCursor.defer,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (event.buttons == kSecondaryMouseButton) {
            final note = _at(event.localPosition);
            if (note != null) widget.onContextMenu?.call(note, event.position);
          }
        },
        child: IgnorePointer(
          ignoring: !widget.selecting,
          child: GestureDetector(
            dragStartBehavior: DragStartBehavior.down,
            behavior: HitTestBehavior.opaque,
            onPanStart: (event) {
              final point = _source(event.localPosition);
              if (point.x < 0 || point.x > 1 || point.y < 0 || point.y > 1) {
                return;
              }
              setState(() {
                _transform = widget.transform;
                _page = widget.page;
                _start = _end = point;
              });
            },
            onPanUpdate: (event) {
              if (_start != null) {
                setState(() => _end = _source(event.localPosition));
              }
            },
            onPanCancel: () => setState(_clear),
            onPanEnd: (_) {
              final page = _page;
              final rect = _start == null || _end == null
                  ? null
                  : ContentRect.between(_start!, _end!);
              setState(_clear);
              if (page != null &&
                  rect != null &&
                  (rect.x1 - rect.x0) * page.sourceWidth >= 2 &&
                  (rect.y1 - rect.y0) * page.sourceHeight >= 2) {
                widget.onSelected(page, rect);
              }
            },
            child: CustomPaint(
              painter: _RegionPainter(
                widget.transform,
                widget.visible ? widget.annotations : const [],
                preview ?? widget.draft,
                widget.selectedId,
                _hoveredId,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class _RegionPainter extends CustomPainter {
  _RegionPainter(
    this.transform,
    this.annotations,
    this.preview,
    this.selectedId,
    this.hoveredId,
  );
  final ViewportTransform transform;
  final List<Annotation> annotations;
  final ContentRect? preview;
  final String? selectedId, hoveredId;

  Path _path(ContentRect r) {
    final points = [
      ContentPoint(r.x0, r.y0),
      ContentPoint(r.x1, r.y0),
      ContentPoint(r.x1, r.y1),
      ContentPoint(r.x0, r.y1),
    ].map(transform.toViewport).toList();
    return Path()
      ..moveTo(points[0].x, points[0].y)
      ..lineTo(points[1].x, points[1].y)
      ..lineTo(points[2].x, points[2].y)
      ..lineTo(points[3].x, points[3].y)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()
      ..color = const Color(0xffd49c23)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final note in annotations) {
      if (note.rect != null) {
        canvas.drawPath(
          _path(note.rect!),
          note.id == selectedId
              ? (Paint()
                  ..color = const Color(0xff0a84ff)
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 3)
              : note.id == hoveredId
              ? (Paint()
                  ..color = paint.color
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 3)
              : paint,
        );
      }
    }
    if (preview != null) {
      canvas.drawPath(
        _path(preview!),
        Paint()..color = const Color(0x30d49c23),
      );
      canvas.drawPath(_path(preview!), paint..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_RegionPainter oldDelegate) => true;
}
