import 'dart:convert';
import 'dart:isolate';
import 'package:path/path.dart' as path;
import 'package:archive/archive_io.dart' as archive_io;
import 'package:enough_convert/enough_convert.dart';
import 'package:flutter_7zip/flutter_7zip.dart';
import 'package:venera_next/features/comic_storage/comic_storage.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/file_type.dart';
import 'package:venera_next/foundation/file_system.dart';
import 'package:zip_flutter/zip_flutter.dart';
import '../local_storage_guard.dart';
import 'comic_import_output.dart';
import 'package:venera_next/foundation/comic_source_provenance.dart';

/// Comic Book Archive. Currently supports CBZ, ZIP and 7Z formats.
abstract class CBZ {
  static Future<FileType> checkType(File file) async {
    var header = <int>[];
    await for (var bytes in file.openRead()) {
      header.addAll(bytes);
      if (header.length >= 32) break;
    }
    return detectFileType(header);
  }

  static Future<void> extractArchive(
    File file,
    Directory out, {
    Future<void> Function(String archivePath, String outputPath, int threads)?
    zipExtractor,
    Future<void> Function(String archivePath, String outputPath, int threads)?
    sevenZipExtractor,
    Future<void> Function(String archivePath, String outputPath)?
    dartZipExtractor,
  }) async {
    final zipExtract = zipExtractor ?? ZipFile.openAndExtractAsync;
    final sevenZipExtract = sevenZipExtractor ?? SZArchive.extractIsolates;
    final dartZipExtract = dartZipExtractor ?? _extractZipWithDart;
    var fileType = await checkType(file);
    if (fileType.mime == 'application/zip') {
      try {
        await zipExtract(file.path, out.path, 4);
      } catch (e) {
        Log.warning(
          "CBZ",
          "Failed to extract ZIP archive with zip_flutter, retry with 7z: $e",
        );
        await out.deleteContents();
        try {
          await sevenZipExtract(file.path, out.path, 4);
        } catch (sevenZipError) {
          Log.warning(
            "CBZ",
            "Failed to extract ZIP archive with 7z, retry with Dart archive: $sevenZipError",
          );
          await out.deleteContents();
          await dartZipExtract(file.path, out.path);
        }
      }
    } else if (fileType.mime == "application/x-7z-compressed") {
      await sevenZipExtract(file.path, out.path, 4);
    } else {
      throw Exception('Unsupported archive type');
    }
  }

  static Future<void> _extractZipWithDart(
    String archivePath,
    String outputPath,
  ) async {
    final input = archive_io.InputFileStream(archivePath);
    try {
      final archive = archive_io.ZipDecoder().decodeStream(input);
      for (final entry in archive) {
        final entryName = _normalizeZipEntryName(entry.name);
        if (entryName == null) continue;
        final destination = FilePath.join(outputPath, entryName);
        if (!_isWithinDirectory(outputPath, destination)) {
          continue;
        }
        if (entry.isDirectory) {
          Directory(destination).createSync(recursive: true);
        } else {
          File(destination).parent.createSync(recursive: true);
          final output = archive_io.OutputFileStream(destination);
          try {
            entry.writeContent(output);
          } finally {
            output.closeSync();
          }
        }
      }
    } finally {
      await input.close();
    }
  }

