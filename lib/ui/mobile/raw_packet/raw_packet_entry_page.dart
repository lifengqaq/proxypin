import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/tcp_udp/packet_capture_manager.dart';
import 'package:proxypin/ui/mobile/raw_packet/raw_packet_list_page.dart';

/// TCP/UDP 原始数据包入口页面
class RawPacketEntryPage extends StatefulWidget {
  const RawPacketEntryPage({super.key});

  @override
  State<RawPacketEntryPage> createState() => _RawPacketEntryPageState();
}

class _RawPacketEntryPageState extends State<RawPacketEntryPage> {
  bool _captureEnabled = true;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final manager = PacketCaptureManager.instance;
    final packetCount = manager.packets.length;
    final sessionCount = manager.sessions.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TCP/UDP Packet Capture'),
        actions: [
          IconButton(
            icon: Icon(_captureEnabled ? Icons.pause : Icons.play_arrow),
            tooltip: _captureEnabled ? 'Pause Capture' : 'Resume Capture',
            onPressed: () {
              setState(() {
                _captureEnabled = !_captureEnabled;
                if (_captureEnabled) {
                  manager.enable();
                } else {
                  manager.disable();
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear All',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear All Data'),
                  content: const Text('Are you sure you want to clear all captured packets?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        manager.clear();
                        Navigator.pop(context);
                        setState(() {});
                      },
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 统计信息卡片
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    'Packets',
                    packetCount.toString(),
                    Icons.data_usage,
                    Colors.blue,
                  ),
                  _buildStatItem(
                    'Active Sessions',
                    sessionCount.toString(),
                    Icons.link,
                    Colors.green,
                  ),
                  _buildStatItem(
                    'Status',
                    _captureEnabled ? 'Active' : 'Paused',
                    _captureEnabled ? Icons.play_circle : Icons.pause_circle,
                    _captureEnabled ? Colors.green : Colors.orange,
                  ),
                ],
              ),
            ),
          ),

          // 查看数据包按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.list),
                label: const Text('View Packet List'),
                style: ElevatedButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 16),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RawPacketListPage(),
                    ),
                  ).then((_) => setState(() {}));
                },
              ),
            ),
          ),

          // 说明文本
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'About TCP/UDP Packet Capture',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildInfoItem(
                      '• This feature captures raw TCP and UDP packets at the VPN layer',
                    ),
                    _buildInfoItem(
                      '• HTTP/HTTPS traffic is captured separately in the main request list',
                    ),
                    _buildInfoItem(
                      '• Use filters to narrow down packets by protocol, direction, or port',
                    ),
                    _buildInfoItem(
                      '• Packet payload is limited to 4KB per packet for performance',
                    ),
                    _buildInfoItem(
                      '• Data is stored in memory and cleared when the app restarts',
                    ),
                  ],
                ),
              ),
            ),
          ),

          const Spacer(),

          // 底部提示
          if (packetCount > 0)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Capturing packets...',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14),
      ),
    );
  }
}
