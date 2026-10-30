import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'comic_source_provenance.dart';

/// A folder's identity is its ordered relative page paths and original bytes,
/// independent of the folder's absolute path, timestamps or cover thumbnail.
Future<ComicSourceProvenance> captureFolderSource({
  required Directory directory,
  required Iterable<String> pagePaths,
}) async {
  final root = await directory.resolveSymbolicLinks();
  final paths = pagePaths.toList()..sort();
  if (paths.isEmpty || paths.toSet().length != paths.length) {
    throw const FormatException('文件夹没有唯一的可读页面');
  }
  final pages = <String, Map<String, Object?>>{};
  final manifest = <Object?>[];
  var size = 0;
  for (final identity in paths) {
    if (!ComicSourceProvenance.validRelativePath(identity)) {
      throw const FormatException('文件夹页面路径无效');
    }
    final file = File(p.joinAll([directory.path, ...identity.split('/')]));
    final actual = await file.resolveSymbolicLinks();
    if (!p.isWithin(root, actual) ||
        await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file) {
      throw const FileSystemException('文件夹页面不能是链接或位于目录之外');
    }
    final before = await file.stat();
    final fingerprint = await ComicSourceProvenance.fingerprint(file);
    final after = await file.stat();
    if (before.size != after.size ||
        before.modified != after.modified ||
        await file.resolveSymbolicLinks() != actual) {
      throw const FileSystemException('读取过程中图片发生变化');
    }
    size += fingerprint['size'] as int;
    pages[identity] = {
      'kind': 'folderImage',
      'relativePath': identity,
      ...fingerprint,
    };
    manifest.add([identity, fingerprint['size'], fingerprint['sha256']]);
  }
  if (await directory.resolveSymbolicLinks() != root) {
    throw const FileSystemException('读取过程中目录发生变化');
  }
  return ComicSourceProvenance(
    source: {
      'kind': 'folder',
      'uri': Directory(root).uri.toString(),
      'size': size,
      'sha256': sha256
          .convert(utf8.encode(jsonEncode(['comicnotes-folder-v1', manifest])))
          .toString(),
    },
    pages: pages,
  );
}

/// These receipts belong to this installation, never to the referenced source
/// folder. The library key includes the import generation, not only its ID.
File folderSourceReceiptFile(String dataPath, String libraryKey) => File(
  p.join(
    dataPath,
    'comicnotes-sources',
    '${sha256.convert(utf8.encode(libraryKey))}.json',
  ),
);

Future<void> writeFolderSourceReceipt({
  required String dataPath,
  required String libraryKey,
  required ComicSourceProvenance receipt,
}) async {
  final file = folderSourceReceiptFile(dataPath, libraryKey);
  await file.parent.create(recursive: true);
  final previous = ComicSourceProvenance.readFile(file);
  if (previous != null) {
    if (previous.source['sha256'] != receipt.source['sha256'] ||
        previous.source['size'] != receipt.source['size']) {
      throw StateError('同一导入身份已存在不同来源映射，未覆盖');
    }
    return;
  }
  final staging = await file.parent.createTemp('.folder-source-');
  try {
    await receipt.write(staging);
    await File(
      p.join(staging.path, ComicSourceProvenance.filename),
    ).rename(file.path);
  } finally {
    await staging.delete(recursive: true);
  }
}