  // Primitive paths cross the worker boundary, never an import operation or
  // reader handle. Read the central directory once, preserving duplicate entries
  // that Archive's filename map would otherwise collapse. Verify original bytes
  // for every selected resource, including paths affected by filesystem aliases.
  static Future<Map<String, Map<String, Object?>>> _zipSourceLocators(
    String archivePath,
    String workspacePath,
    List<String> selectedEntries,
  ) => Isolate.run(() async {
    final input = archive_io.InputFileStream(archivePath);
    Directory? staging;
    try {
      final directory = archive_io.ZipDirectory()..read(input);
      final byPath = <String, List<int>>{};
      for (var index = 0; index < directory.fileHeaders.length; index++) {
        final name = directory.fileHeaders[index].file!.filename;
        if (name.endsWith('/') || name.endsWith('\\')) continue;
        final normalized = _normalizeZipEntryName(name)?.replaceAll('\\', '/');
        if (normalized != null) {
          byPath.putIfAbsent(normalized, () => []).add(index);
        }
      }
      staging = await Directory.systemTemp.createTemp('comicnotes-zip-entry-');
      final result = <String, Map<String, Object?>>{};
      for (final entry in selectedEntries) {
        if (!ComicSourceProvenance.validRelativePath(entry)) {
          throw const FormatException('无效 ZIP 页面路径');
        }
        final candidates = byPath[entry] ?? const <int>[];
        if (candidates.isEmpty) throw const FormatException('无法定位原始 ZIP 图片条目');
        final fingerprint = await ComicSourceProvenance.fingerprint(
          File(FilePath.join(workspacePath, entry)),
        );
        final size = fingerprint['size'] as int;
        if (size > 256 * 1024 * 1024) {
          throw const FormatException('ZIP 图片超过 256 MiB，无法安全确认来源');
        }
        final matches = <int>[];
        for (final index in candidates) {
          final header = directory.fileHeaders[index];
          if (_normalizeZipEntryName(header.filename)?.replaceAll('\\', '/') !=
              entry) {
            throw const FormatException('ZIP 本地与中央目录的条目路径不一致');
          }
          if (header.uncompressedSize != size) continue;
          final check = File(FilePath.join(staging.path, 'entry'));
          final output = _BoundedZipEntryOutput(check.path, size);
          try {
            header.file!.decompress(output);
          } finally {
            output.closeSync();
          }
          if (await check.length() == size &&
              (await ComicSourceProvenance.fingerprint(check))['sha256'] ==
                  fingerprint['sha256']) {
            matches.add(index);
          }
          await check.delete();
        }
        if (matches.isEmpty) {
          throw const FormatException('解压图片与原始 ZIP 条目字节不匹配，未登记不可靠来源');
        }
        // Equal-byte duplicates are interchangeable resources. Select the first
        // verified one deterministically and retain every equivalent index.
        final selected = matches.first;
        result[entry] = {
          'archiveEntryIndex': selected,
          'archiveEntryOccurrence': candidates.indexOf(selected),
          'archiveEntryCount': candidates.length,
          'archiveEntryName': directory.fileHeaders[selected].filename,
          'archiveEntryResolution': candidates.length == 1
              ? 'uniquePath'
              : 'contentMatched',
          if (candidates.length > 1) 'matchingEntryIndices': matches,
        };
      }
      return result;
    } finally {
      await input.close();
      await staging?.delete(recursive: true);
    }
  });

  static String? _normalizeZipEntryName(String name) {
    final decodedName = _decodeLegacyZipName(name);
    final normalized = decodedName.replaceAll('\\', '/');
    final segments = normalized
        .split('/')
        .where((segment) => segment.isNotEmpty && segment != '.')
        .toList();
    if (segments.any((segment) => segment == '..')) {
      return null;
    }
    if (segments.isEmpty) {
      return null;
    }
    return segments.join(Platform.pathSeparator);
  }

  static String _decodeLegacyZipName(String name) {
    final bytes = name.codeUnits;
    if (bytes.any((byte) => byte > 0xff)) {
      return name;
    }
    try {
      final decoded = const GbkCodec().decode(bytes);
      if (_containsCjk(decoded) &&
          (!_containsCjk(name) || _looksLikeMojibake(name))) {
        return decoded;
      }
      return name;
    } catch (_) {
      return name;
    }
  }

  static bool _containsCjk(String name) {
    return name.runes.any(
      (rune) =>
          rune >= 0x3400 && rune <= 0x9fff || rune >= 0xf900 && rune <= 0xfaff,
    );
  }

