import 'package:hive/hive.dart';

part 'message_model.g.dart';

@HiveType(typeId: 0)
class Message extends HiveObject {
  @HiveField(0)
  final String text;

  @HiveField(1)
  final bool isUser;

  @HiveField(2)
  final DateTime timestamp;

  @HiveField(3)
  final String? audioUrl;

  @HiveField(4)
  final String? imageUrl;

  @HiveField(5)
  final bool isVoiceOnly;

  @HiveField(6)
  final String? replyToText;
  
  @HiveField(7)
  final String? senderName; // For group chats
  
  @HiveField(8)
  bool isRead;

  Message({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.imageUrl,
    this.audioUrl,
    this.isVoiceOnly = false,
    this.replyToText,
    this.senderName,
    this.isRead = false,
  });
}
