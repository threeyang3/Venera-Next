import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:xml/xml.dart';
import 'package:venera_next/foundation/annotation_link_contract.dart';
import 'package:venera_next/features/annotations/application/annotation_link_resolver.dart';
import 'package:venera_next/features/annotations/application/annotation_session.dart';
import 'package:venera_next/features/annotations/data/annotation_repository.dart';
import 'package:venera_next/features/annotations/domain/annotation.dart';

void main() {
  test('canonical links round-trip stable identities with URL encoding', () {
    final link = AnnotationLink(
      documentId: '书籍 & version #1',
      annotationId: 'anno-1',
    );
    final encoded = link.toUri();
    expect(encoded.toString(), startsWith('comicnotes://open?'));
    final restored = AnnotationLink.parse(Uri.parse(encoded.toString()))!;
    expect(restored.documentId, link.documentId);
    expect(restored.annotationId, link.annotationId);
  });
  for (final uri in [
    'https://open?document=book&annotation=one',
    'comicnotes://else?document=book&annotation=one',
    'comicnotes:///open?document=book&annotation=one',
    'comicnotes://user@open?document=book&annotation=one',
    'comicnotes://open:123?document=book&annotation=one',
    'comicnotes://open/extra?document=book&annotation=one',
    'comicnotes://open?document=book&annotation=one#fragment',
    'comicnotes://open?document=book',
    'comicnotes://open?document=book&annotation=one&annotation=two',
    'comicnotes://open?document=book&document=other&annotation=one',
    'comicnotes://open?document=book&annotation=one&extra=true',
    'comicnotes://open?document=&annotation=one',
    'comicnotes://open?document=book&annotation=%00x',
  ]) {
    test(
      'invalid or ambiguous link is rejected: $uri',
      () => expect(AnnotationLink.parse(Uri.parse(uri)), isNull),
    );
  }
  test('empty, control and oversized link identities cannot be emitted', () {
    for (final id in ['', ' ', '\n', List.filled(513, 'x').join()]) {
      expect(
        () => AnnotationLink(documentId: id, annotationId: 'one'),
        throwsArgumentError,
      );
    }
  });
  test(
    'resolver requires both the original document and a live annotation',
    () {
      final store = AnnotationRepository(
        sqlite3.openInMemory(),
        ownsConnection: true,
      );
      try {
        final a = AnnotationSession.persistent(
          store,
          libraryKey: 'local:book:123',
          title: 'Book',
        );
        final b = AnnotationSession.persistent(
          store,
          libraryKey: 'local:other:123',
          title: 'Book',
        );
        final page = a.anchor(
          chapterId: 'one',
          imageNumber: 7,
          width: 100,
          height: 200,
          sourceIdentity: 'one/001.png',
        );
        final note = a.add(page, AnnotationKind.pageNote, '原笔记');
        final resolver = AnnotationLinkResolver(store);
        final resolved = resolver.resolve(
          AnnotationLink(documentId: a.documentId, annotationId: note.id),
        );
        expect(resolved.note.id, note.id);
        expect(resolved.page.sourceIdentity, 'one/001.png');
        expect(
          () => resolver.resolve(
            AnnotationLink(documentId: b.documentId, annotationId: note.id),
          ),
          throwsStateError,
        );
        a.remove(note.id);
        expect(
          () => resolver.resolve(
            AnnotationLink(documentId: a.documentId, annotationId: note.id),
          ),
          throwsStateError,
        );
        expect(
          store.db
              .select('SELECT deleted_at FROM annotations')
              .single['deleted_at'],
          isNotNull,
        );
      } finally {
        store.close();
      }
    },
  );
  test(
    'macOS declares the comicnotes URL scheme without changing app identity',
    () {
      final plist = XmlDocument.parse(
        File('macos/Runner/Info.plist').readAsStringSync(),
      );
      final scheme = plist
          .findAllElements('key')
          .where((key) => key.innerText == 'CFBundleURLSchemes')
          .single;
      final siblings = scheme.parent!.children;
      final values = siblings
          .skip(siblings.indexOf(scheme) + 1)
          .whereType<XmlElement>()
          .first;
      expect(
        values.findAllElements('string').map((e) => e.innerText),
        contains('comicnotes'),
      );
      expect(plist.toXmlString(), contains(r'$(PRODUCT_BUNDLE_IDENTIFIER)'));
    },
  );
}
