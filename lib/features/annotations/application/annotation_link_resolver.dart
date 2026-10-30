import 'package:venera_next/foundation/annotation_link_contract.dart';
import '../domain/annotation.dart';
import '../domain/source_document.dart';
import 'annotation_store.dart';

class ResolvedAnnotationLink {
  const ResolvedAnnotationLink({
    required this.document,
    required this.note,
    required this.page,
  });
  final AnnotationSourceDocument document;
  final Annotation note;
  final AnnotationSourcePage page;
}

class AnnotationLinkResolver {
  const AnnotationLinkResolver(this.store);
  final AnnotationStore store;
  ResolvedAnnotationLink resolve(AnnotationLink link) {
    final document = store.document(link.documentId);
    final note = store
        .list(link.documentId)
        .where((n) => n.id == link.annotationId)
        .firstOrNull;
    if (note == null) throw StateError('批注不存在或已被删除');
    final page = store.sourcePage(link.documentId, note.anchor.pageId);
    if (page == null) throw StateError('批注的原图片身份缺失，需要重新关联');
    return ResolvedAnnotationLink(document: document, note: note, page: page);
  }
}
