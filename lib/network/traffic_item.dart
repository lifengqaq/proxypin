import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/tcp_udp/raw_packet.dart';

/// 统一流量条目，可同时包含 HTTP 请求和 TCP/UDP 数据包
sealed class TrafficItem {
  String get id;
  DateTime get timestamp;
}

class HttpTraffic extends TrafficItem {
  final HttpRequest request;
  HttpTraffic(this.request);

  @override
  String get id => request.requestId;

  @override
  DateTime get timestamp => request.requestTime;
}

class PacketTraffic extends TrafficItem {
  final RawPacket packet;
  PacketTraffic(this.packet);

  @override
  String get id => packet.id;

  @override
  DateTime get timestamp => packet.timestamp;
}
