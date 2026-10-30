import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/annotations/domain/geometry.dart';

void main() {
  test('rejects invalid and degenerate normalized rectangles at runtime', () {
    for (final values in [
      [-0.1, 0.0, 1.0, 1.0],
      [0.0, 0.0, 1.1, 1.0],
      [0.5, 0.0, 0.5, 1.0],
      [0.8, 0.0, 0.2, 1.0],
      [0.0, double.nan, 1.0, 1.0],
      [0.0, 0.0, 1.0, double.infinity],
    ]) {
      expect(
        () => ContentRect(values[0], values[1], values[2], values[3]),
        throwsArgumentError,
      );
    }
  });
  test('reverse drag sorts and clamps to original content', () {
    final r = ContentRect.between(
      const ContentPoint(1.2, 0.8),
      const ContentPoint(0.2, -0.1),
    )!;
    expect(r.toJson(), {'x0': 0.2, 'y0': 0.0, 'x1': 1.0, 'y1': 0.8});
  });
  test('outside and zero-area selections have no rectangle', () {
    expect(
      ContentRect.between(const ContentPoint(2, 2), const ContentPoint(3, 3)),
      isNull,
    );
    expect(
      ContentRect.between(const ContentPoint(0, 0), const ContentPoint(0, 1)),
      isNull,
    );
    expect(
      ContentRect.between(
        const ContentPoint(double.nan, 0),
        const ContentPoint(1, 1),
      ),
      isNull,
    );
  });
  test('singular and non-finite transforms fail early', () {
    expect(() => ViewportTransform(0, 0, 0, 0, 0, 0), throwsArgumentError);
    expect(
      () => ViewportTransform(1, 0, 0, 1, double.infinity, 0),
      throwsArgumentError,
    );
    expect(
      () => ViewportTransform.centered(
        sourceWidth: -1,
        sourceHeight: 1,
        viewportWidth: 100,
        viewportHeight: 100,
        scale: 1,
      ),
      throwsArgumentError,
    );
  });
  test('portrait contain maps source corners to known letterboxed pixels', () {
    final t = ViewportTransform.centered(
      sourceWidth: 1000,
      sourceHeight: 2000,
      viewportWidth: 800,
      viewportHeight: 600,
      scale: 0.3,
    );
    expectPoint(t.toViewport(const ContentPoint(0, 0)), 250, 0);
    expectPoint(t.toViewport(const ContentPoint(1, 1)), 550, 600);
  });
  test('landscape contain has vertical letterbox', () {
    final t = ViewportTransform.centered(
      sourceWidth: 2000,
      sourceHeight: 1000,
      viewportWidth: 600,
      viewportHeight: 800,
      scale: 0.3,
    );
    expectPoint(t.toViewport(const ContentPoint(0, 0)), 0, 250);
    expectPoint(t.toViewport(const ContentPoint(1, 1)), 600, 550);
  });
  test('zoom and pan preserve source identity and known screen position', () {
    final t = ViewportTransform.centered(
      sourceWidth: 1000,
      sourceHeight: 2000,
      viewportWidth: 800,
      viewportHeight: 600,
      scale: 0.6,
      panX: 35,
      panY: -20,
    );
    expectPoint(t.toViewport(const ContentPoint(0.5, 0.5)), 435, 280);
    expectPoint(t.toViewport(const ContentPoint(0, 0)), 135, -320);
  });
  test('90 degree rotation uses natural source orientation', () {
    final t = ViewportTransform.centered(
      sourceWidth: 1000,
      sourceHeight: 2000,
      viewportWidth: 800,
      viewportHeight: 600,
      scale: 0.3,
      rotation: math.pi / 2,
    );
    expectPoint(t.toViewport(const ContentPoint(0, 0)), 700, 150);
    expectPoint(t.toSource(const ContentPoint(700, 150)), 0, 0);
  });
  for (final scenario in [
    (800.0, 600.0, 0.3, 0.0, 0.0, 0.0),
    (1440.0, 900.0, 1.7, 227.0, -175.0, 0.0),
    (600.0, 1200.0, 0.6, -150.0, 341.0, math.pi),
    (900.0, 700.0, 0.24, 0.0, 0.0, -math.pi / 2),
    (480.0, 320.0, 0.9, -51.0, 22.0, 0.37),
  ]) {
    test('round trip stays below one source pixel: $scenario', () {
      final t = ViewportTransform.centered(
        sourceWidth: 3000,
        sourceHeight: 4700,
        viewportWidth: scenario.$1,
        viewportHeight: scenario.$2,
        scale: scenario.$3,
        panX: scenario.$4,
        panY: scenario.$5,
        rotation: scenario.$6,
      );
      for (var x = 0; x <= 10; x++) {
        for (var y = 0; y <= 10; y++) {
          final p = ContentPoint(x / 10, y / 10);
          final result = t.toSource(t.toViewport(p));
          expect((result.x - p.x).abs() * 3000, lessThan(1e-6));
          expect((result.y - p.y).abs() * 4700, lessThan(1e-6));
        }
      }
    });
  }
  test('RTL right-half slice maps to the same unsplit original page', () {
    final t = ViewportTransform(
      400,
      0,
      0,
      600,
      0,
      0,
    ).forSlice(ContentRect(0.5, 0, 1, 1));
    expectPoint(t.toSource(const ContentPoint(0, 0)), 0.5, 0);
    expectPoint(t.toSource(const ContentPoint(400, 600)), 1, 1);
  });
  test('two-page RTL ordering is represented by independent translations', () {
    final first = ViewportTransform(300, 0, 0, 500, 300, 0);
    final second = ViewportTransform(300, 0, 0, 500, 0, 0);
    expectPoint(first.toSource(const ContentPoint(450, 250)), 0.5, 0.5);
    expectPoint(second.toSource(const ContentPoint(150, 250)), 0.5, 0.5);
  });
  test('continuous scroll offset affects viewport only', () {
    final t = ViewportTransform(500, 0, 0, 800, 20, -350);
    expectPoint(t.toSource(const ContentPoint(270, 50)), 0.5, 0.5);
  });
  test('resize recomputes contain without changing normalized content', () {
    final a = ViewportTransform.centered(
      sourceWidth: 1000,
      sourceHeight: 2000,
      viewportWidth: 800,
      viewportHeight: 600,
      scale: 0.3,
    );
    final b = ViewportTransform.centered(
      sourceWidth: 1000,
      sourceHeight: 2000,
      viewportWidth: 500,
      viewportHeight: 900,
      scale: 0.45,
    );
    final p = a.toSource(const ContentPoint(325, 450));
    expectPoint(b.toViewport(p), 137.5, 675);
  });
}

void expectPoint(ContentPoint p, double x, double y) {
  expect(p.x, closeTo(x, 1e-9));
  expect(p.y, closeTo(y, 1e-9));
}
