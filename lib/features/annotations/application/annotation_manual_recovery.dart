import 'dart:typed_data';
import '../domain/annotation.dart';
import '../domain/source_document.dart';

/// Runtime-verified target images for an explicit one-to-one page review.
/// Commit rechecks library ownership, file bytes and the database snapshot.
abstract class AnnotationManualRecoveryPreview {
  AnnotationSourceDocument get previous;
  List<AnnotationSourcePage> get previousPages;
  List<Annotation> get annotations;
  List<AnnotationManualTargetPage> get targets;
  Future<bool> commit({
    required Map<String, String> pageMapping,
    required bool Function() isCurrent,
  });
  Future<void> dispose();
}

class AnnotationManualTargetPage {
  const AnnotationManualTargetPage({
    required this.page,
    required this.thumbnail,
  });
  final AnnotationSourcePage page;
  final Uint8List thumbnail;
}
