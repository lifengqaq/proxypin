/*
 * Copyright 2023 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/tcp_udp/packet_capture_manager.dart';
import 'package:proxypin/network/tcp_udp/raw_packet.dart';
import 'package:proxypin/ui/component/multi_select_controller.dart';
import 'package:proxypin/ui/mobile/raw_packet/raw_packet_detail_page.dart';
import 'package:proxypin/ui/mobile/request/domians.dart';
import 'package:proxypin/ui/mobile/request/request.dart';
import 'package:proxypin/ui/mobile/request/request_sequence.dart';
import 'package:proxypin/utils/har.dart';
import 'package:proxypin/utils/listenable_list.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:share_plus/share_plus.dart';

import '../../component/model/search_model.dart';

/// Tab 切换通知
final ValueNotifier<int> tabNotifier = ValueNotifier(-1);

/// 请求列表
class RequestListWidget extends StatefulWidget {
  final ProxyServer proxyServer;
  final ListenableList<HttpRequest>? list;
  final MultiSelectController selectionController;

  const RequestListWidget({super.key, required this.proxyServer, this.list, required this.selectionController});

  @override
  State<StatefulWidget> createState() => RequestListState();
}

class RequestListState extends State<RequestListWidget> with SingleTickerProviderStateMixin {
  final GlobalKey<RequestSequenceState> requestSequenceKey = GlobalKey<RequestSequenceState>();
  final GlobalKey<DomainListState> domainListKey = GlobalKey<DomainListState>();

  ListenableList<HttpRequest> container = ListenableList();
  late final TabController _tabController;
  StreamSubscription? _packetSub;
  VoidCallback? _tabListener;

  final List<RawPacket> _tcpPackets = [];

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    if (widget.list != null) {
      container = widget.list!;
    }
    _packetSub = PacketCaptureManager.instance.packetStream.listen((packet) {
      requestSequenceKey.currentState?.addPacket(packet);
      setState(() => _tcpPackets.insert(0, packet));
    });

    _tabListener = () {
      final target = tabNotifier.value;
      if (target >= 0 && target < 3) {
        _tabController.animateTo(target);
        tabNotifier.value = -1;
      }
    };
    tabNotifier.addListener(_tabListener!);
  }

  @override
  void dispose() {
    _packetSub?.cancel();
    if (_tabListener != null) tabNotifier.removeListener(_tabListener!);
    _tabController.dispose();
    RequestRowState.removeAutoReadByIds(container.map((r) => r.requestId));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> tabs = [
      Tab(child: Text(localizations.sequence)),
      Tab(child: Text(localizations.domainList)),
      const Tab(child: Text('TCP/UDP')),
    ];

    var tabClickHandles = [
      DoubleClickHandle(handle: () => requestSequenceKey.currentState?.scrollToTop()),
      DoubleClickHandle(handle: () => domainListKey.currentState?.scrollToTop()),
      DoubleClickHandle(handle: () {}),
    ];

    return Scaffold(
      appBar: AppBar(
          title: TabBar(controller: _tabController, tabs: tabs,
              onTap: (index) => tabClickHandles[index].call()),
          automaticallyImplyLeading: false),
      body: TabBarView(
        controller: _tabController,
        children: [
          RequestSequence(
              key: requestSequenceKey, container: container,
              proxyServer: widget.proxyServer, onRemove: sequenceRemove,
              selectionController: widget.selectionController),
          DomainList(key: domainListKey, list: container,
              proxyServer: widget.proxyServer, onRemove: domainListRemove),
          _buildTcpTab(),
        ],
      ),
    );
  }

  Widget _buildTcpTab() {
    if (_tcpPackets.isEmpty) {
      return const Center(child: Text('暂无数据包', style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      itemCount: _tcpPackets.length,
      separatorBuilder: (_, __) => const Divider(height: 0.5),
      itemBuilder: (context, index) {
        final p = _tcpPackets[index];
        final isTcp = p.protocol == PacketProtocol.TCP;
        final isOut = p.direction == PacketDirection.outgoing;
        return ListTile(
          visualDensity: const VisualDensity(vertical: -4),
          leading: Container(
            width: 40, height: 24, alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isTcp ? Colors.blue.shade50 : Colors.green.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: isTcp ? Colors.blue.shade200 : Colors.green.shade200, width: 0.5),
            ),
            child: Text(isTcp ? 'TCP' : 'UDP',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                    color: isTcp ? Colors.blue.shade700 : Colors.green.shade700)),
          ),
          title: Text('${p.sourceIp}:${p.sourcePort} → ${p.destIp}:${p.destPort}',
              overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
          subtitle: Text(
            '${p.timestamp.hour.toString().padLeft(2, '0')}:${p.timestamp.minute.toString().padLeft(2, '0')}:${p.timestamp.second.toString().padLeft(2, '0')}  ${p.size}B',
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
          trailing: Icon(isOut ? Icons.arrow_upward : Icons.arrow_downward, size: 16,
              color: isOut ? Colors.orange : Colors.purple),
          contentPadding: const EdgeInsets.only(left: 8, right: 5),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => RawPacketDetailPage(packet: p))),
        );
      },
    );
  }

  void add(Channel channel, HttpRequest request) {
    container.add(request);
    requestSequenceKey.currentState?.add(request);
    domainListKey.currentState?.add(request);
  }

  void addResponse(ChannelContext channelContext, HttpResponse response) {
    requestSequenceKey.currentState?.addResponse(response);
    domainListKey.currentState?.addResponse(response);
  }

  void domainListRemove(List<HttpRequest> list) {
    container.removeWhere((e) => list.contains(e));
    requestSequenceKey.currentState?.remove(list);
    RequestRowState.removeAutoReadByIds(list.map((r) => r.requestId));
  }

  void sequenceRemove(List<HttpRequest> list) {
    container.removeWhere((e) => list.contains(e));
    domainListKey.currentState?.remove(list);
    RequestRowState.removeAutoReadByIds(list.map((r) => r.requestId));
  }

  void search(SearchModel searchModel) {
    requestSequenceKey.currentState?.search(searchModel);
    domainListKey.currentState?.search(searchModel.keyword?.trim());
  }

  Iterable<HttpRequest>? currentView() {
    return requestSequenceKey.currentState?.currentView();
  }

  void clean() {
    setState(() {
      RequestRowState.removeAutoReadByIds(container.map((r) => r.requestId));
      container.clear();
      domainListKey.currentState?.clean();
      requestSequenceKey.currentState?.clean();
      _tcpPackets.clear();
    });
  }

  void cleanupEarlyData(int retain) {
    var list = container.source;
    if (list.length <= retain) return;
    var removeRange = container.removeRange(0, list.length - retain);
    domainListKey.currentState?.clean();
    requestSequenceKey.currentState?.clean();
    RequestRowState.removeAutoReadByIds(removeRange.map((r) => r.requestId));
  }

  Future<void> export(BuildContext context, String title) async {
    String fileName = '${title.contains("ProxyPin") ? '' : 'ProxyPin'}$title.har'
        .replaceAll(" ", "_").replaceAll(":", "_");
    var view = currentView()!;
    var json = await Har.writeJson(view.toList(), title: title);
    var file = XFile.fromData(utf8.encode(json), name: fileName, mimeType: "har");
    RenderBox? box;
    if (await Platforms.isIpad() && context.mounted) {
      box = context.findRenderObject() as RenderBox?;
    }
    SharePlus.instance.share(ShareParams(
        files: [file], fileNameOverrides: [fileName],
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size));
  }

  void sort(bool sortDesc) {
    requestSequenceKey.currentState?.sort(sortDesc);
    domainListKey.currentState?.sort(sortDesc);
  }
}

class DoubleClickHandle {
  int tabClickTime = 0;
  final Function()? handle;
  DoubleClickHandle({this.handle});

  void call() {
    if (handle == null) return;
    if (DateTime.now().millisecondsSinceEpoch - tabClickTime < 500) {
      handle?.call();
    }
    tabClickTime = DateTime.now().millisecondsSinceEpoch;
  }
}
