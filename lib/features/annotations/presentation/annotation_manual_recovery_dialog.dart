import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../application/annotation_manual_recovery.dart';
import '../domain/source_document.dart';
import '../domain/annotation.dart';
import '../domain/geometry.dart';
import 'region_overlay.dart';

/// Owns preparation and its private preview until the route and any in-flight
/// verification have both drained. Closing the route cancels unpublished work.
Future<bool> showAnnotationManualRecoveryDialog(
  BuildContext context, {
  required Future<AnnotationManualRecoveryPreview?> Function({
    required bool Function() isCurrent,
  })
  prepare,
  required bool Function() isCurrent,
  Future<void>? cancelSignal,
}) async {
  var active = true;
  Future<AnnotationManualRecoveryPreview?>? loading;
  bool current() => active && isCurrent();
  Future<AnnotationManualRecoveryPreview?> load() =>
      loading ??= prepare(isCurrent: current);
  if (!isCurrent()) return false;
  final navigator = Navigator.of(context, rootNavigator: true);
  late final DialogRoute<bool> route;
  void closeOwnedRoute() {
    active = false;
    scheduleMicrotask(() {
      if (navigator.mounted && route.isActive) {
        navigator.removeRoute(route, false);
      }
    });
  }

  route = DialogRoute<bool>(
    context: context,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    barrierDismissible: false,
    builder: (_) => _ManualRecoveryDialog(
      load: load,
      isCurrent: current,
      onTargetLost: closeOwnedRoute,
    ),
  );
  cancelSignal?.then((_) {
    if (active) closeOwnedRoute();
  });
  try {
    return await navigator.push<bool>(route) ?? false;
  } finally {
    active = false;
    AnnotationManualRecoveryPreview? preview;
    try {
      preview = await loading;
    } catch (_) {
      // Preparation errors are already displayed by the dialog.
    }
    await preview?.dispose();
  }
}

class _ManualRecoveryDialog extends StatefulWidget {
  const _ManualRecoveryDialog({
    required this.load,
    required this.isCurrent,
    required this.onTargetLost,
  });
  final VoidCallback onTargetLost;
  final Future<AnnotationManualRecoveryPreview?> Function() load;
  final bool Function() isCurrent;
  @override
  State<_ManualRecoveryDialog> createState() => _ManualRecoveryDialogState();
}

class _ManualRecoveryDialogState extends State<_ManualRecoveryDialog> {
  AnnotationManualRecoveryPreview? _preview;
  List<AnnotationSourcePage> _pages = [];
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final preview = await widget.load();
      if (!mounted) return;
      if (preview == null || !widget.isCurrent()) {
        widget.onTargetLost();
        return;
      }
      setState(() {
        _preview = preview;
        _pages = [...preview.previousPages]
          ..sort((a, b) {
            final chapter = a.anchor.chapterId.compareTo(b.anchor.chapterId);
            return chapter == 0
                ? a.anchor.sourceImageNumber.compareTo(
                    b.anchor.sourceImageNumber,
                  )
                : chapter;
          });
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '无法准备预览：$error';
        });
      }
    }
  }

  final _mapping = <String, String>{};
  int _index = 0;
  bool _acknowledged = false, _busy = false;
  String? _error;
  Future<void> _commit() async {
    if (_busy ||
        !_acknowledged ||
        _mapping.length != _pages.length ||
        !widget.isCurrent()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final success = await _preview!.commit(
        pageMapping: Map.unmodifiable(_mapping),
        isCurrent: () => mounted && widget.isCurrent(),
      );
      if (!mounted) return;
      if (success && widget.isCurrent()) {
        Navigator.pop(context, true);
      } else {
        setState(() => _error = '恢复已取消或阅读目标已变化，未提交映射。');
      }
    } catch (error) {
      if (mounted) setState(() => _error = '恢复失败，旧批注仍保留。\n$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _targetImage(
    AnnotationSourcePage page,
    AnnotationManualTargetPage target,
    List<Annotation> notes,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: AspectRatio(
            aspectRatio: page.anchor.sourceWidth / page.anchor.sourceHeight,
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    target.thumbnail,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                  ),
                  AnnotationOverlay(
                    page: page.anchor,
                    transform: ViewportTransform(
                      constraints.maxWidth,
                      0,
                      0,
                      constraints.maxHeight,
                      0,
                      0,
                    ),
                    annotations: notes,
                    selecting: false,
                    onSelected: (_, _) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _preview == null) {
      return AlertDialog(
        title: Text(_loading ? '正在校验目标页…' : '无法打开逐页预览'),
        content: _loading
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : SelectableText(_error ?? '未找到可预览的来源页'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_loading ? '取消校验' : '关闭'),
          ),
        ],
      );
    }
    if (_pages.isEmpty) {
      return AlertDialog(
        title: const Text('没有可恢复的来源页'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('关闭'),
          ),
        ],
      );
    }
    final page = _pages[_index], id = page.anchor.pageId;
    final selected = _preview!.targets
        .where((target) => target.page.anchor.pageId == _mapping[id])
        .firstOrNull;
    final candidates = _preview!.targets
        .where(
          (target) =>
              target.page.anchor.sourceWidth == page.anchor.sourceWidth &&
              target.page.anchor.sourceHeight == page.anchor.sourceHeight &&
              (!_mapping.values.contains(target.page.anchor.pageId) ||
                  _mapping[id] == target.page.anchor.pageId),
        )
        .toList();
    final notes = _preview!.annotations
        .where((note) => note.anchor.pageId == id)
        .toList();
    return AlertDialog(
      title: const Text('逐页关联旧批注'),
      content: SizedBox(
        width: 760,
        height: math.min(640, MediaQuery.sizeOf(context).height * .65),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '上一张旧页',
                  onPressed: _busy || _index == 0
                      ? null
                      : () => setState(() => _index--),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '旧页 ${_index + 1} / ${_pages.length} · 已关联 ${_mapping.length} 页',
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  tooltip: '下一张旧页',
                  onPressed: _busy || _index == _pages.length - 1
                      ? null
                      : () => setState(() => _index++),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('旧原图未自动验证。请对照原件或原导出，逐页核对文字和框线；此操作不证明两个版本内容相同。'),
                    const SizedBox(height: 12),

                    Text(
                      '${page.anchor.chapterId} · 原图 ${page.anchor.sourceImageNumber} · ${page.anchor.sourceWidth.toInt()} × ${page.anchor.sourceHeight.toInt()}',
                    ),
                    SelectableText(page.sourceIdentity),
                    if (notes.isEmpty) const Text('此页仅含历史或删除记录，仍需保持页身份。'),
                    for (final note in notes)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(note.text.isEmpty ? '（无文字批注）' : note.text),
                      ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey((id, _mapping[id])),
                      initialValue: _mapping[id],
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '选择目标原图',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final target in candidates)
                          DropdownMenuItem(
                            value: target.page.anchor.pageId,
                            child: Text(
                              '${target.page.anchor.chapterId} · ${target.page.anchor.sourceImageNumber} · ${target.page.sourceIdentity}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) => setState(() {
                              if (value != null) _mapping[id] = value;
                              _acknowledged = false;
                              _error = null;
                            }),
                    ),
                    if (selected != null)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _mapping.remove(id);
                                _acknowledged = false;
                                _error = null;
                              }),
                        child: const Text('清除此页关联'),
                      ),
                    if (candidates.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('没有未使用且自然尺寸一致的目标页。请检查其他页的选择，或重新导入合适版本。'),
                      ),
                    if (selected != null) _targetImage(page, selected, notes),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _acknowledged,
                      onChanged: _busy || _mapping.length != _pages.length
                          ? null
                          : (value) =>
                                setState(() => _acknowledged = value ?? false),
                      title: const Text('我已逐页核对目标内容和所有选区'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SelectableText(_error!),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(_busy ? '取消校验' : '取消'),
        ),
        FilledButton(
          onPressed: _busy || !_acknowledged || _mapping.length != _pages.length
              ? null
              : _commit,
          child: Text(_busy ? '正在校验并恢复…' : '确认恢复旧批注'),
        ),
      ],
    );
  }
}
