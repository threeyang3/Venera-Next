import 'dart:math' as math;

/// Source content coordinates: top-left origin, natural orientation, [0, 1].
class ContentPoint {
  const ContentPoint(this.x, this.y);
  final double x, y;
  bool get isFinite => x.isFinite && y.isFinite;
}

class ContentRect {
  ContentRect(this.x0, this.y0, this.x1, this.y1) {
    if (![x0, y0, x1, y1].every((v) => v.isFinite) ||
        x0 < 0 ||
        y0 < 0 ||
        x1 > 1 ||
        y1 > 1 ||
        x0 >= x1 ||
        y0 >= y1) {
      throw ArgumentError('Expected a nonempty normalized source rectangle');
    }
  }
  final double x0, y0, x1, y1;

  static ContentRect? between(ContentPoint a, ContentPoint b) {
    if (!a.isFinite || !b.isFinite) return null;
    final x0 = math.min(a.x, b.x).clamp(0.0, 1.0);
    final y0 = math.min(a.y, b.y).clamp(0.0, 1.0);
    final x1 = math.max(a.x, b.x).clamp(0.0, 1.0);
    final y1 = math.max(a.y, b.y).clamp(0.0, 1.0);
    return x0 < x1 && y0 < y1 ? ContentRect(x0, y0, x1, y1) : null;
  }

  bool contains(ContentPoint p) =>
      p.x >= x0 && p.x <= x1 && p.y >= y0 && p.y <= y1;
  Map<String, double> toJson() => {'x0': x0, 'y0': y0, 'x1': x1, 'y1': y1};
}

/// Immutable affine source-to-viewport snapshot, independent of Flutter.
/// Normalized source coordinates are transformed directly to logical pixels.
class ViewportTransform {
  ViewportTransform(this.a, this.b, this.c, this.d, this.tx, this.ty) {
    if (![a, b, c, d, tx, ty].every((v) => v.isFinite) ||
        (a * d - b * c).abs() < 1e-12) {
      throw ArgumentError('Transform must be finite and invertible');
    }
  }
  final double a, b, c, d, tx, ty;

  factory ViewportTransform.centered({
    required double sourceWidth,
    required double sourceHeight,
    required double viewportWidth,
    required double viewportHeight,
    required double scale,
    double panX = 0,
    double panY = 0,
    double rotation = 0,
  }) {
    if (![
      sourceWidth,
      sourceHeight,
      viewportWidth,
      viewportHeight,
      scale,
    ].every((v) => v.isFinite && v > 0)) {
      throw ArgumentError('Sizes and scale must be positive and finite');
    }
    final a = math.cos(rotation) * sourceWidth * scale;
    final b = math.sin(rotation) * sourceWidth * scale;
    final c = -math.sin(rotation) * sourceHeight * scale;
    final d = math.cos(rotation) * sourceHeight * scale;
    return ViewportTransform(
      a,
      b,
      c,
      d,
      viewportWidth / 2 + panX - (a + c) / 2,
      viewportHeight / 2 + panY - (b + d) / 2,
    );
  }

  ContentPoint toViewport(ContentPoint p) =>
      ContentPoint(a * p.x + c * p.y + tx, b * p.x + d * p.y + ty);

  ContentPoint toSource(ContentPoint p) {
    final determinant = a * d - b * c;
    final x = p.x - tx, y = p.y - ty;
    return ContentPoint(
      (d * x - c * y) / determinant,
      (-b * x + a * y) / determinant,
    );
  }

  /// Map a displayed slice (including an RTL half) into its original page.
  ViewportTransform forSlice(ContentRect slice) => ViewportTransform(
    a / (slice.x1 - slice.x0),
    b / (slice.x1 - slice.x0),
    c / (slice.y1 - slice.y0),
    d / (slice.y1 - slice.y0),
    tx -
        a * slice.x0 / (slice.x1 - slice.x0) -
        c * slice.y0 / (slice.y1 - slice.y0),
    ty -
        b * slice.x0 / (slice.x1 - slice.x0) -
        d * slice.y0 / (slice.y1 - slice.y0),
  );
}
