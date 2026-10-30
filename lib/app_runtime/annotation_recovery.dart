import 'dart:convert';
import 'dart:io';
import 'package:venera_next/foundation/folder_source_provenance.dart';
import 'package:path/path.dart' as p;
import 'package:venera_next/features/annotations/application/annotation_session.dart';
import 'package:venera_next/features/annotations/data/annotation_repository.dart';
import 'package:venera_next/features/annotations/domain/annotation.dart';
import 'package:venera_next/features/annotations/domain/source_document.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/foundation/comic_source_provenance.dart';
import 'annotation_navigation.dart';

Set<String> _liveLibraryKeys(LocalManager manager) => manager
    .getComics(LocalSortType.name)
    .where((comic) => comic.comicType == ComicType.local)
    .map(
      (comic) => 'local:${comic.id}:${comic.createdAt.millisecondsSinceEpoch}',
    )
    .toSet();

bool _sameSource(AnnotationSourceDocument a, AnnotationSourceDocument b) =>
    a.source != null &&
    b.source != null &&
    a.source!.kind == b.source!.kind &&
    a.source!.sha256 == b.source!.sha256 &&
    a.source!.size == b.source!.size;

Future<List<RecoverableAnnotationDocument>> findRecoverableAnnotations({
  required AnnotationSession session,
}) async {
  final store = AnnotationRepository.open(
    p.join(App.dataPath, 'annotations.db'),
  );
  try {
    final target = store.document(session.documentId);
    if (store.list(target.documentId).isNotEmpty) {
      throw StateError('当前漫画已有批注，请另行导出或保留，不会覆盖合并');
    }
    final live = _liveLibraryKeys(LocalManager());
    return [
      for (final doc in store.documents())
        if (doc.documentId != target.documentId &&
            !live.contains(doc.libraryKey) &&
            _sameSource(doc, target) &&
            store.list(doc.documentId).isNotEmpty)
          RecoverableAnnotationDocument(
            documentId: doc.documentId,
            title: doc.title,
            annotationCount: store.list(doc.documentId).length,
          ),
    ];
  } finally {
    store.close();
  }
}

/// Restores only an identical imported source with unchanged deterministic page
/// identities. A different importer/layout requires explicit page remapping.
Future<bool> recoverLocalAnnotations({
  required AnnotationSession session,
  required String documentId,
  required bool Function() isCurrent,
}) async {
  if (!isCurrent()) return false;
  final manager = LocalManager();
  final store = AnnotationRepository.open(
    p.join(App.dataPath, 'annotations.db'),
  );
  try {
    final previous = store.document(documentId),
        target = store.document(session.documentId);
    if (!_sameSource(previous, target) ||
        _liveLibraryKeys(manager).contains(previous.libraryKey)) {
      throw StateError('旧批注仍绑定其他漫画，或原件指纹不同，未进行恢复');
    }
    final comic = manager
        .getComics(LocalSortType.name)
        .where(
          (comic) =>
              comic.comicType == ComicType.local &&
              'local:${comic.id}:${comic.createdAt.millisecondsSinceEpoch}' ==
                  target.libraryKey,
        )
        .single;
    final root = p.normalize(p.absolute(comic.baseDir));
    final receipt =
        ComicSourceProvenance.readFile(
          folderSourceReceiptFile(App.dataPath, target.libraryKey),
        ) ??
        ComicSourceProvenance.read(Directory(root));
    if (receipt == null ||
        receipt.source['kind'] != target.source!.kind ||
        receipt.source['sha256'] != target.source!.sha256 ||
        receipt.source['size'] != target.source!.size) {
      throw StateError('当前导入来源凭据不匹配，未进行恢复');
    }
    final oldPages = store.pages(previous.documentId),
        resolved = <String, AnnotationSourcePage>{};
    final imageLists = <Object, Future<List<String>>>{};
    for (final page in oldPages) {
      final locator = receipt.pages[page.sourceIdentity];
      if (locator == null ||
          !{
            'archiveImage',
            'folderImage',
            'epubImage',
            'pdfPage',
          }.contains(page.locator['kind'])) {
        throw StateError('来源页没有可靠原件映射，需要手动重新关联');
      }
      // Every old locator field must match; retained-copy choice may differ.
      for (final key in page.locator.keys.where(
        (key) => key != 'retainedSourcePath' && key != 'manualMapping',
      )) {
        if (jsonEncode(page.locator[key]) != jsonEncode(locator[key])) {
          throw StateError('来源页映射与旧导入不同，未恢复旧坐标');
        }
      }
      final uri = session.assetUriOf?.call(page.sourceIdentity);
      if (uri == null || !uri.startsWith('file://')) {
        throw StateError('来源页路径无法解析');
      }
      final fingerprint = await ComicSourceProvenance.fingerprint(
        File(uri.substring(7)),
      );
      if (!isCurrent()) return false;
      if (fingerprint['sha256'] != locator['sha256'] ||
          fingerprint['size'] != locator['size']) {
        throw StateError('当前图片内容与导入凭据不符，未恢复旧坐标');
      }
      final location = await locateLocalAnnotation(
        comic: comic,
        page: page,
        images: (chapter) => imageLists.putIfAbsent(
          chapter,
          () => manager.getImages(comic.id, comic.comicType, chapter),
        ),
      );
      if (!isCurrent()) return false;
      resolved[page.anchor.pageId] = AnnotationSourcePage(
        anchor: PageAnchor(
          documentId: previous.documentId,
          pageId: page.anchor.pageId,
          chapterId: page.anchor.chapterId,
          sourceImageNumber: location.imageNumber,
          sourceWidth: page.anchor.sourceWidth,
          sourceHeight: page.anchor.sourceHeight,
        ),
        sourceIdentity: page.sourceIdentity,
        assetUri: uri,
        locator: {...locator, 'manualMapping': ?page.locator['manualMapping']},
      );
    }
    if (!isCurrent()) return false;
    if (!identical(LocalManager.current, manager) ||
        _liveLibraryKeys(manager).contains(previous.libraryKey) ||
        !manager
            .getComics(LocalSortType.name)
            .any(
              (current) =>
                  'local:${current.id}:${current.createdAt.millisecondsSinceEpoch}' ==
                      target.libraryKey &&
                  p.normalize(p.absolute(current.baseDir)) == root,
            )) {
      throw StateError('漫画库在恢复过程中变化，请重试');
    }
    store.recoverDocument(
      previous: previous,
      replacement: target,
      expectedPages: oldPages,
      resolvedPages: resolved,
    );
    return true;
  } finally {
    store.close();
  }
}