  static bool _looksLikeMojibake(String name) {
    return name.contains('�') ||
        name.contains('├') ||
        name.contains('┬') ||
        name.contains('╬') ||
        name.contains('▒') ||
        name.contains('╫') ||
        name.contains('╓') ||
        name.contains('╘') ||
        name.contains('─') ||
        name.contains('│') ||
        name.contains('µ') ||
        name.contains('Ú') ||
        name.contains('¾') ||
        name.contains('Ï') ||
        name.contains('Ã') ||
        name.contains('Â');
  }

  static bool _isWithinDirectory(String directory, String filePath) {
    final normalizedDirectory = Directory(directory).absolute.path;
    final normalizedFile = File(filePath).absolute.path;
    return normalizedFile == normalizedDirectory ||
        normalizedFile.startsWith(
          '$normalizedDirectory${Platform.pathSeparator}',
        );
  }

  /// The registrar must report a confirmed non-commit to discard owned output
  /// after failure; unclassified errors retain it because a write may have won.
  static Future<LocalComic> import(
    File file, {
    Future<void> Function(LocalComic comic)? registerComic,
  }) => LocalComicStorageGuard.instance.runImport(
    () => _import(file, registerComic: registerComic),
  );

  static Future<LocalComic> _import(
    File file, {
    Future<void> Function(LocalComic comic)? registerComic,
  }) async {
    final workspace = Directory(App.cachePath).createTempSync('cbz_import_');
    try {
      final source = const bool.fromEnvironment('COMICNOTES_POC')
          ? <String, Object?>{
              'kind': 'archive',
              'uri': file.absolute.uri.toString(),
              ...await ComicSourceProvenance.fingerprint(file),
            }
          : null;
      await extractArchive(file, workspace);
      return await _importExtracted(file, workspace, registerComic, source);
    } finally {
      await workspace.deleteIgnoreError(recursive: true);
    }
  }

