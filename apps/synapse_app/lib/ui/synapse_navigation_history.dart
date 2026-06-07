import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

class SynapseNavigationHistory extends ChangeNotifier {
  SynapseNavigationHistory._();

  static final SynapseNavigationHistory instance = SynapseNavigationHistory._();

  final List<String> _back = [];
  final List<String> _forward = [];
  String? _current;
  bool _ignoreNextRecord = false;

  bool get canGoBack => _back.isNotEmpty;
  bool get canGoForward => _forward.isNotEmpty;

  void record(String location) {
    if (location.isEmpty || location == _current) return;

    if (_ignoreNextRecord) {
      _ignoreNextRecord = false;
      _current = location;
      notifyListeners();
      return;
    }

    final previous = _current;
    if (previous != null) {
      _back.add(previous);
      if (_back.length > 80) _back.removeAt(0);
    }
    _current = location;
    _forward.clear();
    notifyListeners();
  }

  void goBack(GoRouter router) {
    if (!canGoBack) return;
    final destination = _back.removeLast();
    final previous = _current;
    if (previous != null) _forward.add(previous);
    _current = destination;
    _ignoreNextRecord = true;
    notifyListeners();
    router.go(destination);
  }

  void goForward(GoRouter router) {
    if (!canGoForward) return;
    final destination = _forward.removeLast();
    final previous = _current;
    if (previous != null) _back.add(previous);
    _current = destination;
    _ignoreNextRecord = true;
    notifyListeners();
    router.go(destination);
  }

  void clear() {
    _back.clear();
    _forward.clear();
    _current = null;
    _ignoreNextRecord = false;
    notifyListeners();
  }
}
