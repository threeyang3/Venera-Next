import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = _RecordingSemanticsBinding();

  setUp(binding.resetObservations);

  testWidgets(
    'hidden overlay anchors never serialize orphan nodes and recover',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final opacity = ValueNotifier(0.0);
      final controller = OverlayPortalController()..show();
      final entry = OverlayEntry(
        builder: (_) => ValueListenableBuilder<double>(
          valueListenable: opacity,
          builder: (_, value, _) => Opacity(
            opacity: value,
            child: OverlayPortal(
              controller: controller,
              overlayChildBuilder: (_) => Align(
                alignment: Alignment.topRight,
                child: Semantics(
                  container: true,
                  label: 'Overlay child',
                  child: const SizedBox(width: 100, height: 40),
                ),
              ),
              child: Semantics(
                container: true,
                label: 'Anchor',
                child: const SizedBox(width: 100, height: 40),
              ),
            ),
          ),
        ),
      );
      try {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Overlay(initialEntries: [entry]),
          ),
        );
        binding.expectConnectedUpdates();
        expect(binding.reachableLabels, isNot(contains('Overlay child')));

        for (final value in [1.0, 0.0, 1.0]) {
          opacity.value = value;
          await tester.pump();
          binding.expectConnectedUpdates();
          if (value == 1) {
            expect(
              binding.reachableLabels,
              containsAll(['Anchor', 'Overlay child']),
            );
          } else {
            expect(binding.reachableLabels, isNot(contains('Overlay child')));
          }
        }
      } finally {
        entry.remove();
        await tester.pumpWidget(const SizedBox());
        entry.dispose();
        opacity.dispose();
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'pushing and popping a Slider route preserves engine tree links',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('Reader')),
                        body: Slider(
                          value: 0.5,
                          divisions: 10,
                          label: 'Page 5',
                          onChanged: (_) {},
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open reader'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open reader'));
        await tester.pump();
        binding.expectConnectedUpdates();
        await tester.pumpAndSettle();
        binding.expectConnectedUpdates();
        expect(find.byType(Slider), findsOneWidget);
        await tester.pageBack();
        await tester.pump();
        binding.expectConnectedUpdates();
        await tester.pumpAndSettle();
        binding.expectConnectedUpdates();
      } finally {
        await tester.pumpWidget(const SizedBox());
        semantics.dispose();
      }
    },
  );
}

// Record exactly the node IDs and edges submitted to the engine, rather than
// merely inspecting the framework's in-memory semantics tree. A disconnected
// incremental update permanently freezes macOS AX even when that tree looks fine.
class _RecordingSemanticsBinding extends AutomatedTestWidgetsFlutterBinding {
  final nodes =
      <int, ({String label, List<int> traversal, List<int> hitTest})>{};
  final orphanUpdates = <String>[];

  void resetObservations() {
    nodes.clear();
    orphanUpdates.clear();
  }

  Set<int> reachable({bool hitTest = false}) {
    final result = <int>{};
    void visit(int id) {
      if (!result.add(id)) return;
      final node = nodes[id];
      if (node == null) return;
      for (final child in hitTest ? node.hitTest : node.traversal) {
        visit(child);
      }
    }

    visit(0);
    return result;
  }

  Iterable<String> get reachableLabels =>
      reachable().map((id) => nodes[id]?.label ?? '');

  void expectConnectedUpdates() => expect(orphanUpdates, isEmpty);

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _RecordingUpdateBuilder(this);
}

class _RecordingUpdateBuilder extends Fake
    implements ui.SemanticsUpdateBuilder {
  _RecordingUpdateBuilder(this.binding);

  final _RecordingSemanticsBinding binding;
  final _builder = ui.SemanticsUpdateBuilder();
  final updated = <int>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      final arguments = invocation.namedArguments;
      final id = arguments[#id] as int;
      updated.add(id);
      binding.nodes[id] = (
        label: arguments[#label] as String,
        traversal: List<int>.of(
          arguments[#childrenInTraversalOrder] as List<int>,
        ),
        hitTest: List<int>.of(arguments[#childrenInHitTestOrder] as List<int>),
      );
      return null;
    }
    return super.noSuchMethod(invocation);
  }

  @override
  void updateCustomAction({
    required int id,
    String? label,
    String? hint,
    int overrideId = -1,
  }) => _builder.updateCustomAction(
    id: id,
    label: label,
    hint: hint,
    overrideId: overrideId,
  );

  @override
  ui.SemanticsUpdate build() {
    for (final hitTest in [false, true]) {
      final orphans = updated.difference(binding.reachable(hitTest: hitTest));
      if (orphans.isNotEmpty) {
        binding.orphanUpdates.add(
          '${hitTest ? 'hit-test' : 'traversal'} orphan IDs: $orphans',
        );
      }
    }
    return _builder.build();
  }
}
