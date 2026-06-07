import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class CentrifugoClient {
  WebSocketChannel? _channel;
  int _idCounter = 0;
  final Map<String, StreamController<Map<String, dynamic>>>
  _subscriptionControllers = {};

  Future<void> connect(String wsUrl, String token) async {
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    final connectMsg = jsonEncode({
      'id': ++_idCounter,
      'connect': {'token': token},
    });
    _channel!.sink.add(connectMsg);

    _channel!.stream.listen(_onMessage, onError: _onError, onDone: _onDone);
  }

  Stream<Map<String, dynamic>> subscribeToThread(String threadId) {
    final channel = 'thread:$threadId';
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    _subscriptionControllers[channel] = controller;

    final subscribeMsg = jsonEncode({
      'id': ++_idCounter,
      'subscribe': {'channel': channel},
    });
    _channel?.sink.add(subscribeMsg);

    return controller.stream;
  }

  void _onMessage(dynamic raw) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    // Handle ping
    if (msg.containsKey('ping')) {
      _channel?.sink.add(jsonEncode({'pong': {}}));
      return;
    }

    // Handle push publications
    if (msg.containsKey('push')) {
      final push = msg['push'] as Map<String, dynamic>;
      final channelName = push['channel'] as String?;
      if (channelName != null &&
          _subscriptionControllers.containsKey(channelName)) {
        final pub = push['pub'] as Map<String, dynamic>?;
        if (pub != null) {
          final data = pub['data'] as Map<String, dynamic>?;
          if (data != null) {
            _subscriptionControllers[channelName]!.add(data);
          }
        }
      }
    }
  }

  void _onError(Object error) {
    for (final controller in _subscriptionControllers.values) {
      controller.addError(error);
    }
  }

  void _onDone() {
    for (final controller in _subscriptionControllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _subscriptionControllers.clear();
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    for (final controller in _subscriptionControllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _subscriptionControllers.clear();
  }
}
