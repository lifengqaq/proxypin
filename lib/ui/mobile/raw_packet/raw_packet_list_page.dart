import 'dart:async';
import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/tcp_udp/packet_capture_manager.dart';
import 'package:proxypin/network/tcp_udp/raw_packet.dart';
import 'package:proxypin/ui/mobile/raw_packet/raw_packet_detail_page.dart';

/// TCP/UDP 数据包列表页面
class RawPacketListPage extends StatefulWidget {
  const RawPacketListPage({super.key});

  @override
  State<RawPacketListPage> createState() => _RawPacketListPageState();
}

class _RawPacketListPageState extends State<RawPacketListPage> with AutomaticKeepAliveClientMixin {
  final PacketCaptureManager _manager = PacketCaptureManager.instance;
  final ScrollController _scrollController = ScrollController();
  
  StreamSubscription? _packetSubscription;
  List<RawPacket> _packets = [];
  bool _autoScroll = true;
  
  // 过滤器
  PacketProtocol? _protocolFilter;
  PacketDirection? _directionFilter;
  String? _portFilter;
  
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _packets = _manager.packets.toList();
    _packetSubscription = _manager.packetStream.listen((packet) {
      setState(() {
        _packets = _getFilteredPackets();
      });
      if (_autoScroll && _scrollController.hasClients) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
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

  List<RawPacket> _getFilteredPackets() {
    return _manager.search(
      protocol: _protocolFilter,
      direction: _directionFilter,
      port: _portFilter != null ? int.tryParse(_portFilter!) : null,
    );
  }

  void _clearFilters() {
    setState(() {
      _protocolFilter = null;
      _directionFilter = null;
      _portFilter = null;
      _packets = _manager.packets.toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final localizations = AppLocalizations.of(context)!;
    
    return Column(
      children: [
        // 工具栏
        _buildToolbar(localizations),
        const Divider(height: 1),
        // 数据包列表
        Expanded(
          child: _packets.isEmpty
              ? Center(
                  child: Text(
                    localizations.noData,
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  itemCount: _packets.length,
                  itemBuilder: (context, index) {
                    return _PacketListTile(
                      packet: _packets[index],
                      onTap: () => _showPacketDetail(_packets[index]),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildToolbar(AppLocalizations localizations) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // 协议过滤
          _FilterChip(
            label: _protocolFilter?.name ?? 'TCP/UDP',
            selected: _protocolFilter != null,
            onTap: () => _showProtocolFilter(localizations),
          ),
          const SizedBox(width: 8),
          // 方向过滤
          _FilterChip(
            label: _directionFilter == null
                ? 'ALL'
                : _directionFilter == PacketDirection.outgoing
                    ? '↑ OUT'
                    : '↓ IN',
            selected: _directionFilter != null,
            onTap: () => _showDirectionFilter(localizations),
          ),
          const SizedBox(width: 8),
          // 端口过滤
          _FilterChip(
            label: _portFilter ?? 'Port',
            selected: _portFilter != null,
            onTap: () => _showPortFilter(localizations),
          ),
          const Spacer(),
          // 自动滚动
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_bottom_outlined,
              size: 20,
            ),
            tooltip: 'Auto Scroll',
            onPressed: () {
              setState(() {
                _autoScroll = !_autoScroll;
              });
              if (_autoScroll && _scrollController.hasClients) {
                _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
              }
            },
          ),
          // 清空过滤
          if (_protocolFilter != null || _directionFilter != null || _portFilter != null)
            IconButton(
              icon: const Icon(Icons.clear_all, size: 20),
              tooltip: 'Clear Filters',
              onPressed: _clearFilters,
            ),
          // 清空所有
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Clear All',
            onPressed: () {
              setState(() {
                _manager.clear();
                _packets = [];
              });
            },
          ),
        ],
      ),
    );
  }

  void _showProtocolFilter(AppLocalizations localizations) {
    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Protocol Filter'),
          children: [
            SimpleDialogOption(
              onPressed: () {
                setState(() => _protocolFilter = null);
                _packets = _getFilteredPackets();
                Navigator.pop(context);
              },
              child: Row(
                children: [
                  Radio<PacketProtocol?>(
                    value: null,
                    groupValue: _protocolFilter,
                    onChanged: (_) {},
                  ),
                  const Text('All'),
                ],
              ),
            ),
            SimpleDialogOption(
              onPressed: () {
                setState(() => _protocolFilter = PacketProtocol.TCP);
                _packets = _getFilteredPackets();
                Navigator.pop(context);
              },
              child: Row(
                children: [
                  Radio<PacketProtocol?>(
                    value: PacketProtocol.TCP,
                    groupValue: _protocolFilter,
                    onChanged: (_) {},
                  ),
                  const Text('TCP'),
                ],
              ),
            ),
            SimpleDialogOption(
              onPressed: () {
                setState(() => _protocolFilter = PacketProtocol.UDP);
                _packets = _getFilteredPackets();
                Navigator.pop(context);
              },
              child: Row(
                children: [
                  Radio<PacketProtocol?>(
                    value: PacketProtocol.UDP,
                    groupValue: _protocolFilter,
                    onChanged: (_) {},
                  ),
                  const Text('UDP'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _showDirectionFilter(AppLocalizations localizations) {
    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Direction Filter'),
          children: [
            SimpleDialogOption(
              onPressed: () {
                setState(() => _directionFilter = null);
                _packets = _getFilteredPackets();
                Navigator.pop(context);
              },
              child: Row(
                children: [
                  Radio<PacketDirection?>(
                    value: null,
                    groupValue: _directionFilter,
                    onChanged: (_) {},
                  ),
                  const Text('All'),
                ],
              ),
            ),
            SimpleDialogOption(
              onPressed: () {
                setState(() => _directionFilter = PacketDirection.outgoing);
                _packets = _getFilteredPackets();
                Navigator.pop(context);
              },
              child: Row(
                children: [
                  Radio<PacketDirection?>(
                    value: PacketDirection.outgoing,
                    groupValue: _directionFilter,
                    onChanged: (_) {},
                  ),
                  const Text('Outgoing ↑'),
                ],
              ),
            ),
            SimpleDialogOption(
              onPressed: () {
                setState(() => _directionFilter = PacketDirection.incoming);
                _packets = _getFilteredPackets();
                Navigator.pop(context);
              },
              child: Row(
                children: [
                  Radio<PacketDirection?>(
                    value: PacketDirection.incoming,
                    groupValue: _directionFilter,
                    onChanged: (_) {},
                  ),
                  const Text('Incoming ↓'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _showPortFilter(AppLocalizations localizations) {
    final controller = TextEditingController(text: _portFilter);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Port Filter'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'Enter port number',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => _portFilter = null);
                _packets = _getFilteredPackets();
                Navigator.pop(context);
              },
              child: const Text('Clear'),
            ),
            TextButton(
              onPressed: () {
                setState(() => _portFilter = controller.text.trim());
                _packets = _getFilteredPackets();
                Navigator.pop(context);
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
  }

  void _showPacketDetail(RawPacket packet) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RawPacketDetailPage(packet: packet),
      ),
    );
  }
}

/// 过滤芯片
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? theme.colorScheme.onPrimaryContainer : null,
          ),
        ),
      ),
    );
  }
}

/// 数据包列表项
class _PacketListTile extends StatelessWidget {
  final RawPacket packet;
  final VoidCallback onTap;

  const _PacketListTile({
    required this.packet,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOutgoing = packet.direction == PacketDirection.outgoing;
    final isTcp = packet.protocol == PacketProtocol.TCP;
    
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: theme.dividerColor,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // 协议标识
            Container(
              width: 40,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isTcp ? Colors.blue.shade100 : Colors.green.shade100,
                borderRadius: BorderRadius.circular(4),
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
            const SizedBox(width: 8),
            // 方向箭头
            Icon(
              isOutgoing ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16,
              color: isOutgoing ? Colors.orange : Colors.purple,
            ),
            const SizedBox(width: 8),
            // 地址信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${packet.sourceIp}:${packet.sourcePort}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.arrow_forward, size: 12, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        '${packet.destIp}:${packet.destPort}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 数据包大小
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatSize(packet.size),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                Text(
                  _formatTime(packet.timestamp),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
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