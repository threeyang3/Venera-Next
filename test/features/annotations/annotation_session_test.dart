import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/annotations/application/annotation_session.dart';
import 'package:venera_next/features/annotations/domain/annotation.dart';
import 'package:venera_next/features/annotations/domain/geometry.dart';

void main() {
  test('source image identity survives a change of display order', () {
    final session = AnnotationSession();
    final a = session.anchor(
      chapterId: 'one',
      imageNumber: 1,
      width: 10,
      height: 20,
      sourceIdentity: 'file://page-a.png',
    );
    final b = session.anchor(
      chapterId: 'one',
      imageNumber: 2,
      width: 10,
      height: 20,
      sourceIdentity: 'file://page-a.png',
    );
    final c = session.anchor(
      chapterId: 'one',
      imageNumber: 1,
      width: 10,
      height: 20,
      sourceIdentity: 'file://page-b.png',
    );
    expect(a.pageId, b.pageId);
    expect(a.pageId, isNot(c.pageId));
  });
  test('page UUID survives rebuild, resize and chapter round trip', () {
    final session = AnnotationSession();
    PageAnchor page(String chapter, int number, [double width = 1000]) =>
        session.anchor(
          chapterId: chapter,
          imageNumber: number,
          width: width,
          height: 2000,
        );
    final a = page('one', 1);
    expect(page('one', 1, 500).pageId, a.pageId);
    expect(page('two', 1).pageId, isNot(a.pageId));
    expect(page('one', 2).pageId, isNot(a.pageId));
    expect(page('one', 1).pageId, a.pageId);
    expect(AnnotationSession().documentId, isNot(session.documentId));
  });
  test('30 notes create, update and remove with stable UUID and anchor', () {
    final session = AnnotationSession();
    final page = session.anchor(
      chapterId: 'one',
      imageNumber: 8,
      width: 1000,
      height: 2000,
    );
    final notes = List.generate(
      30,
      (i) => session.add(
        page,
        AnnotationKind.region,
        '笔记 $i',
        rect: ContentRect(0.1, 0.2, 0.6, 0.8),
      ),
    );
    expect(notes.map((n) => n.id).toSet(), hasLength(30));
    session.update(notes.first.id, '修改');
    final updated = session.forPage(page).first;
    expect(updated.id, notes.first.id);
    expect(updated.createdAt, notes.first.createdAt);
    expect(updated.text, '修改');
    expect(updated.toJson()['coordinateSpaceVersion'], 1);
    expect(updated.toJson()['sourceImageNumber'], 8);
    session.remove(updated.id);
    expect(session.forPage(page), hasLength(29));
  });
  test(
    'page notes and bookmarks have no region; wrong document is rejected',
    () {
      final a = AnnotationSession(), b = AnnotationSession();
      final page = a.anchor(
        chapterId: 'one',
        imageNumber: 1,
        width: 10,
        height: 20,
      );
      expect(a.add(page, AnnotationKind.pageNote, '整页').rect, isNull);
      expect(a.add(page, AnnotationKind.bookmark, '').rect, isNull);
      expect(
        () => b.add(page, AnnotationKind.bookmark, ''),
        throwsArgumentError,
      );
      expect(() => a.add(page, AnnotationKind.region, ''), throwsArgumentError);
      expect(() => a.update('missing', ''), throwsStateError);
    },
  );
  test('invalid source geometry never creates an anchor', () {
    final session = AnnotationSession();
    expect(
      () => session.anchor(
        chapterId: 'one',
        imageNumber: 0,
        width: 10,
        height: 20,
      ),
      throwsArgumentError,
    );
    expect(
      () => session.anchor(
        chapterId: 'one',
        imageNumber: 1,
        width: double.nan,
        height: 20,
      ),
      throwsArgumentError,
    );
  });
}
