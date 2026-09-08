import 'package:flutter/material.dart';

/// Sidebar listing past general-chat sessions (see ChatScreen's session
/// management) — tap to resume one, or start a new chat. Project chats
/// aren't listed here; they're browsed from their own project instead
/// (see ProjectWorkspaceScreen, and LocalDb.loadSessions' doc comment for
/// why they're excluded).
class ChatSessionsDrawer extends StatelessWidget {
  const ChatSessionsDrawer({
    super.key,
    required this.sessions,
    required this.currentSessionId,
    required this.onSelectSession,
    required this.onNewChat,
    required this.onDeleteSession,
  });

  final List<Map<String, dynamic>> sessions;
  final String currentSessionId;
  final ValueChanged<String> onSelectSession;
  final VoidCallback onNewChat;
  final ValueChanged<String> onDeleteSession;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(child: Text('Chats', style: Theme.of(context).textTheme.titleMedium)),
                  IconButton(
                    icon: const Icon(Icons.add_comment_outlined),
                    tooltip: 'New chat',
                    onPressed: () {
                      Navigator.of(context).pop();
                      onNewChat();
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: sessions.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No past chats yet.'),
                      ),
                    )
                  : ListView.builder(
                      itemCount: sessions.length,
                      itemBuilder: (context, index) {
                        final session = sessions[index];
                        final sessionId = session['session_id'] as String;
                        final preview = session['preview'] as String?;
                        final isCurrent = sessionId == currentSessionId;
                        return ListTile(
                          selected: isCurrent,
                          leading: const Icon(Icons.chat_bubble_outline),
                          title: Text(
                            (preview != null && preview.isNotEmpty) ? preview : 'New chat',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => onDeleteSession(sessionId),
                          ),
                          onTap: () {
                            Navigator.of(context).pop();
                            onSelectSession(sessionId);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
