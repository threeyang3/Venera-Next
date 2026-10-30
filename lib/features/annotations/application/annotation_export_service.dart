import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../domain/annotation.dart';
import 'package:venera_next/foundation/annotation_link_contract.dart';

enum AnnotationImageQuality { original, displayCache }

class ResolvedAnnotationImage {
  const ResolvedAnnotationImage({
    required this.bytes,
    required this.quality,
    this.warning,
    this.alreadyCropped = false,
    this.provenance,
  });
  final Uint8List bytes;
  final AnnotationImageQuality quality;
  final String? warning;
  final bool alreadyCropped;
  final Map<String, Object?>? provenance;
}

typedef ResolveAnnotationImage =
    Future<ResolvedAnnotationImage> Function(Annotation note);

class AnnotationExportCancelled implements Exception {
  const AnnotationExportCancelled();
}

class AnnotationExportResult {
  const AnnotationExportResult({
    required this.directory,
    required this.markdownPath,
    required this.annotationCount,
    required this.warnings,
  });
  final String directory, markdownPath;
  final int annotationCount;
  final List<String> warnings;
}

/// Every export is a new complete directory. Existing Markdown is never merged
/// or overwritten; source images are read only and crops are generated on demand.
class AnnotationExportService {
  AnnotationExportService({
    required this.resolveImage,
    String Function()? newId,
  }) : _newId = newId ?? const Uuid().v4;
  final ResolveAnnotationImage resolveImage;
  final String Function() _newId;

