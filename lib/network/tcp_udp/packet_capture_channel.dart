/*
 * TCP/UDP 数据包 MethodChannel 桥接
 * 接收来自 Android 原生 VPN 层的原始数据包
 */

import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:proxypin/network/tcp_udp/raw_packet.dart';
import 'package:proxypin/network/tcp_udp/packet_capture_manager.dart';
import 'package:proxypin/network/util/logger.dart';

/// TCP/UDP 数据包捕获通道
class PacketCaptureChannel {
  static const MethodChannel _channel = MethodChannel('com.proxy/packetCapture');

  static bool _initialized = false;

  /// 初始化通道，开始接收数据包
  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler(_handleMethodCall);
    logger.i('PacketCaptureChannel initialized');
  }

  /// 处理方法调用
  static Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPacket':
        _onPacket(call.arguments as Map);
        break;
      case 'onSessionClosed':
        _onSessionClosed(call.arguments as Map);
        break;
      default:
        logger.w('Unknown method: ${call.method}');
    }
  }

  /// 处理收到的数据包
  static void _onPacket(Map args) {
    try {
      final protocol = args['protocol'] as String? ?? 'TCP';
      final sourceIp = args['sourceIp'] as String? ?? '';
      final sourcePort = args['sourcePort'] as int? ?? 0;
      final destIp = args['destIp'] as String? ?? '';
      final destPort = args['destPort'] as int? ?? 0;
      final direction = args['direction'] as String? ?? 'outgoing';
      final timestamp = args['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;

      // 解析数据
      Uint8List data;
      final rawData = args['data'];
      if (rawData is List) {
        data = Uint8List.fromList(rawData.cast<int>());
      } else if (rawData is Uint8List) {
        data = rawData;
      } else {
        data = Uint8List(0);
      }

      final packet = RawPacket(
        id: '${timestamp}_${sourceIp}_${sourcePort}_${destIp}_${destPort}_${data.hashCode}',
        protocol: protocol == 'UDP' ? PacketProtocol.UDP : PacketProtocol.TCP,
        direction: direction == 'incoming' ? PacketDirection.incoming : PacketDirection.outgoing,
        sourceIp: sourceIp,
        sourcePort: sourcePort,
        destIp: destIp,
        destPort: destPort,
        data: data,
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
        sequenceNumber: args['sequenceNumber'] as int?,
        ackNumber: args['ackNumber'] as int?,
        isSyn: args['isSyn'] as bool?,
        isAck: args['isAck'] as bool?,
        isFin: args['isFin'] as bool?,
        isRst: args['isRst'] as bool?,
        isPsh: args['isPsh'] as bool?,
      );

      PacketCaptureManager.instance.handleRawPacket(packet);
    } catch (e, stack) {
      logger.e('Error processing packet', error: e, stackTrace: stack);
    }
  }

  /// 处理会话关闭
  static void _onSessionClosed(Map args) {
    try {
      final connectionKey = args['connectionKey'] as String?;
      if (connectionKey != null) {
        logger.d('Session closed: $connectionKey');
      }
    } catch (e) {
      logger.e('Error handling session close', error: e);
    }
  }

  /// 通知原生层启用/禁用数据包捕获
  static Future<void> setCaptureEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setCaptureEnabled', {'enabled': enabled});
    } catch (e) {
      logger.e('Error setting capture enabled', error: e);
    }
  }

  /// 设置捕获的数据大小限制
  static Future<void> setMaxPayloadSize(int maxSize) async {
    try {
      await _channel.invokeMethod('setMaxPayloadSize', {'maxSize': maxSize});
    } catch (e) {
      logger.e('Error setting max payload size', error: e);
    }
  }
}