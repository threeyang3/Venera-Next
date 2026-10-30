import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as native;
import 'package:pdfrx/pdfrx.dart';
import 'pdf_page_geometry.dart';

/// pdfrx suspends its native worker while this callback owns the handle.
/// No handle escapes; these calls read page boxes without changing the PDF.
Future<PdfPageGeometry> readPdfPageGeometry(
  PdfDocument document,
  int index,
) async {
  if (index < 0 || index >= document.pages.length) {
    throw RangeError.index(index, document.pages);
  }
  final page = document.pages[index];
  return document.useNativeDocumentHandle((address) {
    final pdfium = native.getPdfium(modulePath: Pdfrx.pdfiumModulePath);
    final handle = pdfium.FPDF_LoadPage(Pointer.fromAddress(address), index);
    if (handle.address == 0) throw StateError('Cannot read PDF page geometry');
    try {
      return using((arena) {
        final values = arena<Float>(4);
        List<double>? readBox(
          int Function(
            native.FPDF_PAGE,
            Pointer<Float>,
            Pointer<Float>,
            Pointer<Float>,
            Pointer<Float>,
          )
          read,
        ) {
          if (read(handle, values, values + 1, values + 2, values + 3) == 0) {
            return null;
          }
          return List.generate(4, (i) => values[i]);
        }

        final media = readBox(pdfium.FPDFPage_GetMediaBox);
        final crop = readBox(pdfium.FPDFPage_GetCropBox);
        final bounds = arena<native.FS_RECTF>();
        if (media == null ||
            pdfium.FPDF_GetPageBoundingBox(handle, bounds) == 0) {
          throw StateError('PDF page has no valid content box');
        }
        return PdfPageGeometry(
          pageIndex: index,
          width: page.width,
          height: page.height,
          rotation: page.rotation.index * 90,
          mediaBox: media,
          cropBox: crop,
          effectiveBox: [
            bounds.ref.left,
            bounds.ref.bottom,
            bounds.ref.right,
            bounds.ref.top,
          ],
        );
      });
    } finally {
      pdfium.FPDF_ClosePage(handle);
    }
  });
}
