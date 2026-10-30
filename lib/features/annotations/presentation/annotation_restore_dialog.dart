import 'package:flutter/material.dart';
import '../application/annotation_restore_service.dart';
import '../application/annotation_export_service.dart';
import 'annotation_services_scope.dart';

Future<void> showAnnotationRestoreDialog(BuildContext context) async {
  final prepare = AnnotationServicesScope.maybeOf(context)?.prepareRestore;
  if (prepare == null) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _RestoreDialog(prepare: prepare),
  );
}

class _RestoreDialog extends StatefulWidget {
  const _RestoreDialog({required this.prepare});
  final Future<AnnotationRestorePreview?> Function({
    required bool Function() isCancelled,
  })
  prepare;
  @override
  State<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<_RestoreDialog> {
  AnnotationRestorePreview? _preview;
  String? _message;
  bool _busy = true;
  bool _finished = false;
  bool _cancelled = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    AnnotationRestorePreview? preview;
    try {
      preview = await widget.prepare(isCancelled: () => _cancelled);
      if (!mounted) {
        await preview?.dispose();
        return;
      }
      if (preview == null) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        _preview = preview;
        _busy = false;
      });
    } catch (error) {
      await preview?.dispose();
      if (mounted) {
        setState(() {
          _message = '备份验证失败：$error';
          _busy = false;
          _finished = true;
        });
      }
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final result = await _preview!.restore(isCancelled: () => _cancelled);
      if (mounted) {
        setState(() {
          _message =
              '已恢复 ${result.importedDocuments} 册书的批注，跳过 ${result.skippedDocuments} 册已有记录。\n\n有原件指纹的记录：导入对应原件后，在批注面板选择“恢复旧批注”重新关联。无指纹旧记录仍需后续手工映射。旧批注 UUID 保持不变。';
          _finished = true;
        });
      }
    } on AnnotationExportCancelled {
      // Closing the dialog cancels unpublished work.
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = '恢复失败，未导入任何记录：$error';
          _finished = true;
        });
      }
    } finally {
      await _preview?.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    // Restore is synchronous within a SQLite transaction. Disposal cannot race
    // its connection; prepare owns and removes any unfinished staging snapshot.
    _preview?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return AlertDialog(
      title: const Text('恢复批注备份'),
      content: SizedBox(
        width: 420,
        child: _busy
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在验证或导入备份…'),
                ],
              )
            : SelectableText(
                _message ??
                    '备份包含 ${preview!.documentCount} 册书、${preview.annotationCount} 条未删除批注。\n其中 ${preview.existingDocumentCount} 册已存在，将整册跳过；现有笔记和删除记录会保留。\n\n备份不含图片。有原件指纹的记录可在导入同一原件后重新关联；无指纹旧记录会保留，暂不支持手工映射。',
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_finished ? '关闭' : '取消'),
        ),
        if (!_busy && !_finished)
          FilledButton(onPressed: _restore, child: const Text('导入缺失的批注')),
      ],
    );
  }
}
