import 'package:path/path.dart' as p;
import 'package:venera_next/foundation/file_system.dart';
import 'package:venera_next/foundation/comic_source_provenance.dart';
import 'package:venera_next/foundation/folder_source_provenance.dart';
import 'file_system_layout.dart';

/// Uses the same page/cover/chapter rules as the local reader and importer.
Future<ComicSourceProvenance> captureComicFolderSource(
  Directory directory,
) async {
  final layout = await ComicFileSystemLayout.inspectAsync(directory);
  final pages = layout.useChapterDirectories
      ? layout.chapters.expand((chapter) => chapter.pages)
      : layout.rootPages;
  return captureFolderSource(
    directory: directory,
    pagePaths: pages.map(
      (file) => p.split(layout.relativePath(file)).join('/'),
    ),
  );
}