  static Future<LocalComic> _importExtracted(
    File file,
    Directory workspace,
    Future<void> Function(LocalComic comic)? registerComic,
    Map<String, Object?>? source,
  ) async {
    final layout = ComicFileSystemLayout.inspect(
      workspace,
      unwrapSingleDirectory: true,
    );
    final cache = layout.root;
    var metaDataFile = File(FilePath.join(cache.path, 'metadata.json'));
    ComicMetaData? metaData;
    if (metaDataFile.existsSync()) {
      try {
        metaData = ComicMetaData.fromJson(
          jsonDecode(metaDataFile.readAsStringSync()),
        );
      } catch (e) {
        Log.warning("CBZ", "Failed to parse metadata: $e");
      }
    }
    metaData ??= ComicMetaData(
      title: file.name.substring(0, file.name.lastIndexOf('.')),
      author: "",
      tags: [],
    );
    var old = LocalManager().findByName(metaData.title);
    if (old != null) {
      throw Exception('Comic with name ${metaData.title} already exists');
    }
    final files = List<File>.from(layout.rootPages);
    final chapterDirectories = layout.chapters;
    if (!layout.hasImages) {
      throw Exception('No images found in the archive');
    }
    Map<String, String>? cpMap;
    final isZip =
        source != null && (await checkType(file)).mime == 'application/zip';
    final sourcePages =
        metaData.chapters == null && layout.useChapterDirectories
        ? chapterDirectories.expand((chapter) => chapter.pages)
        : metaData.chapters != null
        ? metaData.chapters!.expand(
            (chapter) => files.sublist(chapter.start - 1, chapter.end),
          )
        : files;
    final zipLocators = isZip
        ? await _zipSourceLocators(
            file.path,
            workspace.path,
            sourcePages
                .map(
                  (src) => path
                      .relative(src.path, from: workspace.path)
                      .replaceAll('\\', '/'),
                )
                .toSet()
                .toList(),
          )
        : null;
    var dest = Directory(
      FilePath.join(
        LocalManager().path,
        sanitizeFileName(metaData.title, maxLength: maxSanitizedFileNameLength),
      ),
    );
    if (dest.existsSync() ||
        File(dest.path).existsSync() ||
        Link(dest.path).existsSync()) {
      throw FileSystemException(
        'Archive output path is already occupied',
        dest.path,
      );
    }
    dest.createSync();
    final output = ComicImportOutput(dest);
    final provenance = source == null
        ? null
        : ComicSourceProvenance(source: source, pages: {});
    Future<void> copyPage(File src, File dst) async {
      await src.copyMem(dst.path);
      await provenance?.record(
        extracted: src,
        imported: dst,
        workspace: workspace,
        destination: dest,
        locator:
            zipLocators?[path
                .relative(src.path, from: workspace.path)
                .replaceAll('\\', '/')] ??
            const {},
      );
    }

    try {
      File coverFile;
      if (metaData.chapters == null && layout.useChapterDirectories) {
        coverFile = layout.inferredCover!;
        await coverFile.copyMem(
          FilePath.join(dest.path, 'cover.${coverFile.extension}'),
        );
        cpMap = <String, String>{};
        for (var i = 0; i < chapterDirectories.length; i++) {
          final chapter = chapterDirectories[i];
          final chapterKey = i.toString();
          cpMap[chapterKey] = chapter.title;
          final chapterDir = Directory(FilePath.join(dest.path, chapterKey));
          chapterDir.createSync();
          for (var j = 0; j < chapter.pages.length; j++) {
            final src = chapter.pages[j];
            final dst = File(
              FilePath.join(
                chapterDir.path,
                '${j + 1}.${src.path.split('.').last}',
              ),
            );
            await copyPage(src, dst);
          }
        }
      } else {
        if (files.isEmpty) {
          throw Exception('No images found in the archive');
        }
        coverFile = layout.inferredCover!;
        await coverFile.copyMem(
          FilePath.join(dest.path, 'cover.${coverFile.extension}'),
        );
        if (metaData.chapters == null) {
          for (var i = 0; i < files.length; i++) {
            var src = files[i];
            var dst = File(
              FilePath.join(dest.path, '${i + 1}.${src.path.split('.').last}'),
            );
            await copyPage(src, dst);
          }
        } else {
          dest.createSync();
          var chapters = <String, List<File>>{};
          for (var chapter in metaData.chapters!) {
            chapters[chapter.title] = files.sublist(
              chapter.start - 1,
              chapter.end,
            );
          }
          int i = 0;
          cpMap = <String, String>{};
          for (var chapter in chapters.entries) {
            cpMap[i.toString()] = chapter.key;
            var chapterDir = Directory(FilePath.join(dest.path, i.toString()));
            chapterDir.createSync();
            for (var j = 0; j < chapter.value.length; j++) {
              var src = chapter.value[j];
              var dst = File(
                FilePath.join(
                  chapterDir.path,
                  '${j + 1}.${src.path.split('.').last}',
                ),
              );
              await copyPage(src, dst);
            }
            i++;
          }
        }
      }
      var comic = LocalComic(
        id: LocalManager().findValidId(ComicType.local),
        title: metaData.title,
        subtitle: metaData.author,
        tags: metaData.tags,
        comicType: ComicType.local,
        directory: dest.name,
        chapters: ComicChapters.fromJsonOrNull(cpMap),
        downloadedChapters: cpMap?.keys.toList() ?? [],
        cover: 'cover.${coverFile.extension}',
        createdAt: DateTime.now(),
      );
      if (provenance != null) {
        final after = await ComicSourceProvenance.fingerprint(file);
        if (after['sha256'] != source!['sha256'] ||
            after['size'] != source['size']) {
          throw const FileSystemException(
            'Source archive changed during import',
          );
        }
        await provenance.write(dest);
      }
      await output.register(comic, registerComic);
      return comic;
    } catch (error, stack) {
      return await output.fail(error, stack);
    }
  }

