import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/network/tcp_udp/raw_packet.dart';

/// TCP/UDP 数据包详情页面
class RawPacketDetailPage extends StatelessWidget {
  final RawPacket packet;

  const RawPacketDetailPage({super.key, required this.packet});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTcp = packet.protocol == PacketProtocol.TCP;
    final isOutgoing = packet.direction == PacketDirection.outgoing;

    return Scaffold(
      appBar: AppBar(
        title: Text('${packet.protocol.name} Packet Detail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制全部',
            onPressed: () => _copyAll(context),
          ),
        ],
      ),
      body: ListView(
        children: [
          // 基本信息卡片
          _buildInfoCard(theme),
          
          // TCP 特有信息
          if (isTcp) _buildTcpInfoCard(theme),
          
          // 数据内容
          _buildDataCard(theme, context),
          
          // Hex Dump
          _buildHexDumpCard(theme, context),
        ],
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme) {
    final isOutgoing = packet.direction == PacketDirection.outgoing;
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Basic Info',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoRow('Protocol', packet.protocol.name),
            _buildInfoRow('Direction', isOutgoing ? 'Outgoing ↑' : 'Incoming ↓'),
            _buildInfoRow('Time', _formatFullTime(packet.timestamp)),
            _buildInfoRow('Size', '${packet.size} bytes'),
            const Divider(height: 24),
            _buildInfoRow('Source', '${packet.sourceIp}:${packet.sourcePort}'),
            _buildInfoRow('Destination', '${packet.destIp}:${packet.destPort}'),
          ],
        ),
      ),
    );
  }

  Widget _buildTcpInfoCard(ThemeData theme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TCP Header',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (packet.tcpFlags != null)
              _buildInfoRow('Flags', packet.tcpFlags!),
            if (packet.sequenceNumber != null)
              _buildInfoRow('Seq Number', '${packet.sequenceNumber}'),
            if (packet.ackNumber != null)
              _buildInfoRow('Ack Number', '${packet.ackNumber}'),
            const SizedBox(height: 8),
            // TCP 标志位可视化
            _buildTcpFlagsVisualization(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildTcpFlagsVisualization(ThemeData theme) {
    final flags = [
      ('SYN', packet.isSyn ?? false),
      ('ACK', packet.isAck ?? false),
      ('FIN', packet.isFin ?? false),
      ('RST', packet.isRst ?? false),
      ('PSH', packet.isPsh ?? false),
    ];

    return Wrap(
      spacing: 8,
      children: flags.map((flag) {
        final (name, active) = flag;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: active ? Colors.blue.shade100 : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: active ? Colors.blue : Colors.grey,
              width: 1,
            ),
          ),
          child: Text(
            name,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: active ? Colors.blue.shade700 : Colors.grey.shade600,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDataCard(ThemeData theme, BuildContext context) {
    final utf8Content = packet.utf8Content;
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Payload Data',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (utf8Content != null)
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: '复制文本',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: utf8Content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制')),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (packet.data.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No payload data',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else if (utf8Content != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  utf8Content,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              )
            else
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Binary data (see Hex Dump below)',
                    style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHexDumpCard(ThemeData theme, BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Hex Dump',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: '复制Hex',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: packet.hexDump));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                packet.hexDump,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Colors.greenAccent,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  String _formatFullTime(DateTime time) {
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}.${time.millisecond.toString().padLeft(3, '0')}';
  }

  void _copyAll(BuildContext context) {
    final buffer = StringBuffer();
    buffer.writeln('=== ${packet.protocol.name} Packet ===');
    buffer.writeln('Direction: ${packet.direction == PacketDirection.outgoing ? "Outgoing" : "Incoming"}');
    buffer.writeln('Time: ${_formatFullTime(packet.timestamp)}');
    buffer.writeln('Size: ${packet.size} bytes');
    buffer.writeln('Source: ${packet.sourceIp}:${packet.sourcePort}');
    buffer.writeln('Destination: ${packet.destIp}:${packet.destPort}');
    
    if (packet.protocol == PacketProtocol.TCP) {
      buffer.writeln('\n=== TCP Header ===');
      if (packet.tcpFlags != null) {
        buffer.writeln('Flags: ${packet.tcpFlags}');
      }
      if (packet.sequenceNumber != null) {
        buffer.writeln('Seq: ${packet.sequenceNumber}');
      }
      if (packet.ackNumber != null) {
        buffer.writeln('Ack: ${packet.ackNumber}');
      }
    }
    
    buffer.writeln('\n=== Hex Dump ===');
    buffer.writeln(packet.hexDump);
    
    final utf8 = packet.utf8Content;
    if (utf8 != null) {
      buffer.writeln('\n=== Payload (Text) ===');
      buffer.writeln(utf8);
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制全部信息')),
    );
  }
}