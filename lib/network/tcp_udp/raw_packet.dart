/*
 * Copyright 2024 ProxyPin
 * TCP/UDP 原始数据包模型
 */

import 'dart:typed_data';

/// 协议类型
enum PacketProtocol {
  TCP,
  UDP,
}

/// 数据包方向
enum PacketDirection {
  outgoing, // 从设备发出
  incoming, // 从服务器返回
}

/// TCP/UDP 原始数据包
class RawPacket {
  final String id;
  final PacketProtocol protocol;
  final PacketDirection direction;
  final String sourceIp;
  final int sourcePort;
  final String destIp;
  final int destPort;
  final Uint8List data;
  final DateTime timestamp;
  
  // TCP 特有字段
  final int? sequenceNumber;
  final int? ackNumber;
  final bool? isSyn;
  final bool? isAck;
  final bool? isFin;
  final bool? isRst;
  final bool? isPsh;

  RawPacket({
    required this.id,
    required this.protocol,
    required this.direction,
    required this.sourceIp,
    required this.sourcePort,
    required this.destIp,
    required this.destPort,
    required this.data,
    required this.timestamp,
    this.sequenceNumber,
    this.ackNumber,
    this.isSyn,
    this.isAck,
    this.isFin,
    this.isRst,
    this.isPsh,
  });

  /// 数据包大小（字节）
  int get size => data.length;

  /// 连接标识符（用于分组同一连接的数据包）
  String get connectionKey {
    final sorted = [
      '$sourceIp:$sourcePort',
      '$destIp:$destPort',
    ]..sort();
    return '${protocol.name}:${sorted.join('-')}';
  }

  /// 数据内容的十六进制表示
  String get hexDump {
    final buffer = StringBuffer();
    for (int i = 0; i < data.length; i++) {
      buffer.write(data[i].toRadixString(16).padLeft(2, '0').toUpperCase());
      if (i < data.length - 1) {
        buffer.write(' ');
        if ((i + 1) % 16 == 0) buffer.write('\n');
      }
    }
    return buffer.toString();
  }

  /// 尝试将数据解析为 UTF-8 字符串
  String? get utf8Content {
    try {
      final str = String.fromCharCodes(data);
      // 检查是否包含不可打印字符
      if (str.codeUnits.every((c) => c >= 32 && c < 127 || c == 10 || c == 13 || c == 9)) {
        return str;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// TCP 标志位描述
  String? get tcpFlags {
    if (protocol != PacketProtocol.TCP) return null;
    final flags = <String>[];
    if (isSyn == true) flags.add('SYN');
    if (isAck == true) flags.add('ACK');
    if (isFin == true) flags.add('FIN');
    if (isRst == true) flags.add('RST');
    if (isPsh == true) flags.add('PSH');
    return flags.isEmpty ? null : flags.join('|');
  }

  /// 从 JSON 创建
  factory RawPacket.fromJson(Map<String, dynamic> json) {
    return RawPacket(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      protocol: PacketProtocol.values.firstWhere(
        (p) => p.name == json['protocol'],
        orElse: () => PacketProtocol.TCP,
      ),
      direction: PacketDirection.values.firstWhere(
        (d) => d.name == json['direction'],
        orElse: () => PacketDirection.outgoing,
      ),
      sourceIp: json['sourceIp'] ?? '',
      sourcePort: json['sourcePort'] ?? 0,
      destIp: json['destIp'] ?? '',
      destPort: json['destPort'] ?? 0,
      data: json['data'] != null 
          ? Uint8List.fromList(List<int>.from(json['data']))
          : Uint8List(0),
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'])
          : DateTime.now(),
      sequenceNumber: json['sequenceNumber'],
      ackNumber: json['ackNumber'],
      isSyn: json['isSyn'],
      isAck: json['isAck'],
      isFin: json['isFin'],
      isRst: json['isRst'],
      isPsh: json['isPsh'],
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'protocol': protocol.name,
      'direction': direction.name,
      'sourceIp': sourceIp,
      'sourcePort': sourcePort,
      'destIp': destIp,
      'destPort': destPort,
      'data': data.toList(),
      'timestamp': timestamp.millisecondsSinceEpoch,
      'sequenceNumber': sequenceNumber,
      'ackNumber': ackNumber,
      'isSyn': isSyn,
      'isAck': isAck,
      'isFin': isFin,
      'isRst': isRst,
      'isPsh': isPsh,
    };
  }

  @override
  String toString() {
    final dir = direction == PacketDirection.outgoing ? '→' : '←';
    return '${protocol.name} $dir $sourceIp:$sourcePort → $destIp:$destPort ($size bytes)';
  }
}

/// TCP/UDP 连接会话
class PacketSession {
  final String connectionKey;
  final PacketProtocol protocol;
  final String clientIp;
  final int clientPort;
  final String serverIp;
  final int serverPort;
  final DateTime startTime;
  DateTime? endTime;
  
  final List<RawPacket> packets = [];
  
  PacketSession({
    required this.connectionKey,
    required this.protocol,
    required this.clientIp,
    required this.clientPort,
    required this.serverIp,
    required this.serverPort,
    required this.startTime,
    this.endTime,
  });

  /// 是否活跃
  bool get isActive => endTime == null;

  /// 持续时间
  Duration get duration => (endTime ?? DateTime.now()).difference(startTime);

  /// 总字节数
  int get totalBytes => packets.fold(0, (sum, p) => sum + p.size);

  /// 发送字节数
  int get sentBytes => packets
      .where((p) => p.direction == PacketDirection.outgoing)
      .fold(0, (sum, p) => sum + p.size);

  /// 接收字节数
  int get receivedBytes => packets
      .where((p) => p.direction == PacketDirection.incoming)
      .fold(0, (sum, p) => sum + p.size);

  /// 添加数据包
  void addPacket(RawPacket packet) {
    packets.add(packet);
  }

  /// 关闭会话
  void close() {
    endTime = DateTime.now();
  }

  @override
  String toString() {
    return '${protocol.name} $clientIp:$clientPort → $serverIp:$serverPort (${packets.length} packets)';
  }
}
