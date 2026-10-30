import 'package:venera_next/features/history/history.dart';
import 'package:venera_next/features/history/history_scope.dart';
import 'package:venera_next/features/local_comics/local_comics.dart';
import 'package:venera_next/features/reader/reader.dart';
import 'package:venera_next/routing/app_navigation.dart';
import 'package:venera_next/foundation/context.dart';

void openLocalComic(
  LocalComic comic, {
  int? chapter,
  int? imageNumber,
  String? annotationId,
}) {
  final history = HistoryScope.read(
    appNavigation.rootContext,
  ).find(comic.id, comic.comicType);
  final start = resolveLocalReadingStart(
    chapters: comic.chapters,
    downloadedChapters: comic.downloadedChapters,
    historyChapter: history?.ep,
    historyPage: history?.page,
    historyGroup: history?.group,
  );
  appNavigation.rootContext.to(
    () => Reader(
      onClosed: ReaderSessionScope.onClosedOf(appNavigation.rootContext),
      type: comic.comicType,
      cid: comic.id,
      name: comic.title,
      chapters: comic.chapters,
      initialChapter: chapter ?? start.chapter,
      initialPage: imageNumber ?? start.page,
      initialChapterGroup: chapter == null ? start.group : null,
      initialAnnotationId: annotationId,
      history: history ?? History.fromModel(model: comic, ep: 0, page: 0),
      author: comic.subtitle,
      tags: comic.tags,
    ),
  );
}
