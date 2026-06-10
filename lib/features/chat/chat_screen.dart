import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/storage/chat_store.dart';
import '../../core/mesh/message_model.dart';
import '../../core/transport/nearby_service.dart';

class ChatScreen extends StatefulWidget {
  final String deviceId;
  final String deviceName;
  final String groupId;
  final NearbyService nearby;

  const ChatScreen({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.groupId,
    required this.nearby,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  NearbyService get _nearby => widget.nearby;
  final List<StoredMessage> _messages = [];
  final List<StoredFile> _receivedFiles = [];
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final Map<String, Color> _peerColors = {};
  int _peersCount = 0;

  Color _colorForSender(String senderId) {
    if (!_peerColors.containsKey(senderId)) {
      final colors = [
        Colors.blue.shade400,
        Colors.purple.shade400,
        Colors.orange.shade400,
        Colors.red.shade400,
        Colors.teal.shade400,
        Colors.pink.shade400,
        Colors.indigo.shade400,
      ];
      _peerColors[senderId] = colors[_peerColors.length % colors.length];
    }
    return _peerColors[senderId]!;
  }

  @override
  void initState() {
    super.initState();
    _loadPersistedState();
    _nearby.onMessage = (msg) {
      if (msg.groupId == widget.groupId) {
        final entry = StoredMessage(
          message: msg,
          status: LocalMessageStatus.received,
        );
        setState(() => _messages.add(entry));
        ChatStore.instance.upsertMessage(entry);
        _scrollToBottom();
        if (msg.type == MessageType.sos) {
          _showSnack('SOS received from ${msg.senderName}');
        }
      }
    };
    _nearby.onPeerConnected = (id, name) {
      setState(() => _peersCount = _nearby.connectedPeers.length);
      _showSnack('$name joined the trip 🏔️');
    };
    _nearby.onPeerDisconnected = (id) {
      setState(() => _peersCount = _nearby.connectedPeers.length);
      _showSnack('A peer disconnected');
    };
    _nearby.onSystemEvent = _showSnack;
    _nearby.onFileReceived = (endpointId, filePath) async {
      final file = StoredFile(
        id: DateTime.now().millisecondsSinceEpoch,
        groupId: widget.groupId,
        senderId: endpointId,
        senderName: endpointId,
        path: filePath,
        timestamp: DateTime.now(),
      );
      await ChatStore.instance.addReceivedFile(
        groupId: file.groupId,
        senderId: file.senderId,
        senderName: file.senderName,
        path: file.path,
        timestamp: file.timestamp,
      );
      if (mounted) {
        setState(() => _receivedFiles.insert(0, file));
      }
    };
  }

  Future<void> _loadPersistedState() async {
    final msgs = await ChatStore.instance.loadMessages(widget.groupId);
    final files = await ChatStore.instance.loadReceivedFiles(widget.groupId);
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(msgs);
      _receivedFiles
        ..clear()
        ..addAll(files);
    });
    _scrollToBottom();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    final msg = MeshMessage(
      senderId: widget.deviceId,
      senderName: widget.deviceName,
      groupId: widget.groupId,
      content: text,
      type: MessageType.chat,
    );

    final entry = StoredMessage(
      message: msg,
      status: LocalMessageStatus.sending,
    );
    setState(() => _messages.add(entry));
    await ChatStore.instance.upsertMessage(entry);
    _ctrl.clear();
    _scrollToBottom();

    final sent = await _nearby.send(msg);
    final status = sent ? LocalMessageStatus.sent : LocalMessageStatus.failed;
    await ChatStore.instance.updateMessageStatus(msg.id, status);
    if (!mounted) return;
    final idx = _messages.indexWhere((m) => m.message.id == msg.id);
    if (idx != -1) {
      setState(() {
        _messages[idx] = StoredMessage(message: msg, status: status);
      });
    }
  }

  Future<void> _sendTypedMessage(MessageType type) async {
    if (type == MessageType.file) {
      await _pickAndSendFile();
      return;
    }

    final hint = switch (type) {
      MessageType.file => 'Enter file/photo name (example: trek_plan.jpg)',
      MessageType.music => 'Enter music title or link',
      _ => 'Enter message',
    };
    final title = switch (type) {
      MessageType.file => 'Share file/photo',
      MessageType.music => 'Share music',
      _ => 'Send message',
    };

    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (content == null || content.isEmpty) return;
    final msg = MeshMessage(
      senderId: widget.deviceId,
      senderName: widget.deviceName,
      groupId: widget.groupId,
      content: content,
      type: type,
    );
    final sent = await _nearby.send(msg);
    final status = sent ? LocalMessageStatus.sent : LocalMessageStatus.failed;
    final entry = StoredMessage(message: msg, status: status);
    setState(() => _messages.add(entry));
    await ChatStore.instance.upsertMessage(entry);
    _scrollToBottom();
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;

    final selected = result.files.single;
    final path = selected.path;
    if (path == null) {
      _showSnack('Could not read selected file');
      return;
    }

    final file = File(path);
    final sizeBytes = await file.length();
    final sizeLabel = (sizeBytes / 1024).toStringAsFixed(1);

    await _nearby.sendFileToPeers(path);

    final msg = MeshMessage(
      senderId: widget.deviceId,
      senderName: widget.deviceName,
      groupId: widget.groupId,
      content: '${selected.name} ($sizeLabel KB)',
      type: MessageType.file,
    );
    final sent = await _nearby.send(msg);
    final status = sent ? LocalMessageStatus.sent : LocalMessageStatus.failed;
    final entry = StoredMessage(message: msg, status: status);
    setState(() => _messages.add(entry));
    await ChatStore.instance.upsertMessage(entry);
    _scrollToBottom();
    _showSnack('Shared ${selected.name}');
  }

