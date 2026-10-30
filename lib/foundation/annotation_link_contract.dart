/// Shared URI contract, independent of reader, storage, and platform widgets.
class AnnotationLink {
  AnnotationLink({required this.documentId, required this.annotationId}) {
    if (!_valid(documentId) || !_valid(annotationId)) {
      throw ArgumentError('Invalid annotation link identity');
    }
  }
  final String documentId, annotationId;
  static bool _valid(String value) =>
      value.trim().isNotEmpty &&
      value.length <= 512 &&
      !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);
  Uri toUri() => Uri(
    scheme: 'comicnotes',
    host: 'open',
    queryParameters: {'document': documentId, 'annotation': annotationId},
  );

  static AnnotationLink? parse(Uri uri) {
    if (uri.scheme != 'comicnotes' ||
        uri.host != 'open' ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return null;
    }
    try {
      final query = uri.queryParametersAll;
      if (query.length != 2 ||
          query['document']?.length != 1 ||
          query['annotation']?.length != 1) {
        return null;
      }
      return AnnotationLink(
        documentId: query['document']!.single,
        annotationId: query['annotation']!.single,
      );
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }
}

class AnnotationLinkDestination {
  const AnnotationLinkDestination({
    required this.comicId,
    required this.createdAtMilliseconds,
    required this.chapter,
    required this.imageNumber,
    required this.annotationId,
  });
  final String comicId, annotationId;
  final int createdAtMilliseconds, chapter, imageNumber;
}

typedef ResolveAnnotationLink =
    Future<AnnotationLinkDestination> Function(AnnotationLink link);
