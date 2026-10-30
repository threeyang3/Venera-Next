import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/annotation.dart';
import '../domain/geometry.dart';

class AnnotationEditor extends StatefulWidget {
  const AnnotationEditor({
    super.key,
    required this.page,
    required this.kind,
    this.rect,
    this.initialText = '',
    this.persistent = false,
    this.errorText,
  });
  final PageAnchor page;
  final AnnotationKind kind;
  final ContentRect? rect;
  final String initialText;
  final bool persistent;
  final String? errorText;

  @override
  State<AnnotationEditor> createState() => _AnnotationEditorState();
}

class _AnnotationEditorState extends State<AnnotationEditor> {
  late final _text = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rect = widget.rect;
    final macWorkspace =
        Theme.of(context).platform == TargetPlatform.macOS &&
        const bool.fromEnvironment('COMICNOTES_WORKSPACE');
    void save() => Navigator.of(context).pop(_text.text);
    return Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent ||
            event.logicalKey != LogicalKeyboardKey.enter ||
            HardwareKeyboard.instance.isShiftPressed ||
            HardwareKeyboard.instance.isAltPressed) {
          return KeyEventResult.ignored;
        }
        final composing = _text.value.composing;
        if (composing.isValid && !composing.isCollapsed) {
          return KeyEventResult.ignored;
        }
        save();
        return KeyEventResult.handled;
      },
      child: AlertDialog(
        title: Text(switch (widget.kind) {
          AnnotationKind.region => '区域批注',
          AnnotationKind.pageNote => '整页笔记',
          AnnotationKind.bookmark => '书签',
        }),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  macWorkspace
                      ? '第 ${widget.page.sourceImageNumber} 页 · ${widget.persistent ? '保存在此 Mac' : '本次阅读笔记'}'
                      : '第 ${widget.page.sourceImageNumber} 张原图 · ${widget.persistent ? '保存到本地批注库' : '本轮阅读内有效'}',
                ),
                if (widget.errorText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      widget.errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _text,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    hintText: '写下对画面的观察…',
                    helperText: 'Enter 保存 · Shift+Enter 换行',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (rect != null && !macWorkspace)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '选区：${rect.x0.toStringAsFixed(3)}, ${rect.y0.toStringAsFixed(3)} → ${rect.x1.toStringAsFixed(3)}, ${rect.y1.toStringAsFixed(3)}',
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(onPressed: save, child: const Text('保存')),
        ],
      ),
    );
  }
}
