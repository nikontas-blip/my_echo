import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'message_model.dart';
import 'package:image_picker/image_picker.dart';
import 'main.dart'; // To access flutterLocalNotificationsPlugin

class ChatService extends ChangeNotifier {
  static const String _baseUrl = 'http://192.168.1.168:8000';
  
  List<Message> _messages = [];
  List<Message> get messages => _messages;

  bool _isLoading = false;
  bool get isLoading => _isLoading;
  
  bool _isAiTyping = false;
  bool get isAiTyping => _isAiTyping;
  
  String _currentThread = "dm"; // "dm" or "group"
  
  String _characterId = "alex";
  String get characterId => _characterId;

  Box<Message>? _boxDm;
  Box<Message>? _boxGroup;
  Timer? _pollingTimer;

  Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(MessageAdapter());
    
    _boxDm = await Hive.openBox<Message>('chat_history_dm');
    _boxGroup = await Hive.openBox<Message>('chat_history_group');
    
    _loadMessagesForThread();
    
    // Start Polling for Heartbeat Messages
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (timer) => _pollServer());
  }
  
  void setCharacter(String id) {
    _characterId = id;
    notifyListeners();
  }
  
  void switchThread(String threadId) {
    if (_currentThread == threadId) return;
    _currentThread = threadId;
    _loadMessagesForThread();
    notifyListeners();
  }
  
  void _loadMessagesForThread() async {
    // Small delay to allow pending Hive writes to finish
    await Future.delayed(const Duration(milliseconds: 20));
    final box = _currentThread == "group" ? _boxGroup : _boxDm;
    try {
      _messages = box?.values.toList().cast<Message>() ?? [];
    } catch (e) {
      print("Concurrency Error loading messages: $e");
      _messages = [];
    }
    notifyListeners();
  }
  
  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _pollServer() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/sync'));
      if (response.statusCode == 200) {
        dynamic decoded;
        try {
          decoded = jsonDecode(response.body);
        } catch (e) {
          print("JSON Decode Error: $e");
          return;
        }

        if (decoded is List) {
          // Heartbeat messages usually go to DM
          for (var msgData in decoded) {
            final msg = Message(
              text: msgData['text'],
              isUser: false,
              timestamp: DateTime.now(), 
            );
            // Default to DM box for auto-messages
            _boxDm?.add(msg);
            
            // Only update UI if we are looking at DM
            if (_currentThread == "dm") {
              _messages.add(msg);
              notifyListeners();
            }
            
            // Show Notification
            const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
                'alex_msgs', 'Alex Messages',
                importance: Importance.max, priority: Priority.high, showWhen: true);
            const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);
            
            flutterLocalNotificationsPlugin.show(
                Random().nextInt(100000), 
                'Alex', 
                msg.text, 
                platformChannelSpecifics
            );
          }
        }
      }
    } catch (e) {
      print("Polling Error: $e");
    }
  }

  Future<void> sendMessage(String text, {XFile? image}) async {
    if (text.trim().isEmpty && image == null) return;

    // 1. Upload Image First if exists
    String? serverImageFilename;
    String? localImageUrl;

    if (image != null) {
      if (kIsWeb) {
        localImageUrl = image.path; // On web this is a blob url
      } else {
        localImageUrl = image.path;
      }
      
      _isLoading = true;
      notifyListeners();

      try {
        var request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/upload'));
        
        // Read bytes for web compatibility
        final bytes = await image.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes(
          'file', 
          bytes,
          filename: image.name,
          contentType: MediaType('image', 'jpeg'), // Assuming jpeg/png
        ));

        var res = await request.send();
        if (res.statusCode == 200) {
          final respStr = await res.stream.bytesToString();
          final data = jsonDecode(respStr);
          serverImageFilename = data['filename'];
        }
      } catch (e) {
        print("Upload Failed: $e");
      }
    }

    // 2. Add User Message to UI
    final userMsg = Message(
      text: text, 
      isUser: true, 
      timestamp: DateTime.now(),
      imageUrl: localImageUrl // Display local preview
    );
    _messages.add(userMsg);
    
    final activeBox = _currentThread == "group" ? _boxGroup : _boxDm;
    activeBox?.add(userMsg);
    
    _isLoading = true;
    notifyListeners();

    // Simulate "Read" status after 1-2 seconds
    Future.delayed(Duration(milliseconds: 1000 + Random().nextInt(1000)), () {
        if (_messages.contains(userMsg)) {
            userMsg.isRead = true;
            userMsg.save(); // Update in Hive
            notifyListeners();
        }
    });

    try {
      // 3. Prepare History
      int historyCount = 2000;
      int start = (_messages.length - 1 - historyCount).clamp(0, _messages.length);
      
      List<Map<String, String>> history = [
        {
          "role": "system",
          "content": "You are my best friend. You are chill, real, and supportive. You are not an AI assistant, you are a companion. You speak casually. Keep responses concise unless asked for more."
        }
      ];

      for (var i = start; i < _messages.length; i++) {
        history.add({
          "role": _messages[i].isUser ? "user" : "assistant",
          "content": _messages[i].text
        });
      }

      // 4. Send to Python Server (Chat endpoint)
      final body = {
        "message": text,
        "history": history,
        "thread_id": _currentThread,
        "character_id": _characterId
      };
      
      if (serverImageFilename != null) {
        body["image_filename"] = serverImageFilename;
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        dynamic data;
        try {
          data = jsonDecode(response.body);
        } catch (e) {
          _addError("Invalid Server Response");
          return;
        }
        
        if (data is Map && data.containsKey('group_messages') && data['group_messages'] is List) {
          // Handle Group Chat Response
          final List<dynamic> groupMsgs = data['group_messages'];
          for (var msgData in groupMsgs) {
             final sender = msgData['sender']?.toString();
             final text = msgData['text']?.toString() ?? ""; // Prevent NULL crash
             
             final msg = Message(
               text: text,
               isUser: false,
               timestamp: DateTime.now(),
               senderName: sender
             );
             _messages.add(msg);
             activeBox?.add(msg);
          }
        } else if (data is Map) {
          // New Multi-Message Logic
          List<dynamic> responseMsgs = [];
          if (data.containsKey('messages')) {
             responseMsgs = data['messages'];
          } else {
             // Fallback for old single response format
             responseMsgs.add({
               "text": data['text'], 
               "audio_url": data['audio_url'],
               "is_voice_only": data['is_voice_only'] ?? false,
               "typing_delay": 2.0
             });
          }
          
          _isLoading = false; // Initial load done, now we stream bubbles
          notifyListeners();
          
          for (var msgData in responseMsgs) {
            // 1. Show Typing Indicator
            _isAiTyping = true;
            notifyListeners();
            
            // 2. Wait for calculated delay
            double delay = (msgData['typing_delay'] ?? 2.0).toDouble();
            await Future.delayed(Duration(milliseconds: (delay * 1000).toInt()));
            
            // 3. Add Message
            _isAiTyping = false;
            final aiText = msgData['text']?.toString() ?? "";
            final audioPath = msgData['audio_url']; 
            final isVoiceOnly = msgData['is_voice_only'] ?? false;
            
            String? fullAudioUrl;
            if (audioPath != null) {
               fullAudioUrl = '$_baseUrl$audioPath';
            }
    
            // Logic: Sometimes reply to the specific message (only for first bubble maybe?)
            String? replyContext;
            if (Random().nextDouble() < 0.2 && text.isNotEmpty && responseMsgs.indexOf(msgData) == 0) {
              replyContext = text.length > 50 ? "${text.substring(0, 50)}..." : text;
            }
    
            final aiMsg = Message(
              text: aiText, 
              isUser: false, 
              timestamp: DateTime.now(),
              audioUrl: fullAudioUrl,
              isVoiceOnly: isVoiceOnly,
              replyToText: replyContext,
              isRead: true // User sees it immediately
            );
            
            _messages.add(aiMsg);
            activeBox?.add(aiMsg);
            notifyListeners();
            
            // Small pause between bubbles
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
      } else {
        _addError("Server Error: ${response.statusCode}");
        _isLoading = false;
      }
    } catch (e) {
       _addError("Connection Failed: $e");
       _isLoading = false;
    } finally {
      _isLoading = false;
      _isAiTyping = false;
      notifyListeners();
    }
  }

  void _addError(String text) {
    final msg = Message(text: text, isUser: false, timestamp: DateTime.now());
    _messages.add(msg);
  }

  Future<void> clearHistory() async {
    final activeBox = _currentThread == "group" ? _boxGroup : _boxDm;
    activeBox?.clear();
    _messages.clear();
    notifyListeners();
    
    // Only wipe backend memory if clearing DM (core memory)
    if (_currentThread == "dm") {
      try {
        await http.post(Uri.parse('$_baseUrl/clear'));
      } catch (e) {
        print("Failed to clear backend memory: $e");
      }
    }
  }
}
