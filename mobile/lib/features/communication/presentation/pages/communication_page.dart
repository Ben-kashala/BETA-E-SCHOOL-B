import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/widgets/search_filter_bar.dart';
import '../widgets/message_compose_modal.dart';
import '../../../accountant/presentation/widgets/accountant_bottom_nav.dart';
import '../../../admin/presentation/widgets/admin_bottom_nav.dart';
import '../../../discipline_officer/presentation/widgets/discipline_officer_bottom_nav.dart';

/// Communication — annonces et messages (synchronisé avec le web).
class CommunicationPage extends ConsumerStatefulWidget {
  const CommunicationPage({super.key});

  @override
  ConsumerState<CommunicationPage> createState() => _CommunicationPageState();
}

class _CommunicationPageState extends ConsumerState<CommunicationPage>
    with SingleTickerProviderStateMixin {
  List<dynamic> _announcements = [];
  List<dynamic> _messages = [];
  List<dynamic> _notifications = [];
  List<dynamic> _filteredAnnouncements = [];
  List<dynamic> _filteredMessages = [];
  List<dynamic> _filteredNotifications = [];
  bool _isLoading = true;
  late TabController _tabController;
  String _searchQuery = '';
  int _currentTab = 0;
  String _messageFilter = 'received';
  Map<String, dynamic>? _selectedMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _short(String s, int maxLen) {
    if (s.length <= maxLen) return s;
    return '${s.substring(0, maxLen)}...';
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      final results = await Future.wait([
        api.get<dynamic>('/api/communication/announcements/', useCache: false),
        api.get<dynamic>('/api/communication/messages/', useCache: false),
        api.get<dynamic>('/api/communication/notifications/', useCache: false),
      ]);
      List<dynamic> list(dynamic data) {
        if (data is List) {
          return data;
        }
        if (data is Map && data['results'] != null) {
          return data['results'] as List;
        }
        return [];
      }

      if (mounted) {
        setState(() {
          _announcements = list(results[0].data);
          _messages = list(results[1].data);
          _notifications = list(results[2].data);
          _applyFilters(userId: ref.read(authProvider).user?.id);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _announcements = [];
          _messages = [];
          _notifications = [];
          _isLoading = false;
        });
      }
    }
  }

  void _applyFilters({int? userId}) {
    List<dynamic> baseMessages = _messages;
    if (userId != null) {
      if (_messageFilter == 'received') {
        baseMessages =
            _messages.where((m) => m['recipient'] == userId).toList();
      } else if (_messageFilter == 'sent') {
        baseMessages = _messages.where((m) => m['sender'] == userId).toList();
      }
    }

    setState(() {
      _filteredAnnouncements = _announcements.where((a) {
        if (_searchQuery.isNotEmpty) {
          final title = (a['title'] ?? '').toString().toLowerCase();
          final message = (a['message'] ?? '').toString().toLowerCase();
          return title.contains(_searchQuery.toLowerCase()) ||
              message.contains(_searchQuery.toLowerCase());
        }
        return true;
      }).toList();

      _filteredMessages = baseMessages.where((m) {
        if (_searchQuery.isNotEmpty) {
          final subject = (m['subject'] ?? '').toString().toLowerCase();
          final message = (m['message'] ?? '').toString().toLowerCase();
          return subject.contains(_searchQuery.toLowerCase()) ||
              message.contains(_searchQuery.toLowerCase());
        }
        return true;
      }).toList();

      _filteredNotifications = _notifications.where((n) {
        if (_searchQuery.isNotEmpty) {
          final title = (n['title'] ?? '').toString().toLowerCase();
          final message = (n['message'] ?? '').toString().toLowerCase();
          return title.contains(_searchQuery.toLowerCase()) ||
              message.contains(_searchQuery.toLowerCase());
        }
        return true;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final userId = user?.id;
    final unreadMessagesCount = userId == null
        ? 0
        : _messages
            .where((m) => m['recipient'] == userId && m['is_read'] != true)
            .length;
    final unreadNotificationsCount =
        _notifications.where((n) => n['is_read'] != true).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Communication'),
        actions: [
          if (_currentTab == 1) // Messages tab
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const MessageComposeModal(),
                );
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          onTap: (index) {
            setState(() => _currentTab = index);
          },
          tabs: [
            const Tab(text: 'Annonces', icon: Icon(Icons.campaign)),
            Tab(
              icon: Badge(
                isLabelVisible: unreadMessagesCount > 0,
                label: Text('$unreadMessagesCount'),
                child: const Icon(Icons.mail),
              ),
              text: 'Messages',
            ),
            Tab(
              icon: Badge(
                isLabelVisible: unreadNotificationsCount > 0,
                label: Text('$unreadNotificationsCount'),
                child: const Icon(Icons.notifications),
              ),
              text: 'Notifications',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          SearchFilterBar(
            hintText: 'Rechercher...',
            onSearchChanged: (value) {
              setState(() => _searchQuery = value);
              _applyFilters(userId: userId);
            },
          ),
          if (_currentTab == 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Reçus'),
                    selected: _messageFilter == 'received',
                    onSelected: (_) {
                      _messageFilter = 'received';
                      _applyFilters(userId: userId);
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Envoyés'),
                    selected: _messageFilter == 'sent',
                    onSelected: (_) {
                      _messageFilter = 'sent';
                      _applyFilters(userId: userId);
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Tous'),
                    selected: _messageFilter == 'all',
                    onSelected: (_) {
                      _messageFilter = 'all';
                      _applyFilters(userId: userId);
                    },
                  ),
                ],
              ),
            ),
          if (_currentTab == 2 && unreadNotificationsCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ElevatedButton.icon(
                onPressed: () async {
                  try {
                    await ApiService().post(
                        '/api/communication/notifications/mark_all_read/');
                    await _load();
                  } catch (_) {}
                },
                icon: const Icon(Icons.done_all),
                label: const Text('Marquer tout comme lu'),
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _listView('Annonces', _filteredAnnouncements, (a) {
                        final title =
                            a['title'] ?? a['message'] ?? 'Sans titre';
                        final message = a['message'] ?? a['title'] ?? '';
                        final createdAt = a['created_at'] ?? a['published_at'];
                        return ListTile(
                          title: Text(title.toString()),
                          subtitle: Text(
                              '${message.toString().length > 80 ? '${message.toString().substring(0, 80)}...' : message}\n${createdAt != null ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.tryParse(createdAt.toString()) ?? DateTime.now()) : ''}'),
                          isThreeLine: true,
                        );
                      }),
                      _listView('Messages', _filteredMessages, (m) {
                        final subject = m['subject'] ?? 'Sans objet';
                        final created = m['created_at'];
                        final isUnread = userId != null &&
                            m['recipient'] == userId &&
                            m['is_read'] != true;
                        return ListTile(
                          title: Text(subject.toString()),
                          subtitle: Text(created != null
                              ? DateFormat('dd/MM/yyyy HH:mm').format(
                                  DateTime.tryParse(created.toString()) ??
                                      DateTime.now())
                              : ''),
                          leading: CircleAvatar(
                            child: Icon(m['is_read'] == true
                                ? Icons.drafts
                                : Icons.mail),
                          ),
                          trailing: isUnread
                              ? const Icon(Icons.circle,
                                  color: Colors.blue, size: 10)
                              : null,
                          onTap: () async {
                            if (isUnread && m['id'] != null) {
                              try {
                                await ApiService().post(
                                  '/api/communication/messages/${m['id']}/mark_read/',
                                );
                              } catch (_) {}
                            }
                            if (!mounted) return;
                            setState(() {
                              _selectedMessage =
                                  Map<String, dynamic>.from(m as Map);
                            });
                            await _load();
                          },
                        );
                      }),
                      _listView('Notifications', _filteredNotifications, (n) {
                        final title = n['title'] ??
                            n['notification_type'] ??
                            'Notification';
                        final message = n['message'] ?? '';
                        final createdAt = n['created_at'];
                        return ListTile(
                          leading: CircleAvatar(
                              child: Icon(n['is_read'] == true
                                  ? Icons.notifications_none
                                  : Icons.notifications)),
                          title: Text(title.toString()),
                          subtitle: Text(
                              '${_short(message.toString(), 60)}\n${createdAt != null ? DateFormat('dd/MM/yyyy').format(DateTime.tryParse(createdAt.toString()) ?? DateTime.now()) : ''}'),
                          isThreeLine: true,
                          onTap: () async {
                            if (n['is_read'] != true && n['id'] != null) {
                              try {
                                await ApiService().post(
                                  '/api/communication/notifications/${n['id']}/mark_read/',
                                );
                                await _load();
                              } catch (_) {}
                            }
                          },
                        );
                      }),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: _selectedMessage == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'reply_message_fab',
                  onPressed: () {
                    final msg = _selectedMessage!;
                    final senderId = msg['sender'] as int?;
                    final subject = (msg['subject'] ?? '').toString();
                    final replySubject =
                        subject.toLowerCase().startsWith('re:') ? subject : 'Re: $subject';

                    if (senderId == null) return;

                    showDialog(
                      context: context,
                      builder: (ctx) => MessageComposeModal(
                        initialSubject: replySubject,
                        preselectedRecipientIds: [senderId],
                      ),
                    );
                  },
                  icon: const Icon(Icons.reply),
                  label: const Text('Répondre'),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'close_message_fab',
                  onPressed: () => setState(() => _selectedMessage = null),
                  icon: const Icon(Icons.close),
                  label: const Text('Fermer message'),
                ),
              ],
            ),
      bottomSheet: _selectedMessage == null
          ? null
          : Material(
              elevation: 8,
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 220,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_selectedMessage!['subject'] ?? 'Sans objet'}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'De: ${_selectedMessage!['sender_name'] ?? '-'}  •  À: ${_selectedMessage!['recipient_name'] ?? '-'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            child:
                                Text('${_selectedMessage!['message'] ?? ''}'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      bottomNavigationBar:
          GoRouterState.of(context).uri.path.startsWith('/accountant/')
              ? const AccountantBottomNav()
              : GoRouterState.of(context).uri.path.startsWith('/admin/')
                  ? const AdminBottomNav()
                  : GoRouterState.of(context)
                          .uri
                          .path
                          .startsWith('/discipline-officer/')
                      ? const DisciplineOfficerBottomNav()
                      : null,
    );
  }

  Widget _listView(String emptyLabel, List<dynamic> items,
      Widget Function(dynamic) itemBuilder) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('Aucun $emptyLabel',
                style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: itemBuilder(item),
          );
        },
      ),
    );
  }
}
