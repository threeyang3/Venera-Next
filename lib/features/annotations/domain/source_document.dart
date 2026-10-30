import 'annotation.dart';

class AnnotationPageLocation {
  const AnnotationPageLocation({
    required this.chapter,
    required this.imageNumber,
  });
  final int chapter, imageNumber;
}

class AnnotationDocumentSource {
  const AnnotationDocumentSource({
    required this.kind,
    required this.uri,
    required this.sha256,
    required this.size,
  });
  final String kind, uri, sha256;
  final int size;
}

class AnnotationSourcePage {
  const AnnotationSourcePage({
    required this.anchor,
    required this.sourceIdentity,
    required this.assetUri,
    required this.locator,
  });
  final PageAnchor anchor;
  final String sourceIdentity;
  final String? assetUri;
  final Map<String, Object?> locator;
}

class AnnotationSourceDocument {
  const AnnotationSourceDocument({
    required this.documentId,
    required this.title,
    required this.libraryKey,
    required this.status,
    this.source,
  });
  final String documentId, title, libraryKey, status;
  final AnnotationDocumentSource? source;
}

class RecoverableAnnotationDocument {
  const RecoverableAnnotationDocument({
    required this.documentId,
    required this.title,
    required this.annotationCount,
  });
  final String documentId, title;
  final int annotationCount;
}
