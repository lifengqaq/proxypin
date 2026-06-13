/*
 * TCP/UDP 数据包管理器
 * 负责接收、存储和管理原始数据包事件
 */

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:proxypin/network/tcp_udp/raw_packet.dart';
import 'package:proxypin/network/util/logger.dart';

/// 数据包事件监听器
abstract class PacketListener {
  void onPacket(RawPacket packet);
  void onSessionCreated(PacketSession session);
  void onSessionClosed(PacketSession session);
}

/// TCP/UDP 数据包管理器
class PacketCaptureManager {
  static PacketCaptureManager? _instance;

  /// 数据包流控制器
  final StreamController<RawPacket> _packetController = StreamController.broadcast();

  /// 会话流控制器
  final StreamController<PacketSession> _sessionController = StreamController.broadcast();

  /// 所有数据包（按时间排序）
  final List<RawPacket> _packets = [];

  /// 活跃会话
  final Map<String, PacketSession> _sessions = {};

  /// 已关闭的会话
  final List<PacketSession> _closedSessions = [];

  /// 监听器列表
  final List<PacketListener> _listeners = [];

  /// 最大存储数据包数量
  int maxPackets = 5000;

  /// 最大存储会话数量
  int maxSessions = 200;

  /// 是否启用抓包
  bool _enabled = false;

  /// 端口过滤器（空=不过滤）
  final Set<int> _portFilter = {};

  /// 协议过滤器
  final Set<PacketProtocol> _protocolFilter = {PacketProtocol.TCP, PacketProtocol.UDP};

  PacketCaptureManager._();

  static PacketCaptureManager get instance => _instance ??= PacketCaptureManager._();

  /// 数据包流
  Stream<RawPacket> get packetStream => _packetController.stream;

  /// 会话流
  Stream<PacketSession> get sessionStream => _sessionController.stream;

  /// 所有数据包
  List<RawPacket> get packets => UnmodifiableListView(_packets);

  /// 活跃会话
  Map<String, PacketSession> get sessions => UnmodifiableMapView(_sessions);

  /// 已关闭的会话
  List<PacketSession> get closedSessions => UnmodifiableListView(_closedSessions);

  /// 是否启用
  bool get enabled => _enabled;

  /// 启用抓包
  void enable() {
    _enabled = true;
  }

  /// 禁用抓包
  void disable() {
    _enabled = false;
  }

  /// 设置端口过滤
  void setPortFilter(Set<int> ports) {
    _portFilter.clear();
    _portFilter.addAll(ports);
  }

  /// 设置协议过滤
  void setProtocolFilter(Set<PacketProtocol> protocols) {
    _protocolFilter.clear();
    _protocolFilter.addAll(protocols);
  }

  /// 添加监听器
  void addListener(PacketListener listener) {
    _listeners.add(listener);
  }

  /// 移除监听器
  void removeListener(PacketListener listener) {
    _listeners.remove(listener);
  }

  /// 处理来自 Android 原生层的原始数据包
  void handleRawPacket(RawPacket packet) {
    if (!_enabled) return;

    // 协议过滤
    if (!_protocolFilter.contains(packet.protocol)) return;

    // 端口过滤
    if (_portFilter.isNotEmpty) {
      if (!_portFilter.contains(packet.sourcePort) && !_portFilter.contains(packet.destPort)) {
        return;
      }
    }

    // 添加到列表
    _packets.add(packet);

    // 管理容量
    while (_packets.length > maxPackets) {
      _packets.removeAt(0);
    }

    // 关联到会话
    _updateSession(packet);

    // 通知监听器
    _packetController.add(packet);
    for (var listener in _listeners) {
      try {
        listener.onPacket(packet);
      } catch (e) {
        logger.e('PacketListener error', error: e);
      }
    }
  }

  /// 更新会话状态
  void _updateSession(RawPacket packet) {
    final key = packet.connectionKey;
    var session = _sessions[key];

    if (session == null) {
      // 创建新会话
      session = PacketSession(
        connectionKey: key,
        protocol: packet.protocol,
        clientIp: packet.direction == PacketDirection.outgoing ? packet.sourceIp : packet.destIp,
        clientPort: packet.direction == PacketDirection.outgoing ? packet.sourcePort : packet.destPort,
        serverIp: packet.direction == PacketDirection.outgoing ? packet.destIp : packet.sourceIp,
        serverPort: packet.direction == PacketDirection.outgoing ? packet.destPort : packet.sourcePort,
        startTime: packet.timestamp,
      );
      _sessions[key] = session;
      _sessionController.add(session);

      for (var listener in _listeners) {
        try {
          listener.onSessionCreated(session);
        } catch (e) {
          logger.e('PacketListener error', error: e);
        }
      }

      // 管理会话容量
      while (_sessions.length > maxSessions) {
        final oldest = _sessions.keys.first;
        _closeSession(oldest);
      }
    }

    session.addPacket(packet);

    // TCP FIN/RST 关闭会话
    if (packet.protocol == PacketProtocol.TCP) {
      if (packet.isFin == true || packet.isRst == true) {
        _closeSession(key);
      }
    }
  }

  /// 关闭会话
  void _closeSession(String key) {
    final session = _sessions.remove(key);
    if (session != null) {
      session.close();
      _closedSessions.add(session);

      // 管理容量
      while (_closedSessions.length > maxSessions) {
        _closedSessions.removeAt(0);
      }

      for (var listener in _listeners) {
        try {
          listener.onSessionClosed(session);
        } catch (e) {
          logger.e('PacketListener error', error: e);
        }
      }
    }
  }

  /// 清空所有数据
  void clear() {
    _packets.clear();
    _sessions.clear();
    _closedSessions.clear();
  }

  /// 搜索数据包
  List<RawPacket> search({
    String? keyword,
    PacketProtocol? protocol,
    PacketDirection? direction,
    int? port,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    return _packets.where((packet) {
      if (protocol != null && packet.protocol != protocol) return false;
      if (direction != null && packet.direction != direction) return false;
      if (port != null && packet.sourcePort != port && packet.destPort != port) return false;
      if (startTime != null && packet.timestamp.isBefore(startTime)) return false;
      if (endTime != null && packet.timestamp.isAfter(endTime)) return false;
      if (keyword != null && keyword.isNotEmpty) {
        final kw = keyword.toLowerCase();
        final hexContent = packet.hexDump.toLowerCase();
        final utf8 = packet.utf8Content?.toLowerCase() ?? '';
        final srcInfo = '${packet.sourceIp}:${packet.sourcePort}'.toLowerCase();
        final dstInfo = '${packet.destIp}:${packet.destPort}'.toLowerCase();
        if (!hexContent.contains(kw) && !utf8.contains(kw) &&
            !srcInfo.contains(kw) && !dstInfo.contains(kw)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  /// 导出数据为 JSON
  List<Map<String, dynamic>> exportPackets() {
    return _packets.map((p) => p.toJson()).toList();
  }

  /// 释放资源
  void dispose() {
    _packetController.close();
    _sessionController.close();
    _listeners.clear();
    clear();
    _instance = null;
  }
}