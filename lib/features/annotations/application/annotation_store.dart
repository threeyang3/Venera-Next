import '../domain/annotation.dart';
import '../domain/source_document.dart';

/// Synchronous, transactional persistence boundary. A successful return means
/// the write committed; callers update their in-memory view only afterward.
abstract interface class AnnotationStore {
  String openDocument({
    required String libraryKey,
    required String title,
    AnnotationDocumentSource? source,
  });
  PageAnchor resolvePage({
    required String documentId,
    required String chapterId,
    required String sourceIdentity,
    required int imageNumber,
    required double width,
    required double height,
    String? assetUri,
    Map<String, Object?>? locator,
  });
  AnnotationSourcePage? sourcePage(String documentId, String pageId);
  AnnotationSourceDocument document(String documentId);
  void setSourceStatus(String documentId, String status);
  void relocateSource(String documentId, AnnotationDocumentSource source);
  List<Annotation> list(String documentId);
  void put(Annotation note);
  void remove(String documentId, String annotationId);
  void close();
}
