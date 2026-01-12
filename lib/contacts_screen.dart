import 'package:flutter/material.dart';
import 'chat_screen.dart';
import 'chat_service.dart';
import 'package:provider/provider.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  final List<Map<String, dynamic>> contacts = const [
    {
      "id": "alex",
      "name": "Alex",
      "status": "Online",
      "description": "Graphic Designer",
      "color": Colors.purpleAccent,
      "avatar": "A"
    },
    {
      "id": "sarah",
      "name": "Sarah",
      "status": "Offline",
      "description": "Student / Party Girl",
      "color": Colors.pinkAccent,
      "avatar": "S"
    },
    {
      "id": "marcus",
      "name": "Marcus",
      "status": "Encrypted Connection",
      "description": "Unknown Contact",
      "color": Colors.cyanAccent,
      "avatar": "M"
    },
    {
      "id": "dr_k",
      "name": "Dr. K",
      "status": "Available",
      "description": "Licensed Therapist",
      "color": Colors.greenAccent,
      "avatar": "K"
    },
    {
      "id": "group",
      "name": "Nearby Users",
      "status": "2 people nearby",
      "description": "Public channel",
      "color": Colors.orangeAccent,
      "avatar": "G"
    }
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          "Direct Messages",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () {},
          )
        ],
        elevation: 0,
      ),
      body: ListView.builder(
        itemCount: contacts.length,
        itemBuilder: (context, index) {
          final contact = contacts[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: CircleAvatar(
              radius: 28,
              backgroundColor: (contact['color'] as Color).withOpacity(0.2),
              child: Text(
                contact['avatar'],
                style: TextStyle(
                  color: contact['color'],
                  fontWeight: FontWeight.bold,
                  fontSize: 20
                ),
              ),
            ),
            title: Text(
              contact['name'],
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Text(
              contact['description'],
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.camera_alt_outlined, color: Colors.grey),
            onTap: () {
              final chatService = Provider.of<ChatService>(context, listen: false);
              
              if (contact['id'] == "group") {
                chatService.switchThread("group");
              } else {
                chatService.switchThread("dm");
                chatService.setCharacter(contact['id']);
              }
              
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChatScreen()),
              );
            },
          );
        },
      ),
    );
  }
}
