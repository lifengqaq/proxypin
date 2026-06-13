import 'dart:collection';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:get/get.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/network/tcp_udp/raw_packet.dart';
import 'package:proxypin/network/traffic_item.dart';
import 'package:proxypin/ui/component/multi_select_controller.dart';
import 'package:proxypin/ui/component/selection_action_bar.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/desktop/request/request.dart';
import 'package:proxypin/ui/mobile/raw_packet/raw_packet_detail_page.dart';
import 'package:proxypin/ui/mobile/request/request.dart';
import 'package:proxypin/utils/har.dart';
import 'package:proxypin/utils/keyword_highlight.dart';
import 'package:proxypin/utils/listenable_list.dart';

import '../../../network/channel/host_port.dart' show ProxyInfo;
import '../../../utils/lang.dart';
import '../../component/model/search_model.dart';

///请求序列 列表
///@author wanghongen
class RequestSequence extends StatefulWidget {
  final ListenableList<HttpRequest> container;
  final ProxyServer proxyServer;
  final bool displayDomain;
  final bool? sortDesc;
  final Function(List<HttpRequest>)? onRemove;
  final MultiSelectController selectionController;

  const RequestSequence(
      {super.key,
      required this.container,
      required this.proxyServer,
      this.displayDomain = true,
      this.onRemove,
      this.sortDesc,
      required this.selectionController});

  @override
  State<StatefulWidget> createState() {
    return RequestSequenceState();
  }
}

class RequestSequenceState extends State<RequestSequence> with AutomaticKeepAliveClientMixin {
  ///请求id和对应的row的映射
  Map<String, GlobalKey<RequestRowState>> indexes = HashMap();
  late final MultiSelectListener<String> selectionListener;

  ///显示的请求/数据包列表 最新的在前面
  Queue<TrafficItem> view = Queue();
  bool changing = false;

  bool sortDesc = true;

  //搜索的内容
  SearchModel? searchModel;

  //关键词高亮监听
  late VoidCallback highlightListener;

