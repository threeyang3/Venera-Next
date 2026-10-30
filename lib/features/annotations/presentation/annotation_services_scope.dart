import 'package:flutter/widgets.dart';
import '../application/annotation_session.dart';
import '../application/annotation_manual_recovery.dart';
import '../application/annotation_restore_service.dart';
import '../application/annotation_export_service.dart';
import '../domain/source_document.dart';
import 'package:venera_next/foundation/annotation_link_contract.dart';

typedef LocateAnnotationPage =
    Future<AnnotationPageLocation> Function({
      required String libraryKey,
      required AnnotationSourcePage page,
    });

typedef OpenAnnotationSession =
    AnnotationSession Function({
      required String libraryKey,
      required String title,
      required String sourceRoot,
    });

typedef ExportAnnotationNotes =
    Future<AnnotationExportResult?> Function({
      required AnnotationSession session,
      required String title,
      required bool Function() isCancelled,
    });

/// Runtime composition supplies persistence; reader code never opens SQLite.
class AnnotationServicesScope extends InheritedWidget {
  const AnnotationServicesScope({
    super.key,
    required this.openSession,
    required super.child,
    this.exportNotes,
    this.locatePage,
    this.resolveLink,
    this.backupNotes,
    this.prepareRestore,
    this.relocateOriginal,
    this.findRecovery,
    this.recoverNotes,
    this.findManualRecovery,
    this.prepareManualRecovery,
  });
  final Future<AnnotationRestorePreview?> Function({
    required bool Function() isCancelled,
  })?
  prepareRestore;
  final OpenAnnotationSession openSession;
  final ExportAnnotationNotes? exportNotes;
  final LocateAnnotationPage? locatePage;
  final ResolveAnnotationLink? resolveLink;
  final Future<List<RecoverableAnnotationDocument>> Function({
    required AnnotationSession session,
  })?
  findRecovery;
  final Future<List<RecoverableAnnotationDocument>> Function({
    required AnnotationSession session,
  })?
  findManualRecovery;
  final Future<AnnotationManualRecoveryPreview?> Function({
    required AnnotationSession session,
    required String documentId,
    required bool Function() isCurrent,
  })?
  prepareManualRecovery;
  final Future<bool> Function({
    required AnnotationSession session,
    required String documentId,
    required bool Function() isCurrent,
  })?
  recoverNotes;
  final Future<bool> Function({
    required AnnotationSession session,
    required bool Function() isCurrent,
  })?
  relocateOriginal;
  final Future<String?> Function({required bool Function() isCancelled})?
  backupNotes;
  static AnnotationServicesScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AnnotationServicesScope>();
  @override
  bool updateShouldNotify(AnnotationServicesScope oldWidget) =>
      openSession != oldWidget.openSession ||
      exportNotes != oldWidget.exportNotes ||
      locatePage != oldWidget.locatePage ||
      resolveLink != oldWidget.resolveLink ||
      backupNotes != oldWidget.backupNotes ||
      prepareRestore != oldWidget.prepareRestore ||
      relocateOriginal != oldWidget.relocateOriginal ||
      findRecovery != oldWidget.findRecovery ||
      recoverNotes != oldWidget.recoverNotes ||
      findManualRecovery != oldWidget.findManualRecovery ||
      prepareManualRecovery != oldWidget.prepareManualRecovery;
}
