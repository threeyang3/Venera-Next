import 'package:venera_next/features/annotations/data/annotation_restore.dart';
import 'package:venera_next/features/annotations/application/annotation_restore_service.dart';
import 'package:file_selector/file_selector.dart';
import 'package:venera_next/features/annotations/application/annotation_export_service.dart';
import 'package:venera_next/features/annotations/application/annotation_session.dart';
import 'annotation_assets.dart';
import 'package:path/path.dart' as p;
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/features/annotations/data/annotation_backup.dart';

Future<String?> backupLocalAnnotations({
  required bool Function() isCancelled,
}) async {
  final destination = await getDirectoryPath(confirmButtonText: '备份全部批注');
  if (destination == null || isCancelled()) return null;
  return backupAnnotationDatabase(
    databasePath: p.join(App.dataPath, 'annotations.db'),
    destination: destination,
    isCancelled: isCancelled,
  );
}

Future<AnnotationExportResult?> exportLocalAnnotations({
  required AnnotationSession session,
  required String title,
  required bool Function() isCancelled,
}) async {
  session.refresh();
  final notes = session.all;
  if (notes.isEmpty) throw StateError('还没有可导出的批注');
  final destination = await getDirectoryPath(confirmButtonText: '导出图文笔记');
  if (destination == null || isCancelled()) return null;
  return AnnotationExportService(
    resolveImage: (note) =>
        resolveLocalAnnotationImage(session, note, isCancelled: isCancelled),
  ).export(
    destination: destination,
    documentId: session.documentId,
    title: title,
    annotations: notes,
    isCancelled: isCancelled,
  );
}

Future<AnnotationRestorePreview?> prepareLocalAnnotationRestore({
  required bool Function() isCancelled,
}) async {
  final directory = await getDirectoryPath(confirmButtonText: '选择批注备份文件夹');
  if (directory == null || isCancelled()) return null;
  return prepareAnnotationRestore(
    backupDirectory: directory,
    databasePath: p.join(App.dataPath, 'annotations.db'),
    isCancelled: isCancelled,
  );
}
