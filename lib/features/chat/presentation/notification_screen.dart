import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pfe1/features/chat/data/chat_service.dart';
import 'package:pfe1/features/chat/presentation/chat_room_screen.dart';
import 'package:pfe1/shared/providers/post_notification_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService(Supabase.instance.client);
});

class NotificationScreen extends ConsumerStatefulWidget {
  final Function(int postId, String postType)? onPostNotificationTap;
  
  const NotificationScreen({Key? key, this.onPostNotificationTap}) : super(key: key);
  @override
  ConsumerState<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends ConsumerState<NotificationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Stream<int> _unreadNotificationsStream;
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _postNotifications = [];
  bool _isLoading = true;
  bool _isPostNotificationsLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadNotifications();
    _loadPostNotifications();

    final userEmail = Supabase.instance.client.auth.currentUser?.email;
    if (userEmail != null) {
      _unreadNotificationsStream =
          ref.read(chatServiceProvider).watchUnreadNotificationCount(userEmail);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    try {
      final userEmail = Supabase.instance.client.auth.currentUser?.email;
      if (userEmail != null) {
        final notifications =
            await ref.read(chatServiceProvider).getUserNotifications(userEmail);
        setState(() => _notifications = notifications);
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error loading notifications: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPostNotifications() async {
    setState(() => _isPostNotificationsLoading = true);
    try {
      final userEmail = Supabase.instance.client.auth.currentUser?.email;
      if (userEmail == null) return;
      final data = await Supabase.instance.client
          .from('post_notifications')
          .select()
          .eq('recipient_email', userEmail)
          .order('created_at', ascending: false);
      setState(() => _postNotifications = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error loading post notifications: $e')));
    } finally {
      setState(() => _isPostNotificationsLoading = false);
    }
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      final success =
          await ref.read(chatServiceProvider).markNotificationAsRead(notificationId);
      if (success) _loadNotifications();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error marking notification as read: $e')));
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final userEmail = Supabase.instance.client.auth.currentUser?.email;
      if (userEmail != null) {
        final success =
            await ref.read(chatServiceProvider).markAllNotificationsAsRead(userEmail);
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('All notifications marked as read')));
          _loadNotifications();
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _markPostNotificationAsRead(int id) async {
    await Supabase.instance.client
        .from('post_notifications')
        .update({'is_read': true}).eq('id', id);
    if (mounted) _loadPostNotifications();
  }

  Future<void> _markAllPostNotificationsAsRead() async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email;
    if (userEmail == null) return;
    await Supabase.instance.client
        .from('post_notifications')
        .update({'is_read': true}).eq('recipient_email', userEmail);
    _loadPostNotifications();
  }

  Future<void> _deleteNotification(String notificationId) async {
    try {
      final success =
          await ref.read(chatServiceProvider).deleteNotification(notificationId);
      if (success) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Notification deleted')));
        _loadNotifications();
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error deleting notification: $e')));
    }
  }

  Future<void> _deleteAllNotifications() async {
    try {
      final userEmail = Supabase.instance.client.auth.currentUser?.email;
      if (userEmail != null) {
        final success =
            await ref.read(chatServiceProvider).deleteAllNotifications(userEmail);
        if (success) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('All notifications deleted')));
          _loadNotifications();
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _deletePostNotification(int id) async {
    await Supabase.instance.client
        .from('post_notifications')
        .delete()
        .eq('id', id);
    _loadPostNotifications();
  }

  Future<void> _deleteAllPostNotifications() async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email;
    if (userEmail == null) return;
    await Supabase.instance.client
        .from('post_notifications')
        .delete()
        .eq('recipient_email', userEmail);
    _loadPostNotifications();
  }

  void _navigateToChatScreen(String chatRoomId, Map<String, dynamic> sender) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ChatRoomScreen(chatRoomId: chatRoomId, otherUser: sender),
      ),
    ).then((_) => _loadNotifications());
  }

void _onPostNotificationTap(Map<String, dynamic> notification) async {
  await _markPostNotificationAsRead(notification['id']);
  if (!mounted) return;

  Navigator.of(context).pop();

  // Call the callback after popping
  widget.onPostNotificationTap?.call(
    notification['post_id'] as int,
    notification['post_type'] as String,
  );
}


