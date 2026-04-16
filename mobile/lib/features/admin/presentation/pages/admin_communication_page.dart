import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/api_service.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../communication/presentation/widgets/message_compose_modal.dart';
import '../widgets/admin_bottom_nav.dart';

class AdminCommunicationPage extends ConsumerStatefulWidget {
  const AdminCommunicationPage({super.key});

  @override
  ConsumerState<AdminCommunicationPage> createState() =>
      _AdminCommunicationPageState();
}

class _AdminCommunicationPageState
    extends ConsumerState<AdminCommunicationPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _announcements = [];
  List<dynamic> _messages = [];
  List<dynamic> _notifications = [];
  List<dynamic> _schools = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _messageFilter = 'received';
  String _announcementFilter = 'all';
  String? _selectedSchoolId;
  final _interSchoolSubjectController = TextEditingController();
  final _interSchoolMessageController = TextEditingController();
  bool _sendingInterSchool = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _interSchoolSubjectController.dispose();
    _interSchoolMessageController.dispose();
    super.dispose();
  }

  List<dynamic> _list(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['results'] is List) return data['results'] as List;
    return [];
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiService().get('/api/communication/announcements/', useCache: false),
        ApiService().get('/api/communication/messages/', useCache: false),
        ApiService().get('/api/communication/notifications/', useCache: false),
        ApiService().get('/api/schools/all-for-transfer/', useCache: false),
      ]);
      if (!mounted) return;
      setState(() {
        _announcements = _list(results[0].data);
        _messages = _list(results[1].data);
        _notifications = _list(results[2].data);
        _schools = _list(results[3].data);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markAllNotificationsRead() async {
    try {
      await ApiService().post('/api/communication/notifications/mark_all_read/');
      await _load();
    } catch (_) {}
  }

  Future<void> _markNotificationRead(dynamic notification) async {
    if (notification['is_read'] == true || notification['id'] == null) return;
    try {
      await ApiService().post(
        '/api/communication/notifications/${notification['id']}/mark_read/',
      );
      await _load();
    } catch (_) {}
  }

  Future<void> _markMessageRead(dynamic message) async {
    if (message['is_read'] == true || message['id'] == null) return;
    try {
      await ApiService().post(
        '/api/communication/messages/${message['id']}/mark_read/',
      );
      await _load();
    } catch (_) {}
  }

  Future<void> _sendInterSchool() async {
    if (_selectedSchoolId == null ||
        _interSchoolSubjectController.text.trim().isEmpty ||
        _interSchoolMessageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complétez école, sujet et message.')),
      );
      return;
    }
    setState(() => _sendingInterSchool = true);
    try {
      await ApiService().post(
        '/api/communication/messages/inter-school/',
        data: {
          'target_school': _selectedSchoolId,
          'subject': _interSchoolSubjectController.text.trim(),
          'message': _interSchoolMessageController.text.trim(),
        },
      );
      if (!mounted) return;
      _interSchoolSubjectController.clear();
      _interSchoolMessageController.clear();
      setState(() => _selectedSchoolId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message inter-école envoyé')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.parseDioError(e))),
      );
    } finally {
      if (mounted) setState(() => _sendingInterSchool = false);
    }
  }

  List<dynamic> get _filteredAnnouncements {
    return _announcements.where((item) {
      final title = '${item['title'] ?? ''}'.toLowerCase();
      final message = '${item['message'] ?? ''}'.toLowerCase();
      final q = _searchQuery.toLowerCase();
      final matchesSearch =
          q.isEmpty || title.contains(q) || message.contains(q);
      final published = item['is_published'] == true;
      final matchesFilter = _announcementFilter == 'all' ||
          (_announcementFilter == 'published' && published) ||
          (_announcementFilter == 'draft' && !published);
      return matchesSearch && matchesFilter;
    }).toList();
  }

  List<dynamic> get _filteredMessages {
    final userId = ref.read(authProvider).user?.id;
    return _messages.where((item) {
      final subject = '${item['subject'] ?? ''}'.toLowerCase();
      final message = '${item['message'] ?? ''}'.toLowerCase();
      final q = _searchQuery.toLowerCase();
      final matchesSearch =
          q.isEmpty || subject.contains(q) || message.contains(q);
      final matchesFilter = _messageFilter == 'all' ||
          (_messageFilter == 'sent' && item['sender'] == userId) ||
          (_messageFilter == 'received' && item['recipient'] == userId);
      return matchesSearch && matchesFilter;
    }).toList();
  }

  List<dynamic> get _filteredNotifications {
    return _notifications.where((item) {
      final title = '${item['title'] ?? ''}'.toLowerCase();
      final message = '${item['message'] ?? ''}'.toLowerCase();
      final q = _searchQuery.toLowerCase();
      return q.isEmpty || title.contains(q) || message.contains(q);
    }).toList();
  }

  String _fmtDate(dynamic raw, {bool withTime = false}) {
    try {
      if (raw == null) return '—';
      final date = DateTime.parse(raw.toString());
      return DateFormat(withTime ? 'dd/MM/yyyy HH:mm' : 'dd/MM/yyyy')
          .format(date);
    } catch (_) {
      return '—';
    }
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        decoration: const InputDecoration(
          hintText: 'Rechercher...',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }

  Widget _filterRow() {
    final tab = _tabController.index;
    if (tab == 0) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('Toutes'),
              selected: _announcementFilter == 'all',
              onSelected: (_) => setState(() => _announcementFilter = 'all'),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Publiées'),
              selected: _announcementFilter == 'published',
              onSelected: (_) =>
                  setState(() => _announcementFilter = 'published'),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Brouillons'),
              selected: _announcementFilter == 'draft',
              onSelected: (_) => setState(() => _announcementFilter = 'draft'),
            ),
          ],
        ),
      );
    }
    if (tab == 1) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('Reçus'),
              selected: _messageFilter == 'received',
              onSelected: (_) => setState(() => _messageFilter = 'received'),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Envoyés'),
              selected: _messageFilter == 'sent',
              onSelected: (_) => setState(() => _messageFilter = 'sent'),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Tous'),
              selected: _messageFilter == 'all',
              onSelected: (_) => setState(() => _messageFilter = 'all'),
            ),
          ],
        ),
      );
    }
    if (tab == 2 && _notifications.any((n) => n['is_read'] != true)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FilledButton.icon(
          onPressed: _markAllNotificationsRead,
          icon: const Icon(Icons.done_all),
          label: const Text('Marquer tout comme lu'),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _announcementsTab() {
    if (_filteredAnnouncements.isEmpty) {
      return const Center(child: Text('Aucune annonce'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: _filteredAnnouncements.length,
        itemBuilder: (context, index) {
          final item = _filteredAnnouncements[index];
          final published = item['is_published'] == true;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    published ? Colors.green.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
                child: Icon(
                  Icons.campaign,
                  color: published ? Colors.green : Colors.orange,
                ),
              ),
              title: Text('${item['title'] ?? 'Annonce'}'),
              subtitle: Text(
                '${item['message'] ?? ''}\nAudience: ${item['target_audience'] ?? 'ALL'} • ${published ? 'Publiée' : 'Brouillon'} • ${_fmtDate(item['published_at'] ?? item['created_at'])}',
              ),
              isThreeLine: true,
            ),
          );
        },
      ),
    );
  }

  Widget _messagesTab() {
    if (_filteredMessages.isEmpty) {
      return const Center(child: Text('Aucun message'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: _filteredMessages.length,
        itemBuilder: (context, index) {
          final item = _filteredMessages[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: item['is_read'] == true
                    ? Colors.grey.withValues(alpha: 0.15)
                    : Colors.blue.withValues(alpha: 0.15),
                child: Icon(
                  item['is_read'] == true ? Icons.mail_outline : Icons.mark_email_unread,
                  color: item['is_read'] == true ? Colors.grey : Colors.blue,
                ),
              ),
              title: Text('${item['subject'] ?? 'Sans objet'}'),
              subtitle: Text(
                'De: ${item['sender_name'] ?? '-'} • À: ${item['recipient_name'] ?? '-'}\n${item['message'] ?? ''}\n${_fmtDate(item['created_at'], withTime: true)}',
              ),
              isThreeLine: true,
              onTap: () => _markMessageRead(item),
            ),
          );
        },
      ),
    );
  }

  Widget _notificationsTab() {
    if (_filteredNotifications.isEmpty) {
      return const Center(child: Text('Aucune notification'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: _filteredNotifications.length,
        itemBuilder: (context, index) {
          final item = _filteredNotifications[index];
          final read = item['is_read'] == true;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    read ? Colors.grey.withValues(alpha: 0.15) : Colors.amber.withValues(alpha: 0.15),
                child: Icon(
                  read ? Icons.notifications_none : Icons.notifications_active,
                  color: read ? Colors.grey : Colors.amber.shade800,
                ),
              ),
              title: Text('${item['title'] ?? item['notification_type'] ?? 'Notification'}'),
              subtitle: Text(
                '${item['message'] ?? ''}\n${_fmtDate(item['created_at'], withTime: true)}',
              ),
              isThreeLine: true,
              onTap: () => _markNotificationRead(item),
            ),
          );
        },
      ),
    );
  }

  Widget _interSchoolTab() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedSchoolId,
            decoration: const InputDecoration(labelText: 'École cible'),
            items: _schools
                .map(
                  (school) => DropdownMenuItem<String>(
                    value: '${school['id']}',
                    child: Text('${school['name'] ?? 'École'}'),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _selectedSchoolId = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _interSchoolSubjectController,
            decoration: const InputDecoration(labelText: 'Sujet'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _interSchoolMessageController,
            minLines: 4,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Message'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _sendingInterSchool ? null : _sendInterSchool,
            icon: _sendingInterSchool
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: const Text('Envoyer à l’école'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final unreadMessagesCount = user == null
        ? 0
        : _messages
            .where((m) => m['recipient'] == user.id && m['is_read'] != true)
            .length;
    final unreadNotificationsCount =
        _notifications.where((n) => n['is_read'] != true).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Communication'),
        actions: [
          if (_tabController.index == 1)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => const MessageComposeModal(),
                );
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          onTap: (_) => setState(() {}),
          isScrollable: true,
          tabs: [
            const Tab(text: 'Annonces', icon: Icon(Icons.campaign)),
            Tab(
              text: 'Messages',
              icon: Badge(
                isLabelVisible: unreadMessagesCount > 0,
                label: Text('$unreadMessagesCount'),
                child: const Icon(Icons.mail_outline),
              ),
            ),
            Tab(
              text: 'Notifications',
              icon: Badge(
                isLabelVisible: unreadNotificationsCount > 0,
                label: Text('$unreadNotificationsCount'),
                child: const Icon(Icons.notifications_none),
              ),
            ),
            const Tab(text: 'Inter-école', icon: Icon(Icons.school_outlined)),
          ],
        ),
      ),
      body: Column(
        children: [
          _searchBar(),
          _filterRow(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _announcementsTab(),
                      _messagesTab(),
                      _notificationsTab(),
                      _interSchoolTab(),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: const AdminBottomNav(),
    );
  }
}

