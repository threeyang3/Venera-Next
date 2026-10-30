import 'dart:io';
import 'package:venera_next/foundation/folder_source_provenance.dart';
import 'package:path/path.dart' as p;
import 'package:venera_next/features/annotations/application/annotation_session.dart';
import 'package:venera_next/features/annotations/data/annotation_repository.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/comic_source_provenance.dart';
import 'package:venera_next/features/annotations/domain/source_document.dart';

AnnotationSession openLocalAnnotationSession({
  required String libraryKey,
  required String title,
  required String sourceRoot,
}) {
  final store = AnnotationRepository.open(
    p.join(App.dataPath, 'annotations.db'),
  );
  try {
    final provenance =
        ComicSourceProvenance.readFile(
          folderSourceReceiptFile(App.dataPath, libraryKey),
        ) ??
        ComicSourceProvenance.read(Directory(sourceRoot));
    final source = provenance?.source;
    return AnnotationSession.persistent(
      store,
      libraryKey: libraryKey,
      title: title,
      ownsStore: true,
      documentSource: source == null
          ? null
          : AnnotationDocumentSource(
              kind: source['kind'] as String,
              uri: source['uri'] as String,
              sha256: source['sha256'] as String,
              size: source['size'] as int,
            ),
      pageLocatorOf: (identity) =>
          provenance?.pages[identity] ??
          {'kind': 'localCache', 'identity': identity},
      assetUriOf: (identity) {
        if (p.posix.isAbsolute(identity) ||
            identity
                .split('/')
                .any((part) => part.isEmpty || part == '.' || part == '..') ||
            identity.contains('\\')) {
          throw ArgumentError('Invalid imported page identity');
        }
        final root = p.normalize(p.absolute(sourceRoot));
        final file = p.normalize(p.joinAll([root, ...identity.split('/')]));
        if (!p.isWithin(root, file)) {
          throw ArgumentError('Page is outside the selected comic');
        }
        if (File(file).existsSync()) {
          final resolved = File(file).resolveSymbolicLinksSync();
          if (!p.isWithin(
            Directory(root).resolveSymbolicLinksSync(),
            resolved,
          )) {
            throw FileSystemException(
              'Image links outside the comic cannot be exported',
              file,
            );
          }
          return 'file://$resolved';
        }
        return 'file://$file';
      },
      sourceIdentityOf: (image) {
        if (!image.startsWith('file://')) {
          throw ArgumentError('Only local images can be annotated');
        }
        // Reader file:// keys contain raw native paths, not URI-escaped paths.
        final path = p.normalize(image.substring(7));
        final root = p.normalize(sourceRoot);
        if (!p.isWithin(root, path)) {
          throw ArgumentError('Image is outside the selected comic');
        }
        return p.split(p.relative(path, from: root)).join('/');
      },
    );
  } catch (_) {
    store.close();
    rethrow;
  }
}
