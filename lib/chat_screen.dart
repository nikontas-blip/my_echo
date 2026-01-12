import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'chat_service.dart';
import 'message_model.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ImagePicker _picker = ImagePicker();
  
  String? _playingUrl;
  XFile? _selectedImage;
  bool _isTyping = false;
  
  // Story State
  bool _hasStory = false;
  String? _activeStoryText;
  Timer? _storyTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    
    _controller.addListener(() {
      setState(() {
        _isTyping = _controller.text.isNotEmpty;
      });
    });

    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) setState(() => _playingUrl = null);
    });
    
    // Check for story immediately and every minute
    _checkForStory();
    _storyTimer = Timer.periodic(const Duration(minutes: 1), (_) => _checkForStory());
  }
  
  @override
  void dispose() {
    _storyTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkForStory() async {
    try {
      // Assuming ChatService has the base URL logic, we'll hardcode or grab it
      // Ideally move this to ChatService, but keeping it here for speed
      const baseUrl = 'http://192.168.1.168:8000'; 
      final res = await http.get(Uri.parse('$baseUrl/story'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data.isNotEmpty && data['text'] != null) {
          if (mounted) {
            setState(() {
              _hasStory = true;
              _activeStoryText = data['text'];
            });
          }
        } else {
          if (mounted) setState(() => _hasStory = false);
        }
      }
    } catch (e) {
      print("Story check failed: $e");
    }
  }

  void _showStory() {
    if (!_hasStory || _activeStoryText == null) return;
    
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (ctx) {
        // Auto close after 5 seconds
        Future.delayed(const Duration(seconds: 5), () {
          if (ctx.mounted) Navigator.of(ctx).pop();
        });
        
        return Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            onTap: () => Navigator.of(ctx).pop(),
            child: Stack(
              children: [
                Center(
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF833ab4), Color(0xFFfd1d1d), Color(0xFFfcb045)],
                        begin: Alignment.topLeft, 
                        end: Alignment.bottomRight
                      ),
                      borderRadius: BorderRadius.circular(20)
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("Alex's Story", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 20),
                        Text(
                          _activeStoryText!, 
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 40,
                  right: 20,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
                // Progress bar visualization (fake)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: null, // Indeterminate for now
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    minHeight: 4,
                  ),
                )
              ],
            ),
          ),
        );
      }
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }
  
  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() => _selectedImage = image);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatService = Provider.of<ChatService>(context);
    if (chatService.messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: const Icon(Icons.arrow_back, color: Colors.white),
        title: Row(
          children: [
            GestureDetector(
              onTap: _showStory,
              child: Container(
                padding: const EdgeInsets.all(2), // Border width
                decoration: _hasStory ? const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF833ab4), Color(0xFFfd1d1d), Color(0xFFfcb045)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight
                  )
                ) : null,
                child: Container(
                  padding: const EdgeInsets.all(2), // Gap between border and image
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black),
                  child: const CircleAvatar(
                    radius: 16,
                    backgroundImage: NetworkImage('https://api.dicebear.com/7.x/notionists/png?seed=Alex&backgroundColor=transparent'), 
                    backgroundColor: Color(0xFF262626),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Alex', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                Text('Active now', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.call_outlined, color: Colors.white, size: 28), onPressed: () {}),
          IconButton(icon: const Icon(Icons.videocam_outlined, color: Colors.white, size: 30), onPressed: () {}),
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white, size: 28),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF262626),
                  title: const Text("Reset Alex?", style: TextStyle(color: Colors.white)),
                  content: const Text(
                    "This will wipe all chat history AND his long-term memory of you. He will forget everything.",
                    style: TextStyle(color: Colors.grey)
                  ),
                  actions: [
                    TextButton(
                      child: const Text("Cancel", style: TextStyle(color: Colors.white)),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                    TextButton(
                      child: const Text("Reset", style: TextStyle(color: Colors.redAccent)),
                      onPressed: () {
                        chatService.clearHistory();
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Memory wiped."))
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              itemCount: chatService.messages.length + (chatService.isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (chatService.isLoading && index == chatService.messages.length) {
                  return const TypingBubble();
                }
                final msg = chatService.messages[index];
                return _buildMessageBubble(msg);
              },
            ),
          ),
          _buildInputArea(chatService),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message msg) {
    final isUser = msg.isUser;
    final hasAudio = msg.audioUrl != null;
    final hasImage = msg.imageUrl != null;
    final isPlaying = _playingUrl == msg.audioUrl;
    
    // Determine Sender Identity
    String avatarUrl = 'https://api.dicebear.com/7.x/notionists/png?seed=Alex&backgroundColor=transparent';
    String displayName = "Alex";
    
    if (msg.senderName == "Sarah") {
      avatarUrl = 'https://api.dicebear.com/7.x/notionists/png?seed=Sarah&backgroundColor=ffdfbf';
      displayName = "Sarah";
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundImage: NetworkImage(avatarUrl),
              backgroundColor: const Color(0xFF262626),
            ),
            const SizedBox(width: 8),
          ],
          Container(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isUser && msg.senderName != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(displayName, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                  ),
                if (msg.replyToText != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A3A3A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    constraints: const BoxConstraints(minWidth: 100), // Ensure it's not too tiny
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Replying to you", style: TextStyle(color: Colors.grey, fontSize: 10)),
                        const SizedBox(height: 2),
                        Text(
                          msg.replyToText!, 
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                Container(
                  decoration: isUser
                      ? const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFa13bf7), Color(0xFFf72d7a), Color(0xFFf98e54)], // Instagram Gradient
                            begin: Alignment.bottomLeft,
                            end: Alignment.topRight,
                          ),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(22),
                            topRight: Radius.circular(22),
                            bottomLeft: Radius.circular(22),
                            bottomRight: Radius.circular(4),
                          ),
                        )
                      : BoxDecoration(
                          color: const Color(0xFF262626),
                          borderRadius: BorderRadius.circular(22),
                        ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasImage)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.network(msg.imageUrl!, height: 200, width: double.infinity, fit: BoxFit.cover),
                          ),
                        ),
                      if (hasAudio && !isUser)
                         GestureDetector(
                          onTap: () async {
                            if (isPlaying) {
                              await _audioPlayer.stop();
                              if (mounted) setState(() => _playingUrl = null);
                            } else {
                              if (mounted) setState(() => _playingUrl = msg.audioUrl);
                              await _audioPlayer.play(UrlSource(msg.audioUrl!));
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 24),
                                const SizedBox(width: 8),
                                SizedBox(
                                  height: 20,
                                  width: 60,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: List.generate(8, (i) => Container(
                                      width: 3,
                                      height: 5 + (i % 3) * 6.0,
                                      decoration: BoxDecoration(color: Colors.white70, borderRadius: BorderRadius.circular(2)),
                                    )),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (msg.text.isNotEmpty && !msg.isVoiceOnly)
                        MarkdownBody(
                          data: msg.text,
                          styleSheet: MarkdownStyleSheet(
                            p: const TextStyle(color: Colors.white, fontSize: 17, height: 1.3),
                            code: const TextStyle(color: Colors.white, backgroundColor: Colors.white24, fontFamily: 'monospace'),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(ChatService chatService) {
    return Column(
      children: [
        if (_selectedImage != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFF262626), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(_selectedImage!.path, height: 50, width: 50, fit: BoxFit.cover),
                ),
                const SizedBox(width: 10),
                const Expanded(child: Text("Ready to send...", style: TextStyle(color: Colors.white70, fontSize: 13))),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => setState(() => _selectedImage = null),
                )
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          color: Colors.black,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Color(0xFF262626), shape: BoxShape.circle),
                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF262626),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.purpleAccent,
                          decoration: const InputDecoration(
                            hintText: 'Message...',
                            hintStyle: TextStyle(color: Colors.grey),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onSubmitted: (_) => _send(chatService),
                        ),
                      ),
                      if (_isTyping || _selectedImage != null)
                        GestureDetector(
                          onTap: () => _send(chatService),
                          child: const Text(
                            "Send", 
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)
                          ),
                        )
                      else ...[
                        const Icon(Icons.mic_none_rounded, color: Colors.white, size: 26),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: _pickImage,
                          child: const Icon(Icons.image_outlined, color: Colors.white, size: 26)
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.sticky_note_2_outlined, color: Colors.white, size: 26),
                      ]
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _send(ChatService chatService) {
    final text = _controller.text;
    final image = _selectedImage;
    
    if (text.isNotEmpty || image != null) {
      chatService.sendMessage(text, image: image);
      _controller.clear();
      setState(() {
        _selectedImage = null;
        _isTyping = false;
      });
    }
  }
}

class TypingBubble extends StatelessWidget {
  const TypingBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 0, top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const CircleAvatar(
            radius: 14,
            backgroundImage: NetworkImage('https://api.dicebear.com/7.x/notionists/png?seed=Alex&backgroundColor=transparent'), 
            backgroundColor: Color(0xFF262626),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF262626),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Text("...", style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}