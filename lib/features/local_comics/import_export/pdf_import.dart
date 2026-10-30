import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as image;
import 'package:pdfrx/pdfrx.dart';
import 'package:venera_next/features/local_comics/import_export/document_import.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/features/local_comics/local_storage_guard.dart';
import 'package:venera_next/foundation/file_system.dart';
import 'package:venera_next/foundation/persistence_failure.dart';
import 'comic_import_output.dart';
import 'package:venera_next/foundation/comic_source_provenance.dart';
import 'package:venera_next/foundation/pdf_source_adapter.dart';

class _PdfImportSource {
  _PdfImportSource._(this.file, this.fingerprint, this.retainOriginal);
  final File file;
  final Map<String, Object?> fingerprint;
  final bool retainOriginal;
  static Future<_PdfImportSource> capture(
    File file, {
    bool retainOriginal = false,
  }) async => _PdfImportSource._(
    file,
    Map.unmodifiable(await ComicSourceProvenance.fingerprint(file)),
    retainOriginal,
  );
  Future<void> verify() async {
    final current = await ComicSourceProvenance.fingerprint(file);
    if (current['sha256'] != fingerprint['sha256'] ||
        current['size'] != fingerprint['size']) {
      throw const FileSystemException('PDF source changed during import');
    }
  }
}

const double _pdfRenderScale = 3;
const int _pdfRenderMaxEdge = 3000;

// Only pixels cross the isolate boundary; native PDF objects stay with pdfrx.
Uint8List _encodePdfPage(({Uint8List pixels, int width, int height}) page) {
  final decoded = image.Image.fromBytes(
    width: page.width,
    height: page.height,
    bytes: page.pixels.buffer,
    bytesOffset: page.pixels.offsetInBytes,
    order: image.ChannelOrder.bgra,
  );
  return image.encodeJpg(decoded, quality: 92);
}

class PdfRenderSize {
  const PdfRenderSize(this.width, this.height);

  final int width;
  final int height;
}

class PdfPageRenderException implements Exception {
  const PdfPageRenderException(this.page);

  final int page;

  @override
  String toString() => 'Failed to render PDF page $page';
}

PdfRenderSize calculatePdfRenderSize(
  double width,
  double height, {
  double scale = _pdfRenderScale,
  int maxEdge = _pdfRenderMaxEdge,
}) {
  if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
    throw const FormatException('PDF page has an invalid size');
  }
  final longestEdge = math.max(width, height);
  final actualScale = math.min(scale, maxEdge / longestEdge);
  return PdfRenderSize(
    math.max(1, (width * actualScale).round()),
    math.max(1, (height * actualScale).round()),
  );
}

abstract final class PdfComicImporter {
  static Future<LocalComic> import(
    File file, {
    String? title,
    DocumentImportProgress? onProgress,
    DocumentImportCancellation? cancellation,
    Future<void> Function(LocalComic comic)? registerComic,
    bool retainOriginal = false,
  }) async {
    cancellation?.throwIfCancelled();
    final source = const bool.fromEnvironment('COMICNOTES_POC')
        ? await _PdfImportSource.capture(file, retainOriginal: retainOriginal)
        : null;
    await pdfrxFlutterInitialize();
    late final PdfDocument document;
    try {
      document = await PdfDocument.openFile(file.path);
    } on PdfPasswordException {
      throw const FormatException(
        'Password-protected PDF files are not supported',
      );
    }
    return _importCapturedDocument(
      document,
      title: title ?? file.basenameWithoutExt,
      onProgress: onProgress,
      cancellation: cancellation,
      registerComic: registerComic,
      source: source,
    );
  }

  /// Takes ownership of [document] and closes it even if conversion fails.
  /// A failing registrar must report notCommitted to permit deleting output.
  /// Unknown or committed failures retain pages for recovery.
  static Future<LocalComic> importDocument(
    PdfDocument document, {
    required String title,
    DocumentImportProgress? onProgress,
    DocumentImportCancellation? cancellation,
    Future<void> Function(LocalComic comic)? registerComic,
  }) => _importCapturedDocument(
    document,
    title: title,
    onProgress: onProgress,
    cancellation: cancellation,
    registerComic: registerComic,
  );

  // Only the file entry point can pair a captured fingerprint with a document;
  // callers of importDocument cannot accidentally bind another PDF's identity.
  static Future<LocalComic> _importCapturedDocument(
    PdfDocument document, {
    required String title,
    DocumentImportProgress? onProgress,
    DocumentImportCancellation? cancellation,
    Future<void> Function(LocalComic comic)? registerComic,
    _PdfImportSource? source,
  }) async {
    var entered = false;
    try {
      return await LocalComicStorageGuard.instance.runImport(() {
        entered = true;
        return _importDocument(
          document,
          title: title,
          onProgress: onProgress,
          cancellation: cancellation,
          registerComic: registerComic,
          source: source,
        );
      });
    } catch (error, stack) {
      if (!entered) {
        await _disposeDocument(
          document,
          operationError: error,
          operationStack: stack,
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  static Future<LocalComic> _importDocument(
    PdfDocument document, {
    required String title,
    DocumentImportProgress? onProgress,
    DocumentImportCancellation? cancellation,
    Future<void> Function(LocalComic comic)? registerComic,
    _PdfImportSource? source,
  }) async {
    DocumentImportSession? session;
    Object? operationError;
    StackTrace? operationStack;
    try {
      try {
        cancellation?.throwIfCancelled();
        if (document.pages.isEmpty) {
          throw const FormatException('PDF contains no pages');
        }

        session = DocumentImportSession.start(title);
        final retainedPath = source?.retainOriginal == true
            ? '.comicnotes-original.pdf'
            : null;
        final provenance = source == null
            ? null
            : ComicSourceProvenance(
                source: {
                  'kind': 'pdf',
                  'uri': source.file.absolute.uri.toString(),
                  ...source.fingerprint,
                  'retainedPath': ?retainedPath,
                },
                pages: {},
              );
        if (retainedPath != null) {
          final copy = await source!.file.copy(
            FilePath.join(session.directory.path, retainedPath),
          );
          final copyFingerprint = await ComicSourceProvenance.fingerprint(copy);
          if (copyFingerprint['sha256'] != source.fingerprint['sha256'] ||
              copyFingerprint['size'] != source.fingerprint['size']) {
            throw const FileSystemException(
              'Retained PDF is not a complete original copy',
            );
          }
        }
        final total = document.pages.length;
        onProgress?.call(0, total);
        for (var i = 0; i < total; i++) {
          cancellation?.throwIfCancelled();
          final page = document.pages[i];
          final geometry = provenance == null
              ? null
              : await readPdfPageGeometry(document, i);
          final size = calculatePdfRenderSize(page.width, page.height);
          final rendered = await page.render(
            fullWidth: size.width.toDouble(),
            fullHeight: size.height.toDouble(),
          );
          if (rendered == null) {
            cancellation?.throwIfCancelled();
            throw PdfPageRenderException(i + 1);
          }
          try {
            cancellation?.throwIfCancelled();
            final encoded = await compute(_encodePdfPage, (
              pixels: rendered.pixels,
              width: rendered.width,
              height: rendered.height,
            ), debugLabel: 'PDF JPEG encoding');
            cancellation?.throwIfCancelled();
            final pageFile = File(
              session.pagePath(pageIndex: i + 1, extension: 'jpg'),
            );
            await pageFile.writeAsBytes(encoded);
            if (provenance != null) {
              provenance.pages[pageFile.name] = {
                'kind': 'pdfPage',
                ...geometry!.toJson(),
                ...await ComicSourceProvenance.fingerprint(pageFile),
                'retainedSourcePath': ?retainedPath,
              };
            }
            if (i == 0) {
              await pageFile.copyMem(
                FilePath.join(session.directory.path, 'cover.jpg'),
              );
            }
          } finally {
            rendered.dispose();
          }
          onProgress?.call(i + 1, total);
        }

        cancellation?.throwIfCancelled();
        final comic = session.finish(
          author: '',
          tags: const [],
          cover: 'cover.jpg',
        );
        if (provenance != null) {
          await source!.verify();
          cancellation?.throwIfCancelled();
          await provenance.write(session.directory);
        }
        await session.output.register(comic, registerComic);
        return comic;
      } catch (error, stack) {
        if (session != null) return await session.output.fail(error, stack);
        Error.throwWithStackTrace(error, stack);
      }
    } catch (error, stack) {
      operationError = error;
      operationStack = stack;
      rethrow;
    } finally {
      await _disposeDocument(
        document,
        output: session?.output,
        operationError: operationError,
        operationStack: operationStack,
      );
    }
  }

  static Future<void> _disposeDocument(
    PdfDocument document, {
    ComicImportOutput? output,
    Object? operationError,
    StackTrace? operationStack,
  }) async {
    try {
      await document.dispose();
    } catch (error, stack) {
      if (operationError != null && output != null) {
        output.throwWithCleanup(operationError, operationStack!, error, stack);
      }
      final persistence = operationError is PersistenceFailure
          ? operationError
          : null;
      Error.throwWithStackTrace(
        PersistenceFailure(
          commitState:
              output?.commitState ?? PersistenceCommitState.notCommitted,
          cause: persistence?.cause ?? operationError ?? error,
          stackTrace: persistence?.stackTrace ?? operationStack ?? stack,
          cleanupFailures: [
            ...?persistence?.cleanupFailures,
            if (operationError != null) (error: error, stackTrace: stack),
          ],
        ),
        persistence?.stackTrace ?? operationStack ?? stack,
      );
    }
  }
}
