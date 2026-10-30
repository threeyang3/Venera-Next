import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Root route inventory: opening files is available on pages, while popup
/// interactions retain their own focus and keyboard commands.
class ImportCommandRoutes extends NavigatorObserver {
  final _routes = <Route<dynamic>>[];
  bool get canOpen => _routes.isNotEmpty && _routes.last is PageRoute;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.add(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
  }
}

/// Placed above the root Navigator, so pushed readers and discovery routes
/// receive the same open command as the library.
class ImportCommands extends StatefulWidget {
  const ImportCommands({
    super.key,
    required this.routes,
    required this.canOpen,
    required this.open,
    required this.child,
  });
  final ImportCommandRoutes routes;
  final bool Function() canOpen;
  final Future<void> Function() open;
  final Widget child;
  @override
  State<ImportCommands> createState() => _ImportCommandsState();
}

class _ImportCommandsState extends State<ImportCommands> {
  bool _opening = false;
  Future<void> _open() async {
    if (_opening || !widget.routes.canOpen || !widget.canOpen()) return;
    _opening = true;
    try {
      await widget.open();
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyO, meta: true): _open,
      const SingleActivator(LogicalKeyboardKey.keyO, control: true): _open,
    },
    child: Focus(autofocus: true, child: widget.child),
  );
}