  Future<void> _sendSOS() async {
    final msg = MeshMessage(
      senderId: widget.deviceId,
      senderName: widget.deviceName,
      groupId: widget.groupId,
      content: 'SOS! Need immediate assistance.',
      type: MessageType.sos,
    );
    final sent = await _nearby.send(msg);
    final status = sent ? LocalMessageStatus.sent : LocalMessageStatus.failed;
    final entry = StoredMessage(message: msg, status: status);
    setState(() => _messages.add(entry));
    await ChatStore.instance.upsertMessage(entry);
    _scrollToBottom();
    _showSnack(
      sent ? 'SOS alert sent to group' : 'SOS queued failed (no peers)',
    );
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                scheme.primary,
                scheme.primary.withValues(alpha: 0.82),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.groupId,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            Text(
              _peersCount == 0
                  ? 'Searching for peers...'
                  : '$_peersCount peer(s) connected',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == 'music') {
                _sendTypedMessage(MessageType.music);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'music',
                child: Text('Share music (title/link)'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Received files inbox',
            onPressed: _showReceivedFiles,
            icon: const Icon(Icons.folder, color: Colors.white),
          ),
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _peersCount > 0
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.white12,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  _peersCount > 0 ? Icons.wifi : Icons.wifi_off,
                  color: _peersCount > 0 ? Colors.greenAccent : Colors.white54,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  _peersCount.toString(),
                  style: TextStyle(
                    color:
                        _peersCount > 0 ? Colors.greenAccent : Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.terrain, size: 60, color: Colors.grey),
                        const SizedBox(height: 12),
                        const Text(
                          'No messages yet',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Waiting for group members\nwith code: ${widget.groupId}',
                          textAlign: TextAlign.center,
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) => _MessageBubble(
                      msg: _messages[i].message,
                      status: _messages[i].status,
                      isMe: _messages[i].message.senderId == widget.deviceId,
                      color: _messages[i].message.senderId == widget.deviceId
                          ? scheme.primary
                          : _colorForSender(_messages[i].message.senderId),
                    ),
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Send SOS',
                  onPressed: _sendSOS,
                  icon: const Icon(Icons.sos, color: Colors.redAccent),
                ),
                IconButton(
                  tooltip: 'Share file/photo',
                  onPressed: () => _sendTypedMessage(MessageType.file),
                  icon: const Icon(Icons.attach_file),
                ),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _send,
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Icon(Icons.arrow_upward, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showReceivedFiles() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: _receivedFiles.isEmpty
              ? const Center(child: Text('No files received yet'))
              : ListView.builder(
                  itemCount: _receivedFiles.length,
                  itemBuilder: (context, i) {
                    final item = _receivedFiles[i];
                    return ListTile(
                      leading: const Icon(Icons.insert_drive_file),
                      title: Text(
                        item.path.split('/').last.split('\\').last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${item.senderName} • ${item.path}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Open',
                            onPressed: () => OpenFilex.open(item.path),
                            icon: const Icon(Icons.open_in_new),
                          ),
                          IconButton(
                            tooltip: 'Share',
                            onPressed: () =>
                                Share.shareXFiles([XFile(item.path)]),
                            icon: const Icon(Icons.share),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final MeshMessage msg;
  final LocalMessageStatus status;
  final bool isMe;
  final Color color;

  const _MessageBubble({
    required this.msg,
    required this.status,
    required this.isMe,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final typeLabel = switch (msg.type) {
      MessageType.sos => 'SOS',
      MessageType.file => 'FILE/PHOTO',
      MessageType.music => 'MUSIC',
      MessageType.location => 'LOCATION',
      MessageType.ping => 'PING',
      MessageType.chat => null,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: color,
              child: Text(
                msg.senderName.isNotEmpty
                    ? msg.senderName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7,
              ),
              decoration: BoxDecoration(
                gradient: isMe
                    ? LinearGradient(
                        colors: [
                          scheme.primary,
                          scheme.primary.withValues(alpha: 0.82),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isMe ? null : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: isMe ? null : Border.all(color: Colors.black12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Text(
                      msg.senderName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  if (typeLabel != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: msg.type == MessageType.sos
                            ? Colors.redAccent.withValues(alpha: 0.15)
                            : (isMe
                                ? Colors.white.withValues(alpha: 0.15)
                                : Colors.black12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        typeLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: msg.type == MessageType.sos
                              ? Colors.redAccent
                              : (isMe ? Colors.white70 : Colors.black54),
                        ),
                      ),
                    ),
                  Text(
                    msg.content,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${msg.timestamp.hour}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 10,
                          color: isMe ? Colors.white70 : Colors.grey,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 8),
                        Text(
                          switch (status) {
                            LocalMessageStatus.sending => 'sending…',
                            LocalMessageStatus.sent => 'sent',
                            LocalMessageStatus.failed => 'failed',
                            LocalMessageStatus.received => 'received',
                          },
                          style: TextStyle(
                            fontSize: 10,
                            color: status == LocalMessageStatus.failed
                                ? Colors.redAccent
                                : (isMe ? Colors.white70 : Colors.grey),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: color,
              child: Text(
                msg.senderName.isNotEmpty
                    ? msg.senderName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
