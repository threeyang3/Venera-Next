import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/features/annotations/data/annotation_repository.dart';
import 'package:venera_next/features/annotations/application/annotation_session.dart';
import 'package:venera_next/features/annotations/domain/annotation.dart';
import 'package:venera_next/features/annotations/domain/geometry.dart';

void main() {
  late AnnotationRepository store;
  late AnnotationSession old, target;
  late List<PageAnchor> oldPages, targetPages;
  late ManualAnnotationRecoveryPlan plan;
  late List<Annotation> notes;
  setUp(() {
    store = AnnotationRepository(sqlite3.openInMemory(), ownsConnection: true);
    old = AnnotationSession.persistent(
      store,
      libraryKey: 'orphan:old',
      title: 'Old',
    );
    target = AnnotationSession.persistent(
      store,
      libraryKey: 'local:new:123',
      title: 'New',
    );
    oldPages = [
      for (var i = 1; i <= 2; i++)
        old.anchor(
          chapterId: 'old',
          imageNumber: i,
          width: 100,
          height: 200,
          sourceIdentity: 'old/$i.png',
          assetUri: 'file:///old/$i.png',
        ),
    ];
    targetPages = [
      for (var i = 1; i <= 2; i++)
        target.anchor(
          chapterId: 'new',
          imageNumber: i,
          width: 100,
          height: 200,
          sourceIdentity: 'new/$i.png',
          assetUri: 'file:///new/$i.png',
        ),
    ];
    notes = [
      for (final page in oldPages)
        old.add(
          page,
          AnnotationKind.region,
          'Keep ${page.sourceImageNumber}',
          rect: ContentRect(.1, .2, .7, .8),
        ),
    ];
    old.setTags(notes.first.id, ['tag']);
    old.remove(notes.last.id);
    store.db.execute(
      "INSERT INTO export_manifests VALUES('old-export',?,'old-destination',1,'{}')",
      [old.documentId],
    );
    plan = store.prepareManualRecovery(
      previousDocumentId: old.documentId,
      replacementDocumentId: target.documentId,
    );
  });
  tearDown(() {
    old.close();
    target.close();
    store.close();
  });
  Map<String, String> getMapping() => {
    oldPages[0].pageId: targetPages[1].pageId,
    oldPages[1].pageId: targetPages[0].pageId,
  };
  String snapshot() => jsonEncode([
    for (final table in [
      'source_documents',
      'source_pages',
      'annotations',
      'annotation_tags',
      'export_manifests',
    ])
      store.db
          .select('SELECT * FROM $table')
          .map((row) => Map<String, Object?>.from(row))
          .toList(),
  ]);
  test(
    'explicit same-size remap preserves UUIDs, geometry, tombstones, tags and exports',
    () {
      store.applyManualRecovery(plan: plan, pageMapping: getMapping());
      final document = store.document(old.documentId);
      expect(document.libraryKey, 'local:new:123');
      expect(document.source, isNull);
      expect(document.status, 'unlinked');
      expect(store.documents(), hasLength(1));
      final live = store.list(old.documentId).single;
      expect(live.id, notes.first.id);
      expect(live.anchor.pageId, oldPages.first.pageId);
      expect(live.anchor.chapterId, 'new');
      expect(live.anchor.sourceImageNumber, 2);
      expect(live.rect!.toJson(), notes.first.rect!.toJson());
      expect(live.tags, ['tag']);
      final mapped = store.sourcePage(old.documentId, live.anchor.pageId)!;
      expect(mapped.sourceIdentity, 'new/2.png');
      expect(mapped.assetUri, 'file:///new/2.png');
      expect(
        (mapped.locator['manualMapping'] as Map)['previousSourceIdentity'],
        'old/1.png',
      );
      expect(
        store.db.select(
          'SELECT deleted_at FROM annotations WHERE annotation_id=?',
          [notes.last.id],
        ).single['deleted_at'],
        isNotNull,
      );
      expect(
        store.db.select('SELECT * FROM export_manifests').single['export_id'],
        'old-export',
      );
      expect(store.db.select('PRAGMA foreign_key_check'), isEmpty);
      expect(
        () => store.applyManualRecovery(plan: plan, pageMapping: getMapping()),
        throwsStateError,
      );
    },
  );
  for (final invalid in [
    'missing',
    'duplicate',
    'unknown',
    'dimensions',
    'targetNotes',
    'targetTombstone',
    'oldEdit',
    'oldTag',
    'oldExport',
    'targetSource',
    'failure',
  ]) {
    test('manual remap rolls back or rejects $invalid', () {
      final mapping = getMapping();
      switch (invalid) {
        case 'missing':
          mapping.remove(oldPages.last.pageId);
        case 'duplicate':
          mapping[oldPages.last.pageId] = targetPages.last.pageId;
        case 'unknown':
          mapping[oldPages.first.pageId] = 'missing';
        case 'dimensions':
          store.db.execute(
            'UPDATE source_pages SET source_width=101 WHERE page_id=?',
            [targetPages.first.pageId],
          );
          plan = store.prepareManualRecovery(
            previousDocumentId: old.documentId,
            replacementDocumentId: target.documentId,
          );
        case 'targetNotes':
          target.add(targetPages.first, AnnotationKind.pageNote, 'New');
        case 'targetTombstone':
          final n = target.add(
            targetPages.first,
            AnnotationKind.pageNote,
            'New',
          );
          target.remove(n.id);
        case 'oldEdit':
          old.update(notes.first.id, 'Newer edit');
        case 'oldTag':
          old.setTags(notes.first.id, ['new']);
        case 'oldExport':
          store.db.execute("UPDATE export_manifests SET last_exported_at=2");
        case 'targetSource':
          store.db.execute(
            "UPDATE source_documents SET title='Changed' WHERE document_id=?",
            [target.documentId],
          );
        case 'failure':
          store.db.execute(
            "CREATE TRIGGER fail_manual BEFORE DELETE ON source_documents BEGIN SELECT RAISE(ABORT, 'failed'); END",
          );
      }
      final before = snapshot();
      expect(
        () => store.applyManualRecovery(plan: plan, pageMapping: mapping),
        throwsA(anything),
      );
      expect(snapshot(), before);
    });
  }

  test('different natural sizes require review and update page coordinates', () {
    store.db.execute(
      'UPDATE source_pages SET source_width=200,source_height=400 WHERE page_id=?',
      [targetPages.first.pageId],
    );
    plan = store.prepareManualRecovery(
      previousDocumentId: old.documentId,
      replacementDocumentId: target.documentId,
    );
    final mapping = {
      oldPages.first.pageId: targetPages.first.pageId,
      oldPages.last.pageId: targetPages.last.pageId,
    };
    expect(
      () => store.applyManualRecovery(plan: plan, pageMapping: mapping),
      throwsStateError,
    );
    store.applyManualRecovery(
      plan: plan,
      pageMapping: mapping,
      reviewedDifferentDimensions: {oldPages.first.pageId},
    );
    final mapped = store.sourcePage(old.documentId, oldPages.first.pageId)!;
    expect(mapped.anchor.sourceWidth, 200);
    expect(mapped.anchor.sourceHeight, 400);
    final review = mapped.locator['manualMapping'] as Map;
    expect(review['coordinateReview'], 'explicit-normalized-coordinate-review');
    expect(review['previousSourceWidth'], 100);
    expect(review['targetSourceWidth'], 200);
    expect(store.list(old.documentId).single.anchor.sourceWidth, 200);
  });

  test(
    'target evidence replaces current source while prior source stays in audit',
    () {
      store.db.execute(
        "UPDATE source_documents SET kind='cbz',source_uri='file:///prior.cbz',source_hash=?,source_size=20 WHERE document_id=?",
        ['a' * 64, old.documentId],
      );
      store.db.execute(
        "UPDATE source_documents SET kind='cbz',source_uri='file:///new.cbz',source_hash=?,source_size=30 WHERE document_id=?",
        ['b' * 64, target.documentId],
      );
      plan = store.prepareManualRecovery(
        previousDocumentId: old.documentId,
        replacementDocumentId: target.documentId,
      );
      store.applyManualRecovery(plan: plan, pageMapping: getMapping());
      expect(store.document(old.documentId).source!.sha256, 'b' * 64);
      final audit =
          store.pages(old.documentId).first.locator['manualMapping'] as Map;
      expect((audit['previousDocumentSource'] as Map)['sha256'], 'a' * 64);
    },
  );

  test('explicit page swaps do not violate old identity keys', () {
    for (var i = 0; i < targetPages.length; i++) {
      store.db.execute(
        'UPDATE source_pages SET chapter_id=?,source_identity=? WHERE page_id=?',
        ['old', 'old/${i + 1}.png', targetPages[i].pageId],
      );
    }
    plan = store.prepareManualRecovery(
      previousDocumentId: old.documentId,
      replacementDocumentId: target.documentId,
    );
    store.applyManualRecovery(plan: plan, pageMapping: getMapping());
    expect(
      store.sourcePage(old.documentId, oldPages.first.pageId)!.sourceIdentity,
      'old/2.png',
    );
    expect(
      store.sourcePage(old.documentId, oldPages.last.pageId)!.sourceIdentity,
      'old/1.png',
    );
    expect(store.db.select('PRAGMA foreign_key_check'), isEmpty);
  });

  test('preview rejects a target with deletion history', () {
    final note = target.add(
      targetPages.first,
      AnnotationKind.bookmark,
      'Deleted',
    );
    target.remove(note.id);
    expect(
      () => store.prepareManualRecovery(
        previousDocumentId: old.documentId,
        replacementDocumentId: target.documentId,
      ),
      throwsStateError,
    );
  });
  test('mutable preview metadata cannot inject an unchecked target asset', () {
    expect(
      () => plan.replacementPages.first.locator['injected'] = true,
      throwsUnsupportedError,
    );
    store.applyManualRecovery(plan: plan, pageMapping: getMapping());
    expect(
      store
          .pages(old.documentId)
          .every((page) => !page.locator.containsKey('injected')),
      isTrue,
    );
  });
}