  static Future<File> export(LocalComic comic, String outFilePath) async {
    var cache = Directory(FilePath.join(App.cachePath, 'cbz_export'));
    if (cache.existsSync()) cache.deleteSync(recursive: true);
    cache.createSync();
    List<ComicChapter>? chapters;
    var pageCount = 0;
    if (comic.chapters == null) {
      var images = await LocalManager().getImages(comic.id, comic.comicType, 1);
      pageCount = images.length;
      int i = 1;
      for (var image in images) {
        var src = File(localFilePathFromImageUri(image));
        var dstName = compatiblePageFileName(i, image.split('.').last);
        var dst = File(FilePath.join(cache.path, dstName));
        await src.copyMem(dst.path);
        i++;
      }
    } else {
      var allImages = <String>[];
      final chapterPageCounts = <MapEntry<String, int>>[];
      for (var c in comic.downloadedChapters) {
        var chapterName = comic.chapters![c];
        var images = await LocalManager().getImages(
          comic.id,
          comic.comicType,
          c,
        );
        allImages.addAll(images);
        chapterPageCounts.add(MapEntry(chapterName!, images.length));
      }
      chapters = buildChapterRanges(chapterPageCounts);
      pageCount = allImages.length;
      int i = 1;
      for (var image in allImages) {
        var src = File(localFilePathFromImageUri(image));
        var dstName = compatiblePageFileName(i, image.split('.').last);
        var dst = File(FilePath.join(cache.path, dstName));
        await src.copyMem(dst.path);
        i++;
      }
    }
    var cover = comic.coverFile;
    await cover.copyMem(
      FilePath.join(cache.path, 'cover.${cover.path.split('.').last}'),
    );
    final metaData = ComicMetaData(
      title: comic.title,
      author: comic.subtitle,
      tags: comic.tags,
      chapters: chapters,
    );
    await File(
      FilePath.join(cache.path, 'metadata.json'),
    ).writeAsString(jsonEncode(metaData));
    await File(
      FilePath.join(cache.path, 'ComicInfo.xml'),
    ).writeAsString(buildComicInfoXml(metaData, pageCount: pageCount));
    var cbz = File(outFilePath);
    if (cbz.existsSync()) cbz.deleteSync();
    await _compress(cache.path, cbz.path);
    cache.deleteSync(recursive: true);
    return cbz;
  }

  static String compatiblePageFileName(int pageIndex, String extension) {
    final normalizedExtension = extension.startsWith('.')
        ? extension.substring(1)
        : extension;
    return '${pageIndex.toString().padLeft(4, '0')}.$normalizedExtension';
  }

  static String localFilePathFromImageUri(String imageUri) {
    return imageUri.replaceFirst('file://', '');
  }

  static List<ComicChapter> buildChapterRanges(
    Iterable<MapEntry<String, int>> chapterPageCounts,
  ) {
    final chapters = <ComicChapter>[];
    var nextPage = 1;
    for (final chapter in chapterPageCounts) {
      final start = nextPage;
      final end = start + chapter.value - 1;
      chapters.add(ComicChapter(title: chapter.key, start: start, end: end));
      nextPage = end + 1;
    }
    return chapters;
  }

