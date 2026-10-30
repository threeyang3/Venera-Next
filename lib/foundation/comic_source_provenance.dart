import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'pdf_page_geometry.dart';

/// A portable source receipt: archive resources retain original bytes, while
/// PDF pages retain geometry and rendered-cache fingerprints. Imported paths
/// are relative to the comic, never destinations supplied by the archive.
class ComicSourceProvenance {
  ComicSourceProvenance({required this.source, required this.pages});
  static const filename = '.comicnotes-source.json';
  final Map<String, Object?> source;
  final Map<String, Map<String, Object?>> pages;

  static bool validRelativePath(String value) =>
      value.isNotEmpty &&
      !value.contains('\\') &&
      !value.contains('\u0000') &&
      !p.posix.isAbsolute(value) &&
      !RegExp(r'^[A-Za-z]:').hasMatch(value) &&
      !value.split('/').any((s) => s.isEmpty || s == '.' || s == '..');

  static Future<Map<String, Object?>> fingerprint(File file) async => {
    'size': await file.length(),
    'sha256': (await sha256.bind(file.openRead()).first).toString(),
  };

  Future<void> record({
    required File extracted,
    required File imported,
    required Directory workspace,
    required Directory destination,
    Map<String, Object?> locator = const {},
  }) async {
    final entry = p
        .split(p.relative(extracted.path, from: workspace.path))
        .join('/');
    final identity = p
        .split(p.relative(imported.path, from: destination.path))
        .join('/');
    if (!validRelativePath(entry) || !validRelativePath(identity)) {
      throw const FormatException('Invalid archive source path');
    }
    // Native extractors must not supply a link escaping the owned workspace.
    if (!p.isWithin(
      workspace.resolveSymbolicLinksSync(),
      extracted.resolveSymbolicLinksSync(),
    )) {
      throw const FileSystemException(
        'Archive image escapes extraction workspace',
      );
    }
    final original = await fingerprint(extracted);
    final copy = await fingerprint(imported);
    if (original['sha256'] != copy['sha256'] ||
        original['size'] != copy['size']) {
      throw const FileSystemException(
        'Imported image is not a complete original copy',
      );
    }
    pages[identity] = {
      ...locator,
      'kind': source['kind'] == 'epub' ? 'epubImage' : 'archiveImage',
      'extractedEntry': entry,
      ...copy,
    };
  }

  Future<void> write(Directory directory) =>
      File(p.join(directory.path, filename)).writeAsString(
        jsonEncode({'schemaVersion': 1, 'source': source, 'pages': pages}),
        flush: true,
      );

  static ComicSourceProvenance? read(Directory directory) {
    return readFile(File(p.join(directory.path, filename)));
  }

