import 'dart:io';
import 'package:venera_next/foundation/comic_source_provenance.dart';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:venera_next/features/annotations/application/annotation_export_service.dart';
import 'package:venera_next/features/annotations/application/annotation_session.dart';
import 'package:venera_next/features/annotations/domain/annotation.dart';
import 'package:venera_next/foundation/file_system.dart'
    show readFileBytesChecked;
import 'annotation_pdf_assets.dart';

/// Archive pages are copied without transcoding. Their import receipt proves
/// original image bytes even when the source archive is no longer reachable.
/// PDF pages prefer the original renderer; legacy imports and unavailable PDF
/// originals retain explicit cache provenance.
Future<ResolvedAnnotationImage> resolveLocalAnnotationImage(
  AnnotationSession session,
  Annotation note, {
  bool Function()? isCancelled,
}) async {
  void check() {
    if (isCancelled?.call() ?? false) throw const AnnotationExportCancelled();
  }

  check();
  final page = session.sourcePage(note.anchor);
  String? pdfFallback;
  if (page?.locator['kind'] == 'pdfPage') {
    final cacheUri = page?.assetUri;
    if (cacheUri != null && cacheUri.startsWith('file://')) {
      final cache = File(cacheUri.substring(7));
      if (await cache.exists()) {
        final digest = (await sha256.bind(cache.openRead()).first).toString();
        final length = await cache.length();
        check();
        if (length != page!.locator['size'] ||
            digest != page.locator['sha256']) {
          session.setSourceStatus('changed');
          throw const FileSystemException('用于批注的 PDF 显示缓存已变化，不能确认坐标对应关系；笔记仍保留');
        }
      }
    }
    try {
      return await resolvePdfAnnotationImage(
        session,
        note,
        page!,
        isCancelled: isCancelled,
      );
    } on PdfOriginalUnavailable catch (failure) {
      check();
      session.setSourceStatus(failure.status);
      pdfFallback = failure.message;
    }
  }
  final uri = page?.assetUri;
  if (uri == null || !uri.startsWith('file://')) {
    throw StateError('批注页面没有可读取的本地图片');
  }
  var file = File(uri.substring(7));
  if (!await file.exists() && page?.locator['kind'] == 'folderImage') {
    final source = session.sourceDocument?.source;
    final identity = page!.locator['relativePath'];
    if (source != null &&
        identity is String &&
        ComicSourceProvenance.validRelativePath(identity)) {
      final sourceUri = Uri.parse(source.uri);
      if (sourceUri.scheme == 'file') {
        final directory = Directory.fromUri(sourceUri);
        final original = File(
          p.joinAll([directory.path, ...identity.split('/')]),
        );
        if (await original.exists() &&
            p.isWithin(
              await directory.resolveSymbolicLinks(),
              await original.resolveSymbolicLinks(),
            )) {
          file = original;
        }
      }
    }
  }
  if (!await file.exists()) {
    throw FileSystemException('批注图片已失联，请重新关联漫画后导出', file.path);
  }
  if (await file.length() > 256 * 1024 * 1024) {
    throw const FormatException('图片文件超过 256 MiB 的读取上限');
  }
  // A reader path can never silently escape through an image symlink.
  if (FileSystemEntity.typeSync(file.path, followLinks: false) ==
      FileSystemEntityType.link) {
    throw FileSystemException('请先将链接图片导入漫画库，再导出批注', file.path);
  }
  final bytes = await readFileBytesChecked(file, requireNonEmpty: true);
  check();
  final locator = page!.locator;
  if ({
    'archiveImage',
    'pdfPage',
    'epubImage',
    'folderImage',
  }.contains(locator['kind'])) {
    final digest = await _imageDigest(bytes);
    check();
    if (locator['size'] != bytes.length || locator['sha256'] != digest) {
      session.setSourceStatus('changed');
      throw const FileSystemException('原始图片副本已变化，不能沿用旧坐标导出；笔记仍保留');
    }
    if (locator['kind'] == 'pdfPage') {
      return ResolvedAnnotationImage(
        bytes: bytes,
        quality: AnnotationImageQuality.displayCache,
        warning: pdfFallback,
        provenance: {
          ...locator,
          'kind': 'pdfImportCache',
          'sourceSha256': session.sourceDocument?.source?.sha256,
        },
      );
    }
    return ResolvedAnnotationImage(
      bytes: bytes,
      quality: AnnotationImageQuality.original,
      provenance: {
        ...locator,
        'kind': locator['kind'] == 'folderImage'
            ? 'folderImageOriginal'
            : locator['kind'] == 'epubImage'
            ? 'epubImageCopy'
            : 'archiveImageCopy',
        if (locator['kind'] == 'folderImage')
          'folderSha256': session.sourceDocument?.source?.sha256
        else
          'archiveSha256': session.sourceDocument?.source?.sha256,
      },
    );
  }
  return ResolvedAnnotationImage(
    bytes: bytes,
    quality: AnnotationImageQuality.displayCache,
    warning: '来源为本地导入或渲染缓存，原始文件尚未关联（${p.basename(file.path)}）',
  );
}

// The cancellation callback can capture a Reader and native database. Only the
// image bytes cross this worker boundary.
Future<String> _imageDigest(List<int> bytes) =>
    Isolate.run(() => sha256.convert(bytes).toString());
