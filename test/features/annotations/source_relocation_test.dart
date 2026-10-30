import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/app_runtime/annotation_source_relocation.dart';
import 'package:venera_next/features/annotations/application/annotation_session.dart';
import 'package:venera_next/features/annotations/data/annotation_repository.dart';
import 'package:venera_next/features/annotations/domain/annotation.dart';
import 'package:venera_next/features/annotations/domain/source_document.dart';
import 'package:venera_next/foundation/comic_source_provenance.dart';

void main() {
  late Directory root;
  late AnnotationRepository store;
  setUp(() {
    root = Directory.systemTemp.createTempSync('source-relocation-');
    store = AnnotationRepository.open('${root.path}/notes.db');
  });
  tearDown(() {
    store.close();
    root.deleteSync(recursive: true);
  });

  test(
    'relocation preserves UUIDs, pages and tags after reopen; mismatch never changes binding',
    () async {
      final file = File('${root.path}/new location %.pdf')
        ..writeAsBytesSync([1, 2, 3, 4]);
      final fingerprint = await ComicSourceProvenance.fingerprint(file);
      final original = AnnotationDocumentSource(
        kind: 'pdf',
        uri: 'file:///missing.pdf',
        sha256: fingerprint['sha256'] as String,
        size: 4,
      );
      final session = AnnotationSession.persistent(
        store,
        libraryKey: 'local:1:1',
        title: 'Book',
        documentSource: original,
      );
      final page = session.anchor(
        chapterId: '0',
        imageNumber: 1,
        width: 100,
        height: 200,
      );
      final note = session.add(page, AnnotationKind.pageNote, 'Keep');
      session.setTags(note.id, ['构图']);
      session.setSourceStatus('missing');
      final wrong = File('${root.path}/same-size.pdf')
        ..writeAsBytesSync([4, 3, 2, 1]);
      await expectLater(
        relocateAnnotationOriginal(session, wrong, isCurrent: () => true),
        throwsStateError,
      );
      expect(session.sourceDocument!.source!.uri, original.uri);
      expect(session.sourceDocument!.status, 'missing');
      expect(
        await relocateAnnotationOriginal(session, file, isCurrent: () => true),
        isTrue,
      );
      expect(session.sourceDocument!.source!.uri, file.uri.toString());
      expect(session.sourceDocument!.status, 'available');
      store.close();
      store = AnnotationRepository.open('${root.path}/notes.db');
      final reopened = AnnotationSession.persistent(
        store,
        libraryKey: 'local:1:1',
        title: 'Book',
        documentSource: original,
      );
      expect(reopened.documentId, session.documentId);
      expect(reopened.all.single.id, note.id);
      expect(reopened.all.single.anchor.pageId, page.pageId);
      expect(reopened.all.single.tags, ['构图']);
      expect(reopened.sourceDocument!.source!.uri, file.uri.toString());
      expect(
        () => reopened.relocateSource(
          AnnotationDocumentSource(
            kind: 'pdf',
            uri: file.uri.toString(),
            sha256: 'different',
            size: 4,
          ),
        ),
        throwsStateError,
      );
    },
  );

  test('retired resolution cannot commit to a closed session', () async {
    final file = File('${root.path}/original.pdf')..writeAsBytesSync([1, 2, 3]);
    final fingerprint = await ComicSourceProvenance.fingerprint(file);
    final session = AnnotationSession.persistent(
      store,
      libraryKey: 'local:1:1',
      title: 'Book',
      documentSource: AnnotationDocumentSource(
        kind: 'pdf',
        uri: 'file:///missing.pdf',
        sha256: fingerprint['sha256'] as String,
        size: 3,
      ),
    );
    var active = true;
    final pending = relocateAnnotationOriginal(
      session,
      file,
      isCurrent: () => active,
    );
    active = false;
    session.close();
    expect(await pending, isFalse);
    expect(
      store.document(session.documentId).source!.uri,
      'file:///missing.pdf',
    );
  });
}