  static ComicSourceProvenance? readFile(File file) {
    if (!file.existsSync()) return null;
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        file.lengthSync() > 16 * 1024 * 1024) {
      throw const FormatException('Invalid comic source receipt');
    }
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    if (data['schemaVersion'] != 1) {
      throw const FormatException('Unknown comic source receipt version');
    }
    final source = Map<String, Object?>.from(data['source'] as Map);
    if (!{'archive', 'pdf', 'epub', 'folder'}.contains(source['kind']) ||
        !_validFingerprint(source) ||
        source['uri'] is! String) {
      throw const FormatException('Invalid document source');
    }
    final pages = <String, Map<String, Object?>>{};
    for (final item in (data['pages'] as Map).entries) {
      final page = Map<String, Object?>.from(item.value as Map);
      if (item.key is! String ||
          !validRelativePath(item.key as String) ||
          !_validFingerprint(page)) {
        throw const FormatException('Invalid source page receipt');
      }
      if (source['kind'] == 'archive' && page['kind'] == 'archiveImage') {
        if (page['extractedEntry'] is! String ||
            !validRelativePath(page['extractedEntry'] as String)) {
          throw const FormatException('Invalid archive image receipt');
        }
        if (page.keys.any((key) => key.startsWith('archiveEntry')) ||
            page.containsKey('matchingEntryIndices')) {
          if (page['archiveEntryIndex'] is! int ||
              (page['archiveEntryIndex'] as int) < 0 ||
              page['archiveEntryOccurrence'] is! int ||
              (page['archiveEntryOccurrence'] as int) < 0 ||
              page['archiveEntryCount'] is! int ||
              (page['archiveEntryCount'] as int) < 1 ||
              (page['archiveEntryOccurrence'] as int) >=
                  (page['archiveEntryCount'] as int) ||
              page['archiveEntryName'] is! String ||
              (page['archiveEntryName'] as String).isEmpty ||
              !{
                'uniquePath',
                'contentMatched',
              }.contains(page['archiveEntryResolution'])) {
            throw const FormatException('Invalid ZIP entry occurrence');
          }
          final resolution = page['archiveEntryResolution'];
          if ((resolution == 'uniquePath' &&
                  (page['archiveEntryCount'] != 1 ||
                      page['archiveEntryOccurrence'] != 0)) ||
              (resolution == 'contentMatched' &&
                  ((page['archiveEntryCount'] as int) < 2 ||
                      page['matchingEntryIndices'] == null)) ||
              (page['archiveEntryIndex'] as int) <
                  (page['archiveEntryOccurrence'] as int)) {
            throw const FormatException('Inconsistent ZIP entry resolution');
          }
          final matches = page['matchingEntryIndices'];
          if (matches != null &&
              (matches is! List ||
                  matches.isEmpty ||
                  !matches.every((index) => index is int && index >= 0) ||
                  matches.toSet().length != matches.length ||
                  matches.first != page['archiveEntryIndex'] ||
                  matches.length > (page['archiveEntryCount'] as int))) {
            throw const FormatException('Invalid matching ZIP entry indices');
          }
        }
      } else if (source['kind'] == 'folder' && page['kind'] == 'folderImage') {
        if (page['relativePath'] != item.key) {
          throw const FormatException('Invalid folder image receipt');
        }
      } else if (source['kind'] == 'pdf' && page['kind'] == 'pdfPage') {
        PdfPageGeometry.fromJson(page);
        if (page['retainedSourcePath'] != null &&
            (page['retainedSourcePath'] is! String ||
                !validRelativePath(page['retainedSourcePath'] as String))) {
          throw const FormatException('Invalid retained PDF path');
        }
      } else if (source['kind'] == 'epub' && page['kind'] == 'epubImage') {
        for (final key in [
          'opfPath',
          'spineItemPath',
          'imageResourcePath',
          'extractedEntry',
        ]) {
          if (page[key] is! String || !validRelativePath(page[key] as String)) {
            throw const FormatException('Invalid EPUB resource path');
          }
        }
        for (final key in [
          'spineIndex',
          'imageOccurrence',
          'resourceOccurrence',
        ]) {
          if (page[key] is! int || (page[key] as int) < 0) {
            throw const FormatException('Invalid EPUB occurrence');
          }
        }
        if (page['spineItemId'] is! String ||
            (page['spineItemId'] as String).isEmpty ||
            page['imageManifestIds'] is! List ||
            !(page['imageManifestIds'] as List).every(
              (v) => v is String && v.isNotEmpty,
            ) ||
            page['imageResourcePath'] != page['extractedEntry']) {
          throw const FormatException('Invalid EPUB manifest context');
        }
      } else {
        throw const FormatException('Source page kind does not match document');
      }
      pages[item.key as String] = Map.unmodifiable(page);
    }
    return ComicSourceProvenance(
      source: Map.unmodifiable(source),
      pages: Map.unmodifiable(pages),
    );
  }

  static bool _validFingerprint(Map<String, Object?> value) =>
      value['size'] is int &&
      (value['size'] as int) >= 0 &&
      value['sha256'] is String &&
      RegExp(r'^[a-f0-9]{64}$').hasMatch(value['sha256'] as String);
}