  MultiSelectController get selectionController => widget.selectionController;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    sortDesc = widget.sortDesc ?? true;
    view.addAll(widget.container.source.reversed.map((r) => HttpTraffic(r)));
    selectionListener = MultiSelectListener((items) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });

    widget.selectionController.selectedIds.addListener(selectionListener);
    highlightListener = () {
      //回调时机在高亮设置页面dispose之后。所以需要在下一帧刷新，否则会报错
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        setState(() {});
      });
    };
    KeywordHighlights.addListener(highlightListener);
  }

  @override
  void dispose() {
    widget.selectionController.selectedIds.removeListener(selectionListener);
    KeywordHighlights.removeListener(highlightListener);
    super.dispose();
  }

  ///添加请求
  void add(HttpRequest request) {
    ///过滤
    if (searchModel?.isNotEmpty == true && !searchModel!.filter(request, request.response)) {
      return;
    }

    final item = HttpTraffic(request);
    if (sortDesc) {
      view.addFirst(item);
    } else {
      view.addLast(item);
    }

    changeState();
  }

  ///添加 TCP/UDP 数据包
  void addPacket(RawPacket packet) {
    if (sortDesc) {
      view.addFirst(PacketTraffic(packet));
    } else {
      view.addLast(PacketTraffic(packet));
    }
    changeState();
  }

  ///添加响应
  void addResponse(HttpResponse response) {
    var state = indexes.remove(response.request?.requestId);
    state?.currentState?.change(response);

    if (searchModel == null || searchModel!.isEmpty || response.request == null) {
      return;
    }

    final request = response.request!;
    //搜索视图
    if (searchModel?.filter(request, response) == true && state == null) {
      if (!view.any((item) => item is HttpTraffic && item.request == request)) {
        view.addFirst(HttpTraffic(request));
        changeState();
      }
    }
  }

  void clean() {
    widget.selectionController.clear();
    setState(() {
      view.clear();
      indexes.clear();

      view.addAll(widget.container.source.reversed.map((r) => HttpTraffic(r)));
    });
  }

  void remove(List<HttpRequest> list) {
    final removedRequestIds = list.map((r) => r.requestId).toSet();
    setState(() {
      view.removeWhere((item) => item is HttpTraffic && list.contains(item.request));
      for (final requestId in removedRequestIds) {
        indexes.remove(requestId);
      }
    });
    selectionController.prune(view.map((item) => item.id));
  }

  ///过滤 (仅 HTTP 请求)
  void search(SearchModel searchModel) {
    this.searchModel = searchModel;
    if (searchModel.isEmpty) {
      view = Queue.of(widget.container.source.reversed.map((r) => HttpTraffic(r)));
    } else {
      view = Queue.of(widget.container
          .where((it) => searchModel.filter(it, it.response))
          .map((r) => HttpTraffic(r))
          .toList()
          .reversed);
    }
    selectionController.prune(view.map((item) => item.id));
    changeState();
  }

  Iterable<HttpRequest> currentView() {
    return view.whereType<HttpTraffic>().map((item) => item.request);
  }

  void deleteSelected() {
    final selected = selectedRequests();
    if (selected.isEmpty) {
      return;
    }
    showConfirmDialog(context, content: '${localizations.delete} ${selected.length} ${localizations.request}?',
        onConfirm: () {
      final removedRequestIds = selected.map((request) => request.requestId).toSet();
      setState(() {
        view.removeWhere((request) => removedRequestIds.contains(request.requestId));
        indexes.removeWhere((requestId, _) => removedRequestIds.contains(requestId));
        selectionController.clear();
        widget.onRemove?.call(selected);
      });

      if (mounted) {
        FlutterToastr.show(localizations.deleteSuccess, context);
      }
    });
  }

  List<HttpRequest> selectedRequests() {
    final selectedIds = selectionController.selectedIds.toSet();
    if (selectedIds.isEmpty) {
      return [];
    }

    return view
        .whereType<HttpTraffic>()
        .where((item) => selectedIds.contains(item.request.requestId))
        .map((item) => item.request)
        .toList();
  }

  void changeState() {
    //防止频繁刷新
    if (!changing) {
      changing = true;
      Future.delayed(const Duration(milliseconds: 350), () {
        setState(() {
          changing = false;
        });
      });
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Obx(() {
      final selectionMode = selectionController.isSelectionMode;

      return Column(children: [
        if (selectionMode)
          SelectionActionBar(
              selectionController: selectionController,
              onRepeat: repeatSelected,
              onExport: exportSelected,
              onDelete: deleteSelected),
        Expanded(
            child: Scrollbar(
                controller: PrimaryScrollController.maybeOf(context),
                child: ListView.separated(
                    controller: PrimaryScrollController.maybeOf(context),
                    cacheExtent: 1000,
                    separatorBuilder: (context, index) =>
                        Divider(thickness: 0.2, height: 0, color: Theme.of(context).dividerColor),
                    itemCount: view.length,
                    itemBuilder: (context, index) {
                      final item = view.elementAt(index);

                      if (item is PacketTraffic) {
                        return _buildPacketRow(item.packet, index);
                      }

                      final request = (item as HttpTraffic).request;
                      final requestId = request.requestId;

                      final key = GlobalKey<RequestRowState>();
                      indexes[requestId] = key;

                      return RequestRow(
                          index: sortDesc ? view.length - index : index,
                          key: key,
                          request: request,
                          proxyServer: widget.proxyServer,
                          displayDomain: widget.displayDomain,
                          selectionController: selectionController,
                          selectionHandlers: RequestSelectionHandlers(
                              onDeleteSelected: deleteSelected,
                              onExportSelected: exportSelected,
                              onRepeatSelected: repeatSelected),
                          onRemove: (item) {
                            setState(() {
                              view.remove(item);
                              indexes.remove(requestId);
                            });
                            selectionController.remove(request.requestId);
                            widget.onRemove?.call([item]);
                          });
                    })))
      ]);
    });
  }

  Widget _buildPacketRow(RawPacket packet, int index) {
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
        TextSpan(children: [
          TextSpan(
            text: _fmtTime(packet.timestamp),
            style: TextStyle(fontSize: 11, color: Colors.teal.shade400),
          ),
          TextSpan(
            text: '  ${_fmtSize(packet.size)}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ]),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
      contentPadding: const EdgeInsets.only(left: 8, right: 5),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => RawPacketDetailPage(packet: packet)),
        );
      },
    );
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  String _fmtTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}.${time.millisecond.toString().padLeft(3, '0')}';
  }

  void scrollToTop() {
    PrimaryScrollController.maybeOf(context)
        ?.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.ease);
  }

  ///排序
  void sort(bool desc) {
    if (sortDesc == desc) {
      return;
    }

    sortDesc = desc;
    setState(() {
      view = Queue.of(view.toList().reversed);
    });
  }

  void exportSelected() {
    final selected = selectedRequests();
    if (selected.isEmpty) {
      return;
    }

    _doExport('ProxyPin_selected_${DateTime.now().dateFormat()}.har', selected);
  }

  void repeatSelected() {
    final selected = selectedRequests();
    if (selected.isEmpty) {
      return;
    }

    _repeatRequests(selected);
  }

  Future<void> _doExport(String fileName, List<HttpRequest> requests) async {
    var json = await Har.writeJson(requests, title: fileName);
    final path = await FilePicker.saveFile(fileName: fileName, bytes: utf8.encode(json));
    if (path == null) {
      return;
    }
    selectionController.clear();
    if (mounted) {
      FlutterToastr.show(localizations.exportSuccess, context);
    }
  }

  Future<void> _repeatRequests(List<HttpRequest> requests) async {
    final proxyServer = widget.proxyServer;
    selectionController.clear();
    for (final request in requests) {
      final httpRequest = request.copy(uri: request.requestUrl);
      final proxyInfo = proxyServer.isRunning ? ProxyInfo.of('127.0.0.1', proxyServer.port) : null;
      try {
        await HttpClients.proxyRequest(httpRequest, proxyInfo: proxyInfo, timeout: const Duration(seconds: 3));
        if (mounted) {
          FlutterToastr.show(localizations.reSendRequest, rootNavigator: true, context);
        }
      } catch (e) {
        if (mounted) {
          FlutterToastr.show('${localizations.fail} $e', rootNavigator: true, context);
        }
      }
    }
  }
}