  Future<void> _showDeleteAllConfirmation(VoidCallback onConfirm) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Notifications'),
        content: const Text('Are you sure? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onConfirm();
            },
            child: const Text('Delete All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Messages'),
            Tab(text: 'Posts'),
          ],
        ),
        actions: [
          // Actions change based on current tab
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              if (_tabController.index == 0) {
                return Row(
                  children: [
                    IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _loadNotifications),
                    IconButton(
                        icon: const Icon(Icons.done_all),
                        onPressed: _markAllAsRead),
                    IconButton(
                      icon: const Icon(Icons.delete_sweep),
                      onPressed: _notifications.isEmpty
                          ? null
                          : () => _showDeleteAllConfirmation(_deleteAllNotifications),
                    ),
                  ],
                );
              } else {
                return Row(
                  children: [
                    IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _loadPostNotifications),
                    IconButton(
                        icon: const Icon(Icons.done_all),
                        onPressed: _markAllPostNotificationsAsRead),
                    IconButton(
                      icon: const Icon(Icons.delete_sweep),
                      onPressed: _postNotifications.isEmpty
                          ? null
                          : () => _showDeleteAllConfirmation(_deleteAllPostNotifications),
                    ),
                  ],
                );
              }
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChatNotifications(),
          _buildPostNotifications(),
        ],
      ),
    );
  }

  Widget _buildChatNotifications() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_notifications.isEmpty) return const Center(child: Text('No notifications'));

    return RefreshIndicator(
      onRefresh: _loadNotifications,
      child: ListView.builder(
        itemCount: _notifications.length,
        itemBuilder: (context, index) {
          final notification = _notifications[index];
          final sender = notification['sender'];
          final isRead = notification['is_read'] as bool;
          final createdAt = notification['created_at'] as DateTime;
          final formattedDate = DateFormat.yMMMd().add_jm().format(createdAt);

          return ListTile(
            leading: CircleAvatar(
              backgroundImage: sender['profile_image_url'].isNotEmpty
                  ? NetworkImage(sender['profile_image_url'])
                  : null,
              child: sender['profile_image_url'].isEmpty
                  ? Text(sender['full_name'][0])
                  : null,
            ),
            title: Text(
              sender['full_name'],
              style: TextStyle(
                  fontWeight: isRead ? FontWeight.normal : FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(notification['message'],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight:
                            isRead ? FontWeight.normal : FontWeight.bold)),
                Text(formattedDate,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isRead)
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        shape: BoxShape.circle),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteNotification(notification['id']),
                ),
              ],
            ),
            onTap: () {
              _markAsRead(notification['id']);
              _navigateToChatScreen(notification['chat_room_id'], sender);
            },
          );
        },
      ),
    );
  }

  Widget _buildPostNotifications() {
    if (_isPostNotificationsLoading)
      return const Center(child: CircularProgressIndicator());
    if (_postNotifications.isEmpty)
      return const Center(child: Text('No post notifications'));

    return RefreshIndicator(
      onRefresh: _loadPostNotifications,
      child: ListView.builder(
        itemCount: _postNotifications.length,
        itemBuilder: (context, index) {
          final n = _postNotifications[index];
          final isRead = n['is_read'] as bool;
          final createdAt = DateTime.parse(n['created_at']);
          final formattedDate = DateFormat.yMMMd().add_jm().format(createdAt);

          return ListTile(
            leading: CircleAvatar(
              child: Icon(n['post_type'] == 'business'
                  ? Icons.business
                  : Icons.person),
            ),
            title: Text(
              '${n['sender_name']} made a new post',
              style: TextStyle(
                  fontWeight: isRead ? FontWeight.normal : FontWeight.bold),
            ),
            subtitle: Text(formattedDate,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isRead)
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deletePostNotification(n['id']),
                ),
              ],
            ),
            onTap: () => _onPostNotificationTap(n),
          );
        },
      ),
    );
  }
}