import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'sibling overlay anchors retain both accessible overlay children',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final first = OverlayPortalController();
        final second = OverlayPortalController();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  Row(
                    children: [
                      OverlayPortal(
                        controller: first,
                        overlayChildBuilder: (_) => const Text('Overlay A'),
                        child: const Text('Anchor A'),
                      ),
                      OverlayPortal(
                        controller: second,
                        overlayChildBuilder: (_) => const Text('Overlay B'),
                        child: const Text('Anchor B'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
        first.show();
        second.show();
        await tester.pump();

        final labels = <String>[];
        void visit(SemanticsNode node) {
          labels.add(node.getSemanticsData().label);
          for (final child in node.debugListChildrenInOrder(
            DebugSemanticsDumpOrder.traversalOrder,
          )) {
            visit(child);
          }
        }

        visit(
          tester
              .binding
              .renderViews
              .single
              .owner!
              .semanticsOwner!
              .rootSemanticsNode!,
        );
        expect(labels, containsAll(['Overlay A', 'Overlay B']));
        await tester.pumpWidget(const SizedBox());
      } finally {
        semantics.dispose();
      }
    },
  );
}
