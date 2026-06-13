import 'package:flutter/services.dart';
import 'package:proxypin/network/util/logger.dart';

/// 透明代理控制通道（root + iptables 模式）
class TransparentProxy {
  static const MethodChannel _channel = MethodChannel('com.proxy/transparent');

  static bool _running = false;

  static bool get isRunning => _running;

  /// 启动透明代理
  /// [proxyPort] 为 Flutter 代理服务器的端口
  static Future<bool> start({int proxyPort = 9091}) async {
    if (_running) return true;
    try {
      final result = await _channel.invokeMethod<bool>('start', {'proxyPort': proxyPort});
      _running = result ?? false;
      logger.i('TransparentProxy started: $_running');
      return _running;
    } catch (e) {
      logger.e('TransparentProxy start failed', error: e);
      return false;
    }
  }

  /// 停止透明代理
  static Future<void> stop() async {
    if (!_running) return;
    try {
      await _channel.invokeMethod('stop');
      _running = false;
      logger.i('TransparentProxy stopped');
    } catch (e) {
      logger.e('TransparentProxy stop failed', error: e);
    }
  }
}
