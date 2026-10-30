import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:venera_next/features/annotations/application/annotation_export_service.dart';
import 'package:venera_next/features/annotations/application/annotation_session.dart';
import 'package:venera_next/features/annotations/domain/annotation.dart';
import 'package:venera_next/features/annotations/domain/source_document.dart';
import 'package:venera_next/foundation/comic_source_provenance.dart';
import 'package:venera_next/foundation/pdf_page_geometry.dart';
import 'package:venera_next/foundation/pdf_source_adapter.dart';

class PdfOriginalUnavailable implements Exception {
  const PdfOriginalUnavailable(this.message, this.status);
  final String message, status;
}

class PdfAnnotationCropPlan {
  PdfAnnotationCropPlan(
    PdfPageGeometry page,
    Annotation note, {
    this.dpi = 300,
  }) {
    if (!dpi.isFinite || dpi < 72 || dpi > 1200) {
      throw ArgumentError('Invalid PDF export resolution');
    }
    fullWidth = (page.width * dpi / 72).ceil();
    fullHeight = (page.height * dpi / 72).ceil();
    if (fullWidth < 1 ||
        fullHeight < 1 ||
        fullWidth > 100000 ||
        fullHeight > 100000) {
      throw const FormatException('PDF 页面超过可渲染的尺寸上限');
    }
    final rect = note.rect;
    x = ((rect?.x0 ?? 0) * fullWidth).floor().clamp(0, fullWidth - 1);
    y = ((rect?.y0 ?? 0) * fullHeight).floor().clamp(0, fullHeight - 1);
    width = math.max(
      1,
      ((rect?.x1 ?? 1) * fullWidth).ceil().clamp(1, fullWidth) - x,
    );
    height = math.max(
      1,
      ((rect?.y1 ?? 1) * fullHeight).ceil().clamp(1, fullHeight) - y,
    );
    if (width * height > 40000000) {
      throw const FormatException('PDF 选区超过四千万像素，请缩小选区后导出');
    }
  }
  final double dpi;
  late final int fullWidth, fullHeight, x, y, width, height;
}

Future<ResolvedAnnotationImage> resolvePdfAnnotationImage(
  AnnotationSession session,
  Annotation note,
  AnnotationSourcePage sourcePage, {
  bool Function()? isCancelled,
}) async {
  void check() {
    if (isCancelled?.call() ?? false) throw const AnnotationExportCancelled();
  }

  check();
  final original = session.sourceDocument?.source;
  if (original == null || original.kind != 'pdf') {
    throw StateError('PDF 原始来源未关联');
  }
  final geometry = PdfPageGeometry.fromJson(sourcePage.locator);
  final retained = sourcePage.locator['retainedSourcePath'];
  final candidates = <File>[];
  if (retained is String) {
    final uri = session.assetUriOf?.call(retained);
    if (uri == null || !uri.startsWith('file://')) {
      throw StateError('PDF 原件副本无法解析');
    }
    // Imported image keys carry raw paths; external source URIs are escaped.
    candidates.add(File(uri.substring(7)));
  }
  candidates.add(_externalPdfFile(original.uri));
  File? verified;
  var changed = false;
  final seen = <String>{};
  for (final candidate in candidates) {
    if (!seen.add(candidate.absolute.path)) continue;
    final exists = await candidate.exists();
    check();
    if (!exists) continue;
    final fingerprint = await ComicSourceProvenance.fingerprint(candidate);
    check();
    if (fingerprint['size'] == original.size &&
        fingerprint['sha256'] == original.sha256) {
      verified = candidate;
      break;
    }
    changed = true;
  }
  if (verified == null) {
    throw PdfOriginalUnavailable(
      changed
          ? 'PDF 原件内容已变化，使用已校验的导入渲染缓存；笔记仍保留'
          : 'PDF 原件已失联，使用导入时的渲染缓存；可重新关联原件恢复原质量导出',
      changed ? 'changed' : 'missing',
    );
  }
  final file = verified;
  Future<void> verify() async {
    final fingerprint = await ComicSourceProvenance.fingerprint(file);
    check();
    if (fingerprint['size'] != original.size ||
        fingerprint['sha256'] != original.sha256) {
      throw const PdfOriginalUnavailable(
        'PDF 原件内容已变化，使用已校验的导入渲染缓存；笔记仍保留',
        'changed',
      );
    }
  }

  await pdfrxFlutterInitialize();
  check();
  final document = await PdfDocument.openFile(file.path);
  try {
    check();
    if (geometry.pageIndex >= document.pages.length) {
      throw const FormatException('PDF 原件页索引已失效');
    }
    final actual = await readPdfPageGeometry(document, geometry.pageIndex);
    check();
    if (!geometry.matches(actual)) {
      throw const PdfOriginalUnavailable(
        'PDF 页面几何与导入记录不一致，使用导入渲染缓存；需要重新关联',
        'relink_required',
      );
    }
    final plan = PdfAnnotationCropPlan(actual, note);
    // Both import and export use pdfrx's already rotated effective page box.
    // Applying CropBox offsets or /Rotate here again would crop the wrong area.
    final rendered = await document.pages[geometry.pageIndex].render(
      x: plan.x,
      y: plan.y,
      width: plan.width,
      height: plan.height,
      fullWidth: plan.fullWidth.toDouble(),
      fullHeight: plan.fullHeight.toDouble(),
    );
    if (rendered == null) {
      check();
      throw StateError('PDF 原件选区渲染失败');
    }
    try {
      check();
      if (rendered.width != plan.width || rendered.height != plan.height) {
        throw StateError('PDF 选区返回了不完整的像素');
      }
      final bytes = await _encodePdfPng(
        rendered.pixels,
        rendered.width,
        rendered.height,
      );
      check();
      await verify();
      session.setSourceStatus('available');
      return ResolvedAnnotationImage(
        bytes: bytes,
        quality: AnnotationImageQuality.original,
        alreadyCropped: true,
        provenance: {
          'kind': 'pdfOriginalRender',
          ...geometry.toJson(),
          'sourceSha256': original.sha256,
          'fileName': p.basename(file.path),
          'dpi': plan.dpi,
          'rasterRect': {
            'x': plan.x,
            'y': plan.y,
            'width': plan.width,
            'height': plan.height,
            'fullWidth': plan.fullWidth,
            'fullHeight': plan.fullHeight,
          },
        },
      );
    } finally {
      rendered.dispose();
    }
  } finally {
    await document.dispose();
  }
}

File _externalPdfFile(String value) {
  final uri = Uri.parse(value);
  if (uri.scheme != 'file' || uri.host.isNotEmpty && uri.host != 'localhost') {
    throw StateError('仅支持本地 PDF 原件');
  }
  return File.fromUri(uri);
}

// Keep native document/image handles out of the encoding isolate's closure.
Future<Uint8List> _encodePdfPng(Uint8List pixels, int width, int height) =>
    Isolate.run(
      () => image.encodePng(
        image.Image.fromBytes(
          width: width,
          height: height,
          bytes: pixels.buffer,
          bytesOffset: pixels.offsetInBytes,
          order: image.ChannelOrder.bgra,
        ),
      ),
    );
