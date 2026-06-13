import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:proxypin/network/tcp_udp/packet_capture_manager.dart';
import 'package:proxypin/network/tcp_udp/raw_packet.dart';
import 'package:proxypin/ui/mobile/raw_packet/raw_packet_detail_page.dart';

/// TCP/UDP 数据包序列列表（嵌入请求列表 Tab）
class RawPacketSequence extends StatefulWidget {
  const RawPacketSequence({super.key});

  @override
  State<RawPacketSequence> createState() => RawPacketSequenceState();
}

class RawPacketSequenceState extends State<RawPacketSequence> with AutomaticKeepAliveClientMixin {
  final PacketCaptureManager _manager = PacketCaptureManager.instance;
  final ScrollController _scrollController = ScrollController();

  StreamSubscription? _packetSubscription;
  final Queue<RawPacket> _packets = Queue();
  bool _autoScroll = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _packets.addAll(_manager.packets);
    _packetSubscription = _manager.packetStream.listen((packet) {
      setState(() => _packets.addLast(packet));
      if (_autoScroll && _scrollController.hasClients) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients && _autoScroll) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _packetSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void scrollToTop() {
    _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.ease);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    if (_packets.isEmpty) {
      return Center(
        child: Text('暂无数据包', style: TextStyle(color: theme.disabledColor)),
      );
    }

    return Column(
      children: [
        // 工具栏
        _buildToolbar(theme),
        const Divider(height: 1),
        // 列表
        Expanded(
          child: Scrollbar(
            controller: _scrollController,
            child: ListView.separated(
              controller: _scrollController,
              cacheExtent: 1000,
              itemCount: _packets.length,
              separatorBuilder: (_, __) => Divider(
                thickness: 0.2,
                height: 0,
                color: theme.dividerColor,
              ),
              itemBuilder: (context, index) {
                return _PacketRow(
                  packet: _packets.elementAt(index),
                  onTap: () => _showDetail(_packets.elementAt(index)),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(ThemeData theme) {
    final tcpCount = _packets.where((p) => p.protocol == PacketProtocol.TCP).length;
    final udpCount = _packets.where((p) => p.protocol == PacketProtocol.UDP).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Text(
            'TCP: $tcpCount  UDP: $udpCount',
            style: TextStyle(fontSize: 12, color: theme.disabledColor),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_bottom_outlined,
              size: 20,
            ),
            tooltip: '自动滚动',
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: '清空',
            onPressed: () {
              _manager.clear();
              setState(() => _packets.clear());
            },
          ),
        ],
      ),
    );
  }

  void _showDetail(RawPacket packet) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RawPacketDetailPage(packet: packet)),
    );
  }
}

/// 数据包列表行（复用原项目 ListTile 风格）
class _PacketRow extends StatelessWidget {
  final RawPacket packet;
  final VoidCallback onTap;

  const _PacketRow({required this.packet, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isTcp = packet.protocol == PacketProtocol.TCP;
    final isOutgoing = packet.direction == PacketDirection.outgoing;

    return ListTile(
      visualDensity: const VisualDensity(vertical: -4),
      minLeadingWidth: 5,
      leading: Container(
        width: 40,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isTcp ? Colors.blue.shade50 : Colors.green.shade50,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isTcp ? Colors.blue.shade200 : Colors.green.shade200,
            width: 0.5,
          ),
        ),
        child: Text(
          isTcp ? 'TCP' : 'UDP',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isTcp ? Colors.blue.shade700 : Colors.green.shade700,
          ),
        ),
      ),
      title: Row(
        children: [
          Icon(
            isOutgoing ? Icons.arrow_upward : Icons.arrow_downward,
            size: 14,
            color: isOutgoing ? Colors.orange : Colors.purple,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '${packet.sourceIp}:${packet.sourcePort} → ${packet.destIp}:${packet.destPort}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: _formatTime(packet.timestamp),
              style: TextStyle(fontSize: 11, color: Colors.teal.shade400),
            ),
            TextSpan(
              text: '  ${_formatSize(packet.size)}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
      contentPadding: const EdgeInsets.only(left: 8, right: 5),
      onTap: onTap,
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}.${time.millisecond.toString().padLeft(3, '0')}';
  }
}
