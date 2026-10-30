import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:venera_next/features/annotations/application/annotation_manual_recovery.dart';
import 'package:venera_next/features/annotations/application/annotation_session.dart';
import 'package:venera_next/features/annotations/data/annotation_repository.dart';
import 'package:venera_next/features/annotations/domain/annotation.dart';
import 'package:venera_next/features/annotations/domain/source_document.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/comic_type.dart';

String _key(LocalComic comic) =>
    'local:${comic.id}:${comic.createdAt.millisecondsSinceEpoch}';
Set<String> _liveKeys(LocalManager manager) => manager
    .getComics(LocalSortType.name)
    .where((comic) => comic.comicType == ComicType.local)
    .map(_key)
    .toSet();

Future<List<RecoverableAnnotationDocument>> findManualAnnotationRecovery({
  required AnnotationSession session,
}) async {
  final store = AnnotationRepository.open(
    p.join(App.dataPath, 'annotations.db'),
  );
  try {
    final target = store.document(session.documentId);
    if (store.db.select(
      'SELECT 1 FROM annotations WHERE document_id=? LIMIT 1',
      [target.documentId],
    ).isNotEmpty) {
      throw StateError('当前漫画已有批注或删除记录，不会覆盖或合并');
    }
    final live = _liveKeys(LocalManager());
    return [
      for (final doc in store.documents())
        if (doc.documentId != target.documentId &&
            !live.contains(doc.libraryKey) &&
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

LocalComic _boundComic(LocalManager manager, String libraryKey) => manager
    .getComics(LocalSortType.name)
    .where(
      (comic) =>
          comic.comicType == ComicType.local && _key(comic) == libraryKey,
    )
    .single;

typedef _PageRef = ({String chapterId, int imageNumber, String uri});
Future<List<_PageRef>> _catalogue(
  LocalManager manager,
  LocalComic comic,
) async {
  final result = <_PageRef>[];
  final chapters = comic.chapters;
  for (var chapter = 1; chapter <= (chapters?.length ?? 1); chapter++) {
    final id = chapters?.positionAt(chapter).id ?? '0';
    final images = await manager.getImages(
      comic.id,
      comic.comicType,
      chapters == null ? 1 : id,
    );
    for (var i = 0; i < images.length; i++) {
      result.add((chapterId: id, imageNumber: i + 1, uri: images[i]));
    }
  }
  return result;
}

typedef _VerifiedImage = ({
  int width,
  int height,
  String hash,
  int size,
  String uri,
  Uint8List thumbnail,
});
_VerifiedImage _readImage(String uri, String root, {bool thumbnail = true}) {
  if (!uri.startsWith('file://')) throw StateError('手工恢复只支持本地图片');
  final path = p.normalize(p.absolute(uri.substring(7)));
  final realRoot = Directory(root).resolveSymbolicLinksSync();
  if (!p.isWithin(p.normalize(p.absolute(root)), path)) {
    throw StateError('来源页不在当前漫画目录内');
  }
  final file = File(path);
  final resolved = file.resolveSymbolicLinksSync();
  if (!p.isWithin(realRoot, resolved)) throw StateError('来源页链接到漫画目录之外');
  final before = file.statSync();
  if (before.type != FileSystemEntityType.file ||
      before.size < 1 ||
      before.size > 256 * 1024 * 1024) {
    throw StateError('来源页缺失或超过 256 MiB');
  }
  final handle = file.openSync();
  late final Uint8List bytes;
  try {
    // A file may grow after stat; never allocate an unbounded read.
    bytes = handle.readSync(before.size + 1);
  } finally {
    handle.closeSync();
  }
  final after = file.statSync();
  if (bytes.length != before.size ||
      before.size != after.size ||
      before.modified != after.modified ||
      resolved != file.resolveSymbolicLinksSync()) {
    throw StateError('读取时图片发生变化');
  }
  final decoder = image.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (decoder == null ||
      info == null ||
      info.width < 1 ||
      info.height < 1 ||
      info.width * info.height > 40000000 ||
      info.numFrames != 1) {
    throw StateError('图片无法解码、为动态图或超过四千万像素');
  }
  final decoded = decoder.decodeFrame(0);
  if (decoded == null) throw StateError('来源页无法解码');
  final natural = image.bakeOrientation(decoded);
  return (
    width: natural.width,
    height: natural.height,
    hash: sha256.convert(bytes).toString(),
    size: bytes.length,
    uri: uri,
    thumbnail: thumbnail
        ? Uint8List.fromList(
            image.encodePng(
              image.copyResize(
                natural,
                width: natural.width > natural.height ? 192 : null,
                height: natural.width > natural.height ? null : 192,
              ),
            ),
          )
        : Uint8List(0),
  );
}

// Keep the isolate closure outside the runtime-owner scope: LocalManager,
// SQLite handles and cancellation callbacks must never enter its capture set.
Future<_VerifiedImage> _decodeInIsolate(
  String uri,
  String root, {
  bool thumbnail = true,
}) => Isolate.run(() => _readImage(uri, root, thumbnail: thumbnail));

Future<AnnotationManualRecoveryPreview?> prepareManualAnnotationRecovery({
  required AnnotationSession session,
  required String documentId,
  required bool Function() isCurrent,
}) async {
  if (!isCurrent()) return null;
  final manager = LocalManager();
  final store = AnnotationRepository.open(
    p.join(App.dataPath, 'annotations.db'),
  );
  try {
    final previous = store.document(documentId),
        target = store.document(session.documentId);
    if (previous.documentId == target.documentId ||
        _liveKeys(manager).contains(previous.libraryKey)) {
      throw StateError('旧批注仍绑定本地漫画，不能手工恢复');
    }
    if (store.db.select(
      'SELECT 1 FROM annotations WHERE document_id=? LIMIT 1',
      [target.documentId],
    ).isNotEmpty) {
      throw StateError('当前漫画已有批注或删除记录，不会覆盖或合并');
    }
    final comic = _boundComic(manager, target.libraryKey);
    final root = p.normalize(p.absolute(comic.baseDir));
    bool current() =>
        isCurrent() &&
        identical(LocalManager.current, manager) &&
        !_liveKeys(manager).contains(previous.libraryKey) &&
        manager
            .getComics(LocalSortType.name)
            .any(
              (entry) =>
                  _key(entry) == target.libraryKey &&
                  p.normalize(p.absolute(entry.baseDir)) == root,
            );
    final catalogue = await _catalogue(manager, comic);
    if (!current()) {
      store.close();
      return null;
    }
    final targets = <AnnotationManualTargetPage>[],
        fingerprints = <String, _VerifiedImage>{};
    for (final ref in catalogue) {
      final verified = await _decodeInIsolate(ref.uri, root);
      if (!current()) {
        store.close();
        return null;
      }
      final anchor = session.anchor(
        chapterId: ref.chapterId,
        imageNumber: ref.imageNumber,
        width: verified.width.toDouble(),
        height: verified.height.toDouble(),
        sourceIdentity: ref.uri,
      );
      final page = store.sourcePage(target.documentId, anchor.pageId)!;
      final recordedHash = page.locator['sha256'];
      if (recordedHash != null &&
          (recordedHash != verified.hash ||
              page.locator['size'] != verified.size)) {
        throw StateError('目标页与导入来源凭据不同，请重新导入后核对');
      }
      targets.add(
        AnnotationManualTargetPage(page: page, thumbnail: verified.thumbnail),
      );
      fingerprints[anchor.pageId] = verified;
    }
    if (!current()) {
      store.close();
      return null;
    }
    final plan = store.prepareManualRecovery(
      previousDocumentId: previous.documentId,
      replacementDocumentId: target.documentId,
    );
    if (targets.length < plan.previousPages.length) {
      throw StateError('目标页数量不足，请选择包含全部旧页的导入版本');
    }
    return _ManualPreview(
      store,
      plan,
      manager,
      comic,
      root,
      catalogue,
      List.unmodifiable(targets),
      Map.unmodifiable(fingerprints),
      List.unmodifiable(store.list(previous.documentId)),
    );
  } catch (_) {
    store.close();
    rethrow;
  }
}

class _ManualPreview implements AnnotationManualRecoveryPreview {
  _ManualPreview(
    this.store,
    this.plan,
    this.manager,
    this.comic,
    this.root,
    this.catalogue,
    this.targets,
    this.fingerprints,
    this.annotations,
  );
  final AnnotationRepository store;
  final ManualAnnotationRecoveryPlan plan;
  final LocalManager manager;
  final LocalComic comic;
  final String root;
  final List<_PageRef> catalogue;
  final Map<String, _VerifiedImage> fingerprints;
  @override
  final List<AnnotationManualTargetPage> targets;
  @override
  final List<Annotation> annotations;
  bool _disposed = false, _committing = false, _committed = false;
  Completer<void>? _commitDone;
  @override
  AnnotationSourceDocument get previous => plan.previous;
  @override
  List<AnnotationSourcePage> get previousPages => plan.previousPages;
  bool _current(bool Function() isCurrent) =>
      !_disposed &&
      !_committed &&
      isCurrent() &&
      identical(LocalManager.current, manager) &&
      !_liveKeys(manager).contains(previous.libraryKey) &&
      manager
          .getComics(LocalSortType.name)
          .any(
            (entry) =>
                _key(entry) == plan.replacement.libraryKey &&
                p.normalize(p.absolute(entry.baseDir)) == root,
          );
  @override
  Future<bool> commit({
    required Map<String, String> pageMapping,
    Set<String> reviewedDifferentDimensions = const {},
    required bool Function() isCurrent,
  }) async {
    if (_committing || !_current(isCurrent)) return false;
    final mapping = Map<String, String>.unmodifiable(pageMapping);
    _committing = true;
    final done = _commitDone = Completer<void>();
    try {
      final latest = await _catalogue(
        manager,
        _boundComic(manager, plan.replacement.libraryKey),
      );
      if (!_current(isCurrent)) return false;
      if (latest.length != catalogue.length ||
          List.generate(
            latest.length,
            (index) => latest[index] == catalogue[index],
          ).any((equal) => !equal)) {
        throw StateError('目标图片列表已变化，请重新预览');
      }
      for (final id in mapping.values.toSet()) {
        final expected = fingerprints[id];
        if (expected == null) throw ArgumentError('目标页不在预览内');
        final actual = await _decodeInIsolate(
          expected.uri,
          root,
          thumbnail: false,
        );
        if (!_current(isCurrent)) return false;
        if (actual.hash != expected.hash ||
            actual.size != expected.size ||
            actual.width != expected.width ||
            actual.height != expected.height) {
          throw StateError('预览后目标图片内容变化，请重新预览');
        }
      }
      if (!_current(isCurrent)) return false;
      store.applyManualRecovery(
        plan: plan,
        pageMapping: mapping,
        reviewedDifferentDimensions: reviewedDifferentDimensions,
      );
      _committed = true;
      return true;
    } finally {
      _committing = false;
      try {
        if (_disposed) store.close();
      } finally {
        done.complete();
      }
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    if (_committing) {
      await _commitDone?.future;
    } else {
      store.close();
    }
  }
}
