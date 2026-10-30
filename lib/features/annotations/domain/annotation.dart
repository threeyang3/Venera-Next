import 'geometry.dart';

enum AnnotationKind { region, pageNote, bookmark }

/// UUIDs refer to source images, never to a grouped reader display page.
class PageAnchor {
  const PageAnchor({
    required this.documentId,
    required this.pageId,
    required this.chapterId,
    required this.sourceImageNumber,
    required this.sourceWidth,
    required this.sourceHeight,
  });
  final String documentId, pageId, chapterId;
  final int sourceImageNumber;
  final double sourceWidth, sourceHeight;
  static const coordinateSpaceVersion = 1;
}

class Annotation {
  Annotation({
    required this.id,
    required this.anchor,
    required this.kind,
    this.rect,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    Iterable<String> tags = const [],
  }) : tags = normalizeTags(tags) {
    if ((kind == AnnotationKind.region) != (rect != null)) {
      throw ArgumentError('Only region annotations have a rectangle');
    }
  }
  final String id;
  final PageAnchor anchor;
  final AnnotationKind kind;
  final ContentRect? rect;
  final String text;
  final DateTime createdAt, updatedAt;
  final List<String> tags;

  static List<String> normalizeTags(Iterable<String> values) {
    final tags =
        values.map((v) => v.trim()).where((v) => v.isNotEmpty).toSet().toList()
          ..sort();
    if (tags.length > 32 ||
        tags.any(
          (t) => t.runes.length > 64 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(t),
        )) {
      throw ArgumentError('最多 32 个标签，每个不超过 64 字且不能包含控制字符');
    }
    return List.unmodifiable(tags);
  }

  Annotation withAnchor(PageAnchor page) {
    if (page.documentId != anchor.documentId || page.pageId != anchor.pageId) {
      throw ArgumentError('Source metadata refresh cannot move an annotation');
    }
    return Annotation(
      id: id,
      anchor: page,
      kind: kind,
      rect: rect,
      text: text,
      createdAt: createdAt,
      updatedAt: updatedAt,
      tags: tags,
    );
  }

  Annotation withText(String value, DateTime now) => Annotation(
    id: id,
    anchor: anchor,
    kind: kind,
    rect: rect,
    text: value,
    createdAt: createdAt,
    updatedAt: now,
    tags: tags,
  );

  Annotation withTags(Iterable<String> values, DateTime now) => Annotation(
    id: id,
    anchor: anchor,
    kind: kind,
    rect: rect,
    text: text,
    createdAt: createdAt,
    updatedAt: now,
    tags: values,
  );

  Map<String, Object?> toJson() => {
    'annotationId': id,
    'documentId': anchor.documentId,
    'pageId': anchor.pageId,
    'chapterId': anchor.chapterId,
    'sourceImageNumber': anchor.sourceImageNumber,
    'sourceWidth': anchor.sourceWidth,
    'sourceHeight': anchor.sourceHeight,
    'coordinateSpaceVersion': PageAnchor.coordinateSpaceVersion,
    'kind': kind.name,
    'rect': rect?.toJson(),
    'text': text,
    'tags': tags,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}