  static String buildComicInfoXml(
    ComicMetaData data, {
    required int pageCount,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="utf-8"?>');
    buffer.writeln(
      '<ComicInfo xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">',
    );

    buffer.writeln('  <Title>${_escapeXml(data.title)}</Title>');
    buffer.writeln('  <Series>${_escapeXml(data.title)}</Series>');

    final comicInfoTags = _buildComicInfoTags(data);

    if (comicInfoTags.writer.isNotEmpty) {
      buffer.writeln('  <Writer>${_escapeXml(comicInfoTags.writer)}</Writer>');
    }

    if (comicInfoTags.genres.isNotEmpty) {
      buffer.writeln(
        '  <Genre>${_escapeXml(comicInfoTags.genres.join(', '))}</Genre>',
      );
    }

    if (comicInfoTags.tags.isNotEmpty) {
      buffer.writeln(
        '  <Tags>${_escapeXml(comicInfoTags.tags.join(', '))}</Tags>',
      );
    }

    buffer.writeln('  <PageCount>$pageCount</PageCount>');

    if (data.chapters != null && data.chapters!.isNotEmpty) {
      final chaptersInfo = data.chapters!
          .map(
            (chapter) =>
                '${_escapeXml(chapter.title)}: ${chapter.start}-${chapter.end}',
          )
          .join('; ');
      buffer.writeln('  <Notes>Chapters: $chaptersInfo</Notes>');
    }

    buffer.writeln('  <Manga>Unknown</Manga>');
    buffer.writeln('  <BlackAndWhite>Unknown</BlackAndWhite>');

    if (pageCount > 0) {
      buffer.writeln('  <Pages>');
      for (var i = 0; i < pageCount; i++) {
        buffer.writeln('    <Page Image="$i" Type="Story" />');
      }
      buffer.writeln('  </Pages>');
    }

    final now = DateTime.now();
    buffer.writeln('  <Year>${now.year}</Year>');

    buffer.writeln('</ComicInfo>');
    return buffer.toString();
  }

  static String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static _ComicInfoTags _buildComicInfoTags(ComicMetaData data) {
    final writers = <String>[];
    if (data.author.isNotEmpty) {
      writers.add(data.author);
    }

    final genres = <String>[];
    final tags = <String>[];

    for (final tag in data.tags) {
      final normalizedTag = tag.trim();
      if (normalizedTag.isEmpty) continue;

      final separator = normalizedTag.indexOf(':');
      if (separator <= 0) {
        tags.add(normalizedTag);
        continue;
      }

      final key = normalizedTag.substring(0, separator).trim().toLowerCase();
      final value = normalizedTag.substring(separator + 1).trim();
      if (value.isEmpty) continue;

      switch (key) {
        case 'author':
        case 'authors':
        case 'artist':
        case 'artists':
          writers.addAll(_splitComicInfoValues(value));
        case 'category':
        case 'categories':
        case 'genre':
        case 'genres':
          genres.addAll(_splitComicInfoValues(value));
        case 'tag':
        case 'tags':
          tags.addAll(_splitComicInfoValues(value));
        default:
          tags.add(normalizedTag);
      }
    }

    return _ComicInfoTags(
      writer: _uniqueValues(writers).join(', '),
      genres: _uniqueValues(genres),
      tags: _uniqueValues(tags),
    );
  }

  static List<String> _splitComicInfoValues(String value) {
    return value
        .split(RegExp(r'[,，]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static List<String> _uniqueValues(List<String> values) {
    return values.toSet().toList();
  }

  static Future<void> _compress(String src, String dst) async {
    await ZipFile.compressFolderAsync(src, dst, 4);
  }
}

class _ComicInfoTags {
  final String writer;

  final List<String> genres;

  final List<String> tags;

  _ComicInfoTags({
    required this.writer,
    required this.genres,
    required this.tags,
  });
}

/// Decompression must not exceed the already extracted page's exact length.
class _BoundedZipEntryOutput extends archive_io.OutputFileStream {
  _BoundedZipEntryOutput(String path, this.limit)
    : super.withFileHandle(
        archive_io.FileHandle(path, mode: archive_io.FileAccess.write),
        bufferSize: 64 * 1024,
      );
  final int limit;
  void _check(int count) {
    if (count < 0 || length + count > limit) {
      throw const FormatException('ZIP 条目解压数据超过已校验页面长度');
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeBackReference(int distance, int count) {
    _check(count);
    super.writeBackReference(distance, count);
  }
}