  static final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
  static String filename(String title) {
    var value = title.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    value = value.replaceAll(RegExp(r'[. ]+$'), '');
    if (value.isEmpty || value == '.' || value == '..') value = '漫画笔记';
    if (RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
      caseSensitive: false,
    ).hasMatch(value)) {
      value = '_$value';
    }
    final runes = <int>[];
    var bytes = 0;
    for (final rune in value.runes.take(80)) {
      final count = utf8.encode(String.fromCharCode(rune)).length;
      if (bytes + count > 140) break;
      bytes += count;
      runes.add(rune);
    }
    return String.fromCharCodes(runes);
  }

  Future<AnnotationExportResult> export({
    required String destination,
    required String documentId,
    required String title,
    required List<Annotation> annotations,
    bool Function()? isCancelled,
  }) async {
    void check() {
      if (isCancelled?.call() ?? false) throw const AnnotationExportCancelled();
    }

    check();
    final notes = List<Annotation>.unmodifiable(annotations);
    if (notes.isEmpty) throw StateError('没有可导出的批注');
    final ids = <String>{};
    for (final note in notes) {
      if (note.anchor.documentId != documentId ||
          !_safeId.hasMatch(note.id) ||
          !ids.add(note.id)) {
        throw ArgumentError(
          'Invalid, duplicate or cross-document annotation identity',
        );
      }
    }
    final exportId = _newId();
    if (!_safeId.hasMatch(exportId) || exportId.length > 64) {
      throw ArgumentError('Invalid export identity');
    }
    final root = Directory(destination).absolute;
    if (!await root.exists()) {
      throw FileSystemException(
        'Export destination does not exist',
        destination,
      );
    }
    final name = filename(title);
    final output = p.join(root.path, '$name-$exportId');
    if (await FileSystemEntity.type(output, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException(
        'Export destination is already occupied',
        output,
      );
    }
    final staging = await root.createTemp('.comicnotes-export-');
    var committed = false;
    try {
      final assetDir = await Directory(p.join(staging.path, 'assets')).create();
      final markdown = StringBuffer('# ${_inline(title)}\n\n');
      final assets = <String, Object?>{},
          blocks = <String, String>{},
          warnings = <String>{};
      for (final note in notes) {
        check();
        String? assetName;
        String? warning;
        if (note.kind != AnnotationKind.bookmark) {
          final resolved = await resolveImage(note);
          check();
          if (resolved.bytes.length > 256 * 1024 * 1024) {
            throw const FormatException(
              'Image exceeds the 256 MiB export read limit',
            );
          }
          warning = resolved.warning;
          if (resolved.quality == AnnotationImageQuality.displayCache) {
            warning ??= '来源为导入或渲染缓存，尚未关联原始文件';
          }
          if (warning != null) warnings.add(warning);
          final pixels = await _cropInWorker(note, resolved);
          check();
          assetName = '${note.id}.png';
          await File(
            p.join(assetDir.path, assetName),
          ).writeAsBytes(pixels, flush: true);
          assets[note.id] = {
            'path': 'assets/$assetName',
            'sha256': sha256.convert(pixels).toString(),
            'quality': resolved.quality.name,
            'source': ?resolved.provenance,
            'warning': ?warning,
          };
        }
        final block = StringBuffer(
          '<!-- comicnote:annotation:${note.id}:start -->\n',
        );
        block.writeln(
          '### ${_kind(note.kind)} · 第 ${note.anchor.sourceImageNumber} 张原图',
        );
        if (assetName != null) {
          block.writeln(
            '![${note.kind == AnnotationKind.region ? '选区截图' : '页面截图'}](assets/$assetName)\n',
          );
        }
        if (note.text.isNotEmpty) {
          block.writeln(
            '${note.text.replaceAll('<!-- comicnote:', '&lt;!-- comicnote:')}\n',
          );
        }
        if (note.tags.isNotEmpty) {
          block.writeln('标签：${note.tags.map(_inline).join('、')}\n');
        }
        block.writeln(
          '来源：《${_inline(title)}》，章节 ${_inline(note.anchor.chapterId)}，第 ${note.anchor.sourceImageNumber} 张原图  ',
        );
        if (warning != null) block.writeln('> ${_inline(warning)}\n');
        final link = AnnotationLink(
          documentId: documentId,
          annotationId: note.id,
        ).toUri();
        block.writeln('[返回漫画批注]($link)');
        block.writeln('<!-- comicnote:annotation:${note.id}:end -->');
        final value = block.toString();
        blocks[note.id] = sha256.convert(utf8.encode(value)).toString();
        markdown.writeln(value);
      }
      check();
      final mdName = '$name.md';
      await File(
        p.join(staging.path, mdName),
      ).writeAsString(markdown.toString(), flush: true);
      await File(p.join(staging.path, 'manifest.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'schemaVersion': 1,
          'exportId': exportId,
          'documentId': documentId,
          'title': title,
          'exportedAt': DateTime.now().toUtc().toIso8601String(),
          'annotations': notes.map((n) => n.toJson()).toList(),
          'assets': assets,
          'managedBlockHashes': blocks,
        }),
        flush: true,
      );
      check();
      // The rename publishes the verified complete set, on the same filesystem.
      for (final entry in assets.values.cast<Map<String, Object?>>()) {
        if (!await File(
          p.join(staging.path, entry['path'] as String),
        ).exists()) {
          throw StateError('Missing staged image');
        }
      }
      await staging.rename(output);
      committed = true;
      return AnnotationExportResult(
        directory: output,
        markdownPath: p.join(output, mdName),
        annotationCount: notes.length,
        warnings: List.unmodifiable(warnings),
      );
    } finally {
      if (!committed && await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }

  static String _kind(AnnotationKind kind) => switch (kind) {
    AnnotationKind.region => '区域批注',
    AnnotationKind.pageNote => '整页笔记',
    AnnotationKind.bookmark => '书签',
  };
  static String _inline(String value) => value
      .replaceAll(RegExp(r'[\r\n]'), ' ')
      .replaceAllMapped(RegExp(r'[\\`*_[\]<>#]'), (m) => '\\${m[0]}');
}

Future<Uint8List> _cropInWorker(
  Annotation note,
  ResolvedAnnotationImage resolved,
) => Isolate.run(() => _crop(note, resolved));

Uint8List _crop(Annotation note, ResolvedAnnotationImage resolved) {
  // Read dimensions before allocating the full image. Reject excessive input
  // explicitly instead of unexpectedly exhausting memory during export.
  final decoder = image.findDecoderForData(resolved.bytes);
  final info = decoder?.startDecode(resolved.bytes);
  if (decoder == null ||
      info == null ||
      info.width < 1 ||
      info.height < 1 ||
      info.width * info.height > 40000000) {
    throw const FormatException('图片无法解码或超过四千万像素的导出上限');
  }
  if (info.numFrames > 1) throw const FormatException('暂不支持动态图页面的批注截图导出');
  final frame = decoder.decodeFrame(0);
  if (frame == null) throw const FormatException('Image decoding failed');
  final original = image.bakeOrientation(frame);
  if (!resolved.alreadyCropped &&
      ((original.width - note.anchor.sourceWidth).abs() > 1 ||
          (original.height - note.anchor.sourceHeight).abs() > 1)) {
    throw StateError(
      'Source dimensions no longer match the annotation; relink the original before exporting',
    );
  }
  final rect = note.rect;
  if (rect == null || resolved.alreadyCropped) return image.encodePng(original);
  final x0 = (rect.x0 * original.width).floor().clamp(0, original.width - 1);
  final y0 = (rect.y0 * original.height).floor().clamp(0, original.height - 1);
  final x1 = math.max(
    x0 + 1,
    (rect.x1 * original.width).ceil().clamp(1, original.width),
  );
  final y1 = math.max(
    y0 + 1,
    (rect.y1 * original.height).ceil().clamp(1, original.height),
  );
  return image.encodePng(
    image.copyCrop(original, x: x0, y: y0, width: x1 - x0, height: y1 - y0),
  );
}
