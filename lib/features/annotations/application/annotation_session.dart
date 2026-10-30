import 'package:uuid/uuid.dart';
import '../domain/annotation.dart';
import '../domain/geometry.dart';
import 'annotation_store.dart';
import '../domain/source_document.dart';

/// A reader's working view. Persistent mutations commit before changing memory.
/// The default memory constructor remains useful for previews and tests.
class AnnotationSession {
  AnnotationSession()
    : documentId = const Uuid().v4(),
      _store = null,
      ownsStore = false,
      sourceIdentityOf = null,
      pageLocatorOf = null,
      assetUriOf = null;
  AnnotationSession.persistent(
    AnnotationStore store, {
    required String libraryKey,
    required String title,
    this.ownsStore = false,
    this.sourceIdentityOf,
    this.pageLocatorOf,
    this.assetUriOf,
    AnnotationDocumentSource? documentSource,
  }) : _store = store,
       documentId = store.openDocument(
         libraryKey: libraryKey,
         title: title,
         source: documentSource,
       ) {
    for (final note in store.list(documentId)) {
      _notes[note.id] = note;
    }
  }
  final AnnotationStore? _store;
  final bool ownsStore;
  final String Function(String)? sourceIdentityOf;
  final Map<String, Object?> Function(String)? pageLocatorOf;
  final String Function(String)? assetUriOf;
  bool _closed = false;
  bool get persistent => _store != null;
  final String documentId;
  final _pageIds = <(String, String), String>{};
  final _anchors = <(String, String), PageAnchor>{};
  final _notes = <String, Annotation>{};
  final _sources = <String, AnnotationSourcePage>{};
  bool inputActive = false;
  String? selectedId;
  Object? persistenceFailure;

  void _checkWrite() {
    if (_closed) throw StateError('Annotation session is closed');
    if (persistenceFailure case final failure?) {
      throw StateError('批注数据库不可用：$failure');
    }
  }

  PageAnchor anchor({
    required String chapterId,
    required int imageNumber,
    required double width,
    required double height,
    String? sourceIdentity,
    String? assetUri,
  }) {
    if (imageNumber < 1 ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0) {
      throw ArgumentError('Invalid source page');
    }
    _checkWrite();
    final identity = sourceIdentity == null
        ? 'image:$imageNumber'
        : sourceIdentityOf?.call(sourceIdentity) ?? sourceIdentity;
    final key = (chapterId, identity);
    final store = _store;
    if (store != null) {
      final cached = _anchors[key];
      if (cached != null &&
          cached.sourceImageNumber == imageNumber &&
          cached.sourceWidth == width &&
          cached.sourceHeight == height) {
        return cached;
      }
      final page = _anchors[key] = store.resolvePage(
        documentId: documentId,
        chapterId: chapterId,
        sourceIdentity: identity,
        imageNumber: imageNumber,
        width: width,
        height: height,
        assetUri: assetUri ?? sourceIdentity,
        locator: pageLocatorOf?.call(identity),
      );
      for (final note
          in _notes.values
              .where((n) => n.anchor.pageId == page.pageId)
              .toList()) {
        _notes[note.id] = note.withAnchor(page);
      }
      return page;
    }
    final page = PageAnchor(
      documentId: documentId,
      pageId: _pageIds.putIfAbsent(key, () => const Uuid().v4()),
      chapterId: chapterId,
      sourceImageNumber: imageNumber,
      sourceWidth: width,
      sourceHeight: height,
    );
    _sources[page.pageId] = AnnotationSourcePage(
      anchor: page,
      sourceIdentity: identity,
      assetUri: assetUri ?? sourceIdentity,
      locator: const {'kind': 'localCache'},
    );
    return page;
  }

  AnnotationSourcePage? sourcePage(PageAnchor page) {
    final stored =
        _store?.sourcePage(documentId, page.pageId) ?? _sources[page.pageId];
    if (stored == null) return null;
    return AnnotationSourcePage(
      anchor: stored.anchor,
      sourceIdentity: stored.sourceIdentity,
      assetUri: assetUriOf?.call(stored.sourceIdentity) ?? stored.assetUri,
      locator: stored.locator,
    );
  }

  AnnotationSourceDocument? get sourceDocument => _store?.document(documentId);
  void setSourceStatus(String status) =>
      _store?.setSourceStatus(documentId, status);

  void relocateSource(AnnotationDocumentSource source) {
    _checkWrite();
    final store = _store;
    if (store == null) throw StateError('临时批注不能重新关联原件');
    store.relocateSource(documentId, source);
  }

  List<Annotation> forPage(PageAnchor page) => List.unmodifiable(
    _notes.values.where((note) => note.anchor.pageId == page.pageId),
  );
  List<Annotation> get all => List.unmodifiable(_notes.values);

  void refresh() {
    if (_closed) throw StateError('Annotation session is closed');
    final store = _store;
    if (store == null) return;
    final notes = store.list(documentId);
    _notes
      ..clear()
      ..addEntries(notes.map((note) => MapEntry(note.id, note)));
    _anchors.clear();
    if (!_notes.containsKey(selectedId)) selectedId = null;
    persistenceFailure = null;
  }

  Annotation add(
    PageAnchor page,
    AnnotationKind kind,
    String text, {
    ContentRect? rect,
  }) {
    if (page.documentId != documentId) throw ArgumentError('Wrong document');
    _checkWrite();
    final now = DateTime.now().toUtc();
    final note = Annotation(
      id: const Uuid().v4(),
      anchor: page,
      kind: kind,
      rect: rect,
      text: text,
      createdAt: now,
      updatedAt: now,
    );
    _store?.put(note);
    _notes[note.id] = note;
    return note;
  }

  void update(String id, String text) {
    _checkWrite();
    final note = _notes[id];
    if (note == null) throw StateError('Annotation no longer exists');
    final updated = note.withText(text, DateTime.now().toUtc());
    _store?.put(updated);
    _notes[id] = updated;
  }

  void remove(String id) {
    _checkWrite();
    _store?.remove(documentId, id);
    _notes.remove(id);
  }

  void setTags(String id, Iterable<String> tags) {
    _checkWrite();
    final note = _notes[id];
    if (note == null) throw StateError('Annotation no longer exists');
    final updated = note.withTags(tags, DateTime.now().toUtc());
    _store?.put(updated);
    _notes[id] = updated;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (ownsStore) _store?.close();
  }
}
