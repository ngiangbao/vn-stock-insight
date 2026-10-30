import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ai/finance_chat.dart';
import '../state.dart';

/// App-wide overlay above the navigator, including stock dialogs and reports.
class FloatingFinanceChat extends StatefulWidget {
  final Widget child;
  final FinanceChatService? service;
  const FloatingFinanceChat({super.key, required this.child, this.service});
  @override
  State<FloatingFinanceChat> createState() => _FloatingFinanceChatState();
}

class _FloatingFinanceChatState extends State<FloatingFinanceChat> {
  static const _size = 52.0, _gap = 12.0;
  bool _left = false, _dragging = false, _open = false, _sending = false;
  double _vertical = 0.75;
  Offset? _drag;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final _history = <FinanceTurn>[];
  final _messages = <({bool user, String text})>[];
  late final _service = widget.service ?? FinanceChatService();
  int _generation = 0;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Offset _position(Size size) {
    final maxX = math.max(_gap, size.width - _size - _gap);
    final maxY = math.max(_gap, size.height - _size - _gap);
    return _dragging && _drag != null
        ? Offset(_drag!.dx.clamp(_gap, maxX), _drag!.dy.clamp(_gap, maxY))
        : Offset(_left ? _gap : maxX, _gap + _vertical * (maxY - _gap));
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  });

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_sending || text.isEmpty) return;
    final app = AppScope.of(context);
    final generation = _generation;
    setState(() {
      _sending = true;
      _messages.add((user: true, text: text));
      _input.clear();
    });
    _scrollDown();
    final reply = await _service.reply(
      question: text,
      history: List.of(_history),
      config: app.resolveAiConfig,
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      _sending = false;
      _messages.add((user: false, text: reply.text));
      if (reply.accepted) {
        _history.add(FinanceTurn(text, reply.text));
        if (_history.length > 6) _history.removeAt(0);
      }
      if (_messages.length > 40) {
        _messages.removeRange(0, _messages.length - 40);
      }
    });
    _scrollDown();
  }

  Widget _panel(BuildContext context, double height) {
    if (height < 200) {
      return SingleChildScrollView(
        child: SizedBox(height: 220, child: _panel(context, 220)),
      );
    }
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 12,
      color: cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 14, right: 4),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'AI Tài chính',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Xóa cuộc trò chuyện',
                  onPressed: () => setState(() {
                    _generation++;
                    _sending = false;
                    _messages.clear();
                    _history.clear();
                  }),
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
                IconButton(
                  tooltip: 'Đóng chat',
                  onPressed: () {
                    _focus.unfocus();
                    setState(() => _open = false);
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          if (height >= 300)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(
                'Chỉ tài chính & chứng khoán · ${AppScope.of(context).aiLabel}\nLịch sử chỉ giữ trong phiên. Chat chưa có dữ liệu giá trực tiếp.',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Bạn muốn tìm hiểu điều gì về tài chính hoặc chứng khoán?',
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final message = _messages[i];
                      return Align(
                        alignment: message.user
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: message.user
                                ? cs.primaryContainer
                                : cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          // Plain text only: never execute HTML, links, commands, or tools.
                          child: SelectableText(
                            message.text,
                            style: TextStyle(
                              color: message.user
                                  ? cs.onPrimaryContainer
                                  : cs.onSurface,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_sending) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    maxLength: 4000,
                    minLines: 1,
                    maxLines: height >= 300 ? 3 : 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Hỏi về tài chính, chứng khoán…',
                      counterText: '',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Gửi câu hỏi',
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      Positioned.fill(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                final position = _position(size);
                final panelHeight = math.min(
                  560.0,
                  math.max(0.0, size.height - 24),
                );
                return Stack(
                  children: [
                    if (_open)
                      Positioned(
                        left: _left ? _gap : null,
                        right: _left ? null : _gap,
                        bottom: _gap,
                        width: math.max(0, math.min(440.0, size.width - 24)),
                        height: panelHeight,
                        child: _panel(context, panelHeight),
                      ),
                    if (!_open)
                      AnimatedPositioned(
                        duration: _dragging
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        left: position.dx,
                        top: position.dy,
                        width: _size,
                        height: _size,
                        child: Semantics(
                          label: 'Chat AI tài chính, kéo để di chuyển',
                          button: true,
                          child: GestureDetector(
                            onPanStart: (_) => setState(() {
                              _drag = position;
                              _dragging = true;
                            }),
                            onPanUpdate: (details) => setState(() {
                              _drag = _position(size) + details.delta;
                            }),
                            onPanEnd: (_) => setState(() {
                              final end = _position(size);
                              _left = end.dx + _size / 2 < size.width / 2;
                              final range = size.height - _size - 2 * _gap;
                              _vertical = range > 0
                                  ? ((end.dy - _gap) / range).clamp(0, 1)
                                  : 0;
                              _dragging = false;
                              _drag = null;
                            }),
                            onPanCancel: () => setState(() {
                              _dragging = false;
                              _drag = null;
                            }),
                            child: Material(
                              color: Theme.of(context).colorScheme.primary,
                              shape: const CircleBorder(),
                              elevation: 6,
                              child: IconButton(
                                key: const ValueKey('finance-chat-bubble'),
                                tooltip: 'Chat AI tài chính',
                                onPressed: () => setState(() => _open = true),
                                icon: Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ],
  );
}
