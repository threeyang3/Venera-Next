/// A verified private snapshot. Callers must dispose it on every exit path.
abstract class AnnotationRestorePreview {
  int get documentCount;
  int get annotationCount;
  int get existingDocumentCount;
  Future<AnnotationRestoreResult> restore({bool Function()? isCancelled});
  Future<void> dispose();
}

class AnnotationRestoreResult {
  const AnnotationRestoreResult(this.importedDocuments, this.skippedDocuments);
  final int importedDocuments, skippedDocuments;
}
