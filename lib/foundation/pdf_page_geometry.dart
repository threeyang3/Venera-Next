/// PDF boxes use unrotated PDF points, in [left, bottom, right, top] order.
/// Display dimensions include the PDF's effective crop and page rotation,
/// exactly as the importer and original renderer present the page.
class PdfPageGeometry {
  PdfPageGeometry({
    required this.pageIndex,
    required this.width,
    required this.height,
    required this.rotation,
    required List<double> mediaBox,
    List<double>? cropBox,
    required List<double> effectiveBox,
  }) : mediaBox = List.unmodifiable(mediaBox),
       cropBox = cropBox == null ? null : List.unmodifiable(cropBox),
       effectiveBox = List.unmodifiable(effectiveBox) {
    if (pageIndex < 0 ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0 ||
        !{0, 90, 180, 270}.contains(rotation) ||
        !_validBox(this.mediaBox) ||
        !_validBox(this.effectiveBox) ||
        (this.cropBox != null && !_validBox(this.cropBox!))) {
      throw const FormatException('Invalid PDF source geometry');
    }
  }
  final int pageIndex, rotation;
  final double width, height;
  final List<double> mediaBox, effectiveBox;
  final List<double>? cropBox;
  static bool _validBox(List<double> box) =>
      box.length == 4 &&
      box.every((v) => v.isFinite) &&
      box[0] < box[2] &&
      box[1] < box[3];
  Map<String, Object?> toJson() => {
    'pageIndex': pageIndex,
    'widthPoints': width,
    'heightPoints': height,
    'rotation': rotation,
    'mediaBox': mediaBox,
    'cropBox': cropBox,
    'effectiveBox': effectiveBox,
    'pdfCoordinateSpace': 'pdfrx-rotated-effective-box-v1',
  };
  factory PdfPageGeometry.fromJson(Map<String, Object?> json) {
    List<double> box(String key) =>
        (json[key] as List).map((v) => (v as num).toDouble()).toList();
    if (json['pdfCoordinateSpace'] != 'pdfrx-rotated-effective-box-v1') {
      throw const FormatException('Unknown PDF coordinate space');
    }
    return PdfPageGeometry(
      pageIndex: json['pageIndex'] as int,
      width: (json['widthPoints'] as num).toDouble(),
      height: (json['heightPoints'] as num).toDouble(),
      rotation: json['rotation'] as int,
      mediaBox: box('mediaBox'),
      cropBox: json['cropBox'] == null ? null : box('cropBox'),
      effectiveBox: box('effectiveBox'),
    );
  }
  bool matches(PdfPageGeometry other) {
    bool same(List<double> a, List<double> b) =>
        a.length == b.length &&
        List.generate(
          a.length,
          (i) => (a[i] - b[i]).abs() < .001,
        ).every((v) => v);
    return pageIndex == other.pageIndex &&
        rotation == other.rotation &&
        (width - other.width).abs() < .001 &&
        (height - other.height).abs() < .001 &&
        same(mediaBox, other.mediaBox) &&
        same(effectiveBox, other.effectiveBox) &&
        (cropBox == null
            ? other.cropBox == null
            : other.cropBox != null && same(cropBox!, other.cropBox!));
  }
}
