import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:venera_next/features/annotations/application/annotation_link_resolver.dart';
import 'package:venera_next/features/annotations/data/annotation_repository.dart';
import 'package:venera_next/features/annotations/domain/source_document.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/foundation/annotation_link_contract.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/comic_type.dart';

typedef LocalAnnotationLocation = AnnotationPageLocation;

class LocalAnnotationTarget {
  const LocalAnnotationTarget({
    required this.comic,
    required this.resolved,
    required this.location,
  });
  final LocalComic comic;
  final ResolvedAnnotationLink resolved;
  final LocalAnnotationLocation location;
}

Future<LocalAnnotationLocation> locateLocalAnnotation({
  required LocalComic comic,
  required AnnotationSourcePage page,
  required Future<List<String>> Function(Object chapter) images,
}) async {
  var chapter = 1;
  if (comic.chapters case final chapters?) {
    final matches = <int>[];
    for (var i = 1; i <= chapters.length; i++) {
      if (chapters.positionAt(i).id == page.anchor.chapterId) matches.add(i);
    }
    if (matches.length != 1) throw StateError('来源章节缺失或不唯一，需要重新关联');
    chapter = matches.single;
  } else if (page.anchor.chapterId != '0') {
    throw StateError('漫画的章节结构已改变，需要重新关联');
  }
  final identity = page.sourceIdentity;
  if (identity.isEmpty ||
      identity.contains('\\') ||
      p.posix.isAbsolute(identity) ||
      identity.split('/').any((v) => v.isEmpty || v == '.' || v == '..')) {
    throw const FormatException('Invalid source image identity');
  }
  final root = p.normalize(p.absolute(comic.baseDir));
  final target = p.normalize(p.joinAll([root, ...identity.split('/')]));
  if (!p.isWithin(root, target)) {
    throw const FormatException('Source image is outside the comic');
  }
  final current = await images(comic.hasChapters ? page.anchor.chapterId : 1);
  final image = current.indexWhere(
    (value) =>
        value.startsWith('file://') &&
        p.equals(p.normalize(p.absolute(value.substring(7))), target),
  );
  if (image < 0) throw StateError('批注原图已失联，笔记仍保留，请重新关联');
  return LocalAnnotationLocation(chapter: chapter, imageNumber: image + 1);
}

Future<LocalAnnotationTarget> resolveLocalAnnotationLink(
  AnnotationLink link,
) async {
  final path = p.join(App.dataPath, 'annotations.db');
  if (!File(path).existsSync()) throw StateError('本机没有批注数据库');
  final store = AnnotationRepository.open(path);
  try {
    final resolved = AnnotationLinkResolver(store).resolve(link);
    final local = LocalManager();
    final comic = _findComic(resolved.document.libraryKey, local);
    final rootBefore = p.normalize(p.absolute(comic.baseDir));
    final location = await locateLocalAnnotation(
      comic: comic,
      page: resolved.page,
      images: (chapter) => local.getImages(comic.id, comic.comicType, chapter),
    );
    if (!identical(LocalManager.current, local) ||
        p.normalize(
              p.absolute(
                _findComic(resolved.document.libraryKey, local).baseDir,
              ),
            ) !=
            rootBefore) {
      throw StateError('漫画库在定位过程中发生变化，请重试');
    }
    final latest = AnnotationLinkResolver(store).resolve(link);
    return LocalAnnotationTarget(
      comic: comic,
      resolved: latest,
      location: location,
    );
  } finally {
    store.close();
  }
}

LocalComic _findComic(String libraryKey, LocalManager local) {
  final key = RegExp(r'^local:(.+):(-?[0-9]+)$').firstMatch(libraryKey);
  if (key == null) throw StateError('此批注尚未关联本地漫画');
  final comic = local.find(key.group(1)!, ComicType.local);
  if (comic == null ||
      comic.createdAt.millisecondsSinceEpoch.toString() != key.group(2)) {
    throw StateError('原漫画已移除或是另一个版本；批注仍保留，需要重新关联');
  }
  return comic;
}

Future<AnnotationPageLocation> locateRegisteredAnnotationPage({
  required String libraryKey,
  required AnnotationSourcePage page,
}) {
  final local = LocalManager();
  final comic = _findComic(libraryKey, local);
  return locateLocalAnnotation(
    comic: comic,
    page: page,
    images: (chapter) => local.getImages(comic.id, comic.comicType, chapter),
  );
}

Future<AnnotationLinkDestination> resolveAnnotationLinkDestination(
  AnnotationLink link,
) async {
  final target = await resolveLocalAnnotationLink(link);
  return AnnotationLinkDestination(
    comicId: target.comic.id,
    createdAtMilliseconds: target.comic.createdAt.millisecondsSinceEpoch,
    chapter: target.location.chapter,
    imageNumber: target.location.imageNumber,
    annotationId: target.resolved.note.id,
  );
}
