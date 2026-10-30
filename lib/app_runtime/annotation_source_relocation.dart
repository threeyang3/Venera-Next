import 'package:venera_next/features/comic_storage/comic_storage.dart'
    show captureComicFolderSource;
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:venera_next/features/annotations/application/annotation_session.dart';
import 'package:venera_next/features/annotations/domain/source_document.dart';
import 'package:venera_next/foundation/comic_source_provenance.dart';

/// Relocation is deliberately exact: a different edition requires a separate
/// page-mapping review. Titles and page counts cannot establish source identity.
Future<bool> relocateAnnotationOriginal(
  AnnotationSession session,
  File file, {
  required bool Function() isCurrent,
}) async {
  if (!isCurrent()) return false;
  final original = session.sourceDocument?.source;
  if (original == null) throw StateError('旧导入没有原件指纹，暂不能自动关联');
  final fingerprint = await ComicSourceProvenance.fingerprint(file);
  if (!isCurrent()) return false;
  if (fingerprint['sha256'] != original.sha256 ||
      fingerprint['size'] != original.size) {
    throw StateError('所选文件与导入原件内容不同，未修改关联；请选择同一版本的原文件');
  }
  session.relocateSource(
    AnnotationDocumentSource(
      kind: original.kind,
      uri: file.absolute.uri.toString(),
      sha256: original.sha256,
      size: original.size,
    ),
  );
  return true;
}

Future<bool> relocateAnnotationFolder(
  AnnotationSession session,
  Directory directory, {
  required bool Function() isCurrent,
}) async {
  if (!isCurrent()) return false;
  final original = session.sourceDocument?.source;
  if (original == null || original.kind != 'folder') {
    throw StateError('当前记录没有文件夹来源指纹');
  }
  final receipt = await captureComicFolderSource(directory);
  if (!isCurrent()) return false;
  if (receipt.source['sha256'] != original.sha256 ||
      receipt.source['size'] != original.size) {
    throw StateError('所选目录的页面内容或相对路径不同，未修改关联');
  }
  session.relocateSource(
    AnnotationDocumentSource(
      kind: original.kind,
      uri: receipt.source['uri'] as String,
      sha256: original.sha256,
      size: original.size,
    ),
  );
  return true;
}

Future<bool> selectAnnotationOriginal({
  required AnnotationSession session,
  required bool Function() isCurrent,
}) async {
  if (!isCurrent()) return false;
  final source = session.sourceDocument?.source;
  if (source == null) throw StateError('旧导入没有原件指纹，暂不能自动关联');
  if (source.kind == 'folder') {
    final directory = await getDirectoryPath(confirmButtonText: '关联原始图片目录');
    if (directory == null || !isCurrent()) return false;
    return relocateAnnotationFolder(
      session,
      Directory(directory),
      isCurrent: isCurrent,
    );
  }
  final extensions = switch (source.kind) {
    'pdf' => ['pdf'],
    'epub' => ['epub'],
    'archive' => ['cbz', 'zip', '7z', 'cb7'],
    _ => throw StateError('此来源暂不支持原件重新关联'),
  };
  final selected = await openFile(
    acceptedTypeGroups: [XTypeGroup(label: '原始漫画文件', extensions: extensions)],
  );
  if (selected == null || !isCurrent()) return false;
  return relocateAnnotationOriginal(
    session,
    File(selected.path),
    isCurrent: isCurrent,
  );
}
