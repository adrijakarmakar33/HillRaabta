import 'dart:convert';
import 'package:uuid/uuid.dart';

enum MessageType { chat, location, sos, file, music, ping }

class MeshMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String groupId;
  final String content;
  final MessageType type;
  int ttl;
  final DateTime timestamp;

  MeshMessage({
    String? id,
    required this.senderId,
    required this.senderName,
    required this.groupId,
    required this.content,
    required this.type,
    this.ttl = 5,
    DateTime? timestamp,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  bool get shouldRelay => ttl > 0;
  bool get isSOS => type == MessageType.sos;

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'senderName': senderName,
        'groupId': groupId,
        'content': content,
        'type': type.name,
        'ttl': ttl,
        'timestamp': timestamp.toIso8601String(),
      };

  factory MeshMessage.fromJson(Map<String, dynamic> j) => MeshMessage(
        id: j['id'],
        senderId: j['senderId'],
        senderName: j['senderName'],
        groupId: j['groupId'],
        content: j['content'],
        type: MessageType.values.byName(j['type']),
        ttl: j['ttl'],
        timestamp: DateTime.parse(j['timestamp']),
      );

  String encode() => jsonEncode(toJson());
  static MeshMessage decode(String raw) =>
      MeshMessage.fromJson(jsonDecode(raw));
}
