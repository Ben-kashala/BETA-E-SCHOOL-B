import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/layout/scroll_content_padding.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/domain/models/user_model.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  List<dynamic> _childrenDashboard = [];
  bool _childrenLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChildrenIfParent();
    // Après remplacement de assets/images/logo.png, évince le cache image (sinon ancienne image jusqu’à redémarrage).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      imageCache.evict(AssetImage('assets/images/logo.png'));
    });
  }

  static int? _parseStudentId(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return num.tryParse(v.toString())?.toInt();
  }

  /// Texte lisible sur cartes (clair ou sombre) alors que le thème global est adapté au fond primaryColor.
  static Widget _cardForegroundTheme(BuildContext context, {required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(
          bodyColor: isDark ? Colors.white : AppTheme.textPrimary,
          displayColor: isDark ? Colors.white : AppTheme.textPrimary,
        ),
      ),
      child: child,
    );
  }

  static String _schoolDisplayName(UserModel? user) {
    final n = user?.schoolName?.trim();
    if (n != null && n.isNotEmpty) return n;
    final c = user?.schoolCode?.trim();
    if (c != null && c.isNotEmpty) return c;
    return 'E-School';
  }

  Future<void> _loadChildrenIfParent() async {
    final user = ref.read(authProvider).user;
    if (user?.isParent != true) return;
    setState(() => _childrenLoading = true);
    try {
      final api = ApiService();
      final response = await api.get(
        '/api/auth/students/parent_dashboard/',
        useCache: false,
      );
      final data = response.data;
      final list = data is List
          ? data
          : (data is Map && data['results'] != null
              ? data['results'] as List
              : <dynamic>[]);

      if (mounted) {
        setState(() {
          _childrenDashboard = List<dynamic>.from(list);
          _childrenLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _childrenDashboard = [];
          _childrenLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isStudent = user?.role == 'STUDENT';
    final isParent = user?.role == 'PARENT';
    final isTeacher = user?.role == 'TEACHER';
    final isAdmin = user?.role == 'ADMIN';
    final isAccountant = user?.role == 'ACCOUNTANT';
    final isDisciplineOfficer = user?.role == 'DISCIPLINE_OFFICER';
    final isPromoter = user?.role == 'PROMOTER';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        toolbarHeight: 52,
        title: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Image.asset(
                'assets/images/logo.png',
                height: 100,
                width: 95,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.school_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 60,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 68),
              child: Text(
                _schoolDisplayName(user),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push(
              isAccountant ? '/accountant/communication' : '/communication',
            ),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () {
              context.push('/profile');
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(authProvider.notifier).refreshUser();
          await _loadChildrenIfParent();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: ScrollContentPadding.page(context, trailing: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Contenu selon le rôle
              if (isStudent) ...[
                // Dashboard Élève
                Text(
                  'Actions rapides',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.05,
                  children: [
                    _DashboardCard(
                      icon: Icons.book,
                      title: 'Mes Cours',
                      color: Colors.blue,
                      onTap: () => context.push('/courses'),
                    ),
                    _DashboardCard(
                      icon: Icons.assignment,
                      title: 'Devoirs',
                      color: Colors.orange,
                      onTap: () => context.push('/assignments'),
                    ),
                    _DashboardCard(
                      icon: Icons.quiz,
                      title: 'Examens',
                      color: Colors.red,
                      onTap: () => context.push('/exams'),
                    ),
                    _DashboardCard(
                      icon: Icons.library_books,
                      title: 'Bibliothèque',
                      color: Colors.green,
                      onTap: () => context.push('/library'),
                    ),
                    _DashboardCard(
                      icon: Icons.grade,
                      title: 'Notes',
                      color: Colors.purple,
                      onTap: () => context.push('/grades'),
                    ),
                    _DashboardCard(
                      icon: Icons.gavel,
                      title: 'Discipline',
                      color: Colors.brown,
                      onTap: () => context.push('/discipline'),
                    ),
                    _DashboardCard(
                      icon: Icons.message,
                      title: 'Envoyer un message',
                      color: Colors.teal,
                      onTap: () => context.push('/communication'),
                    ),
                  ],
                ),
              ] else if (isParent) ...[
                // Dashboard Parent
                Text(
                  'Mes Enfants',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                if (_childrenLoading)
                  const Center(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                          )))
                else if (_childrenDashboard.isEmpty)
                  Card(
                    child: _cardForegroundTheme(
                      context,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Aucun enfant inscrit',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  )
                else
                  ...(_childrenDashboard.map<Widget>((item) {
                    final identity = item is Map
                        ? (item['identity'] as Map?) ?? item
                        : <String, dynamic>{};
                    final userData = identity['user'];
                    final userName = userData is Map
                        ? '${userData['first_name'] ?? ''} ${userData['last_name'] ?? ''} ${userData['middle_name'] ?? ''}'
                            .trim()
                        : (identity['user_name'] as String? ?? '');
                    final className = identity['class_name'] as String? ??
                        identity['school_class_academic_year'] as String? ??
                        '';
                    final studentId = _parseStudentId(identity['id']);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 20),
                      clipBehavior: Clip.antiAlias,
                      child: _cardForegroundTheme(
                        context,
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: () {
                              if (studentId != null) {
                                context.push('/students/${studentId.toString()}');
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 28,
                                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                    child: Icon(
                                      Icons.person,
                                      size: 32,
                                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          userName.isEmpty ? 'Enfant' : userName,
                                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          className.isEmpty ? 'Classe' : className,
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Voir le détail',
                                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                            color: Theme.of(context).colorScheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      ),
                    );
                  })),
                const SizedBox(height: 24),
                // Modules alignés avec le web (ordre = sidebar parent)
                Text(
                  'Modules',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.05,
                  children: [
                    _DashboardCard(
                      icon: Icons.grade,
                      title: 'Notes',
                      color: Colors.orange,
                      onTap: () => context.push('/grades'),
                    ),
                    _DashboardCard(
                      icon: Icons.how_to_reg,
                      title: 'Présences',
                      color: Colors.green,
                      onTap: () => context.push('/presences'),
                    ),
                    _DashboardCard(
                      icon: Icons.event,
                      title: 'Réunions',
                      color: Colors.deepOrange,
                      onTap: () => context.push('/meetings'),
                    ),
                    _DashboardCard(
                      icon: Icons.payment,
                      title: 'Payer',
                      color: Colors.purple,
                      onTap: () => context.push('/payments'),
                    ),
                    _DashboardCard(
                      icon: Icons.library_books,
                      title: 'Bibliothèque',
                      color: Colors.indigo,
                      onTap: () => context.push('/library'),
                    ),
                    _DashboardCard(
                      icon: Icons.school,
                      title: 'Encadrement',
                      color: Colors.teal,
                      onTap: () => context.push('/tutoring'),
                    ),
                    _DashboardCard(
                      icon: Icons.gavel,
                      title: 'Discipline',
                      color: Colors.brown,
                      onTap: () => context.push('/discipline'),
                    ),
                    _DashboardCard(
                      icon: Icons.message,
                      title: 'Envoyer un message',
                      color: Colors.cyan,
                      onTap: () => context.push('/communication'),
                    ),
                    _DashboardCard(
                      icon: Icons.person_add,
                      title: 'Inscription',
                      color: Colors.blue,
                      onTap: () => context.push('/enrollment'),
                    ),
                  ],
                ),
              ] else if (isTeacher) ...[
                // Dashboard Enseignant
                Text(
                  'Actions rapides',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.05,
                  children: [
                    _DashboardCard(
                      icon: Icons.groups_2,
                      title: 'Ma classe (Titulariat)',
                      color: Colors.indigo,
                      onTap: () => context.push('/teacher/my-class'),
                    ),
                    _DashboardCard(
                      icon: Icons.class_,
                      title: 'Classes',
                      color: Colors.blue,
                      onTap: () => context.push('/teacher/classes'),
                    ),
                    _DashboardCard(
                      icon: Icons.menu_book,
                      title: 'Matières par classe',
                      color: Colors.deepPurple,
                      onTap: () => context.push('/teacher/class-subjects'),
                    ),
                    _DashboardCard(
                      icon: Icons.people,
                      title: 'Élèves',
                      color: Colors.green,
                      onTap: () => context.push('/teacher/students'),
                    ),
                    _DashboardCard(
                      icon: Icons.assignment,
                      title: 'Devoirs',
                      color: Colors.orange,
                      onTap: () => context.push('/teacher/assignments'),
                    ),
                    _DashboardCard(
                      icon: Icons.quiz,
                      title: 'Quiz/Examens',
                      color: Colors.red,
                      onTap: () => context.push('/teacher/quizzes'),
                    ),
                    _DashboardCard(
                      icon: Icons.book,
                      title: 'Cours',
                      color: Colors.green,
                      onTap: () => context.push('/teacher/courses'),
                    ),
                    _DashboardCard(
                      icon: Icons.grade,
                      title: 'Notes',
                      color: Colors.purple,
                      onTap: () => context.push('/teacher/grades'),
                    ),
                    _DashboardCard(
                      icon: Icons.check_circle,
                      title: 'Présences',
                      color: Colors.teal,
                      onTap: () => context.push('/teacher/attendance'),
                    ),
                    _DashboardCard(
                      icon: Icons.gavel,
                      title: 'Discipline',
                      color: Colors.brown,
                      onTap: () => context.push('/teacher/discipline'),
                    ),
                    _DashboardCard(
                      icon: Icons.school,
                      title: 'Encadrement',
                      color: Colors.indigo,
                      onTap: () => context.push('/teacher/tutoring'),
                    ),
                    _DashboardCard(
                      icon: Icons.library_books,
                      title: 'Bibliothèque',
                      color: Colors.lightGreen,
                      onTap: () => context.push('/teacher/library'),
                    ),
                    _DashboardCard(
                      icon: Icons.event,
                      title: 'Réunions',
                      color: Colors.deepOrange,
                      onTap: () => context.push('/teacher/meetings'),
                    ),
                    _DashboardCard(
                      icon: Icons.message,
                      title: 'Envoyer un message',
                      color: Colors.cyan,
                      onTap: () => context.push('/teacher/communication'),
                    ),
                    _DashboardCard(
                      icon: Icons.cast_for_education,
                      title: 'E-learning',
                      color: Colors.teal,
                      onTap: () => context.push('/teacher/elearning'),
                    ),
                  ],
                ),
              ] else if (isAdmin) ...[
                // Dashboard Admin
                Text(
                  'Actions rapides',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.05,
                  children: [
                    _DashboardCard(
                      icon: Icons.person_add,
                      title: 'Inscriptions',
                      color: Colors.blue,
                      onTap: () => context.push('/admin/enrollments'),
                    ),
                    _DashboardCard(
                      icon: Icons.people,
                      title: 'Élèves',
                      color: Colors.green,
                      onTap: () => context.push('/admin/students'),
                    ),
                    _DashboardCard(
                      icon: Icons.class_,
                      title: 'Classes',
                      color: Colors.orange,
                      onTap: () => context.push('/admin/classes'),
                    ),
                    _DashboardCard(
                      icon: Icons.person,
                      title: 'Enseignants',
                      color: Colors.purple,
                      onTap: () => context.push('/admin/teachers'),
                    ),
                    _DashboardCard(
                      icon: Icons.payment,
                      title: 'Payer',
                      color: Colors.teal,
                      onTap: () => context.push('/admin/payments'),
                    ),
                    _DashboardCard(
                      icon: Icons.library_books,
                      title: 'Bibliothèque',
                      color: Colors.indigo,
                      onTap: () => context.push('/admin/library'),
                    ),
                    _DashboardCard(
                      icon: Icons.gavel,
                      title: 'Discipline',
                      color: Colors.brown,
                      onTap: () => context.push('/admin/discipline'),
                    ),
                    _DashboardCard(
                      icon: Icons.message,
                      title: 'Envoyer un message',
                      color: Colors.cyan,
                      onTap: () => context.push('/admin/communication'),
                    ),
                    _DashboardCard(
                      icon: Icons.event,
                      title: 'Réunions',
                      color: Colors.deepOrange,
                      onTap: () => context.push('/admin/meetings'),
                    ),
                    _DashboardCard(
                      icon: Icons.school,
                      title: 'Encadrement',
                      color: Colors.lightBlue,
                      onTap: () => context.push('/admin/tutoring'),
                    ),
                    _DashboardCard(
                      icon: Icons.money_off,
                      title: 'Dépenses',
                      color: Colors.red,
                      onTap: () => context.push('/admin/expenses'),
                    ),
                    _DashboardCard(
                      icon: Icons.account_balance_wallet,
                      title: 'Caisse',
                      color: Colors.amber,
                      onTap: () => context.push('/admin/caisse'),
                    ),
                    _DashboardCard(
                      icon: Icons.cast_for_education,
                      title: 'E-learning',
                      color: Colors.teal,
                      onTap: () => context.push('/admin/elearning'),
                    ),
                    _DashboardCard(
                      icon: Icons.history_edu,
                      title: 'Anciens élèves',
                      color: Colors.blueGrey,
                      onTap: () => context.push('/admin/former-students'),
                    ),
                  ],
                ),
              ] else if (isAccountant) ...[
                // Dashboard Comptable (aligné menu web : TDB, Inscriptions, Paiements, Dépenses, Caisse)
                Text(
                  'Actions rapides',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.05,
                  children: [
                    _DashboardCard(
                      icon: Icons.dashboard,
                      title: 'Tableau de bord',
                      color: Colors.indigo,
                      onTap: () => context.push('/accountant'),
                    ),
                    _DashboardCard(
                      icon: Icons.person_add,
                      title: 'Inscriptions',
                      color: Colors.blue,
                      onTap: () => context.push('/accountant/enrollments'),
                    ),
                    _DashboardCard(
                      icon: Icons.payment,
                      title: 'Paiements',
                      color: Colors.green,
                      onTap: () => context.push('/accountant/payments'),
                    ),
                    _DashboardCard(
                      icon: Icons.money_off,
                      title: 'Dépenses',
                      color: Colors.red,
                      onTap: () => context.push('/accountant/expenses'),
                    ),
                    _DashboardCard(
                      icon: Icons.account_balance_wallet,
                      title: 'Caisse',
                      color: Colors.orange,
                      onTap: () => context.push('/accountant/caisse'),
                    ),
                    _DashboardCard(
                      icon: Icons.message,
                      title: 'Communication',
                      color: Colors.teal,
                      onTap: () => context.push('/accountant/communication'),
                    ),
                  ],
                ),
              ] else if (isDisciplineOfficer) ...[
                // Dashboard Chargé de discipline
                Text(
                  'Actions rapides',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.05,
                  children: [
                    _DashboardCard(
                      icon: Icons.gavel,
                      title: 'Discipline',
                      color: Colors.brown,
                      onTap: () =>
                          context.push('/discipline-officer/discipline'),
                    ),
                    _DashboardCard(
                      icon: Icons.event,
                      title: 'Réunions',
                      color: Colors.green,
                      onTap: () => context.push('/discipline-officer/meetings'),
                    ),
                    _DashboardCard(
                      icon: Icons.message,
                      title: 'Envoyer un message',
                      color: Colors.cyan,
                      onTap: () =>
                          context.push('/discipline-officer/communication'),
                    ),
                  ],
                ),
              ] else if (isPromoter) ...[
                // Dashboard Promoteur
                Text(
                  'Actions rapides',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.05,
                  children: [
                    _DashboardCard(
                      icon: Icons.dashboard,
                      title: 'Tableau de bord',
                      color: Colors.blue,
                      onTap: () => context.push('/promoter'),
                    ),
                    _DashboardCard(
                      icon: Icons.school,
                      title: 'Mes écoles',
                      color: Colors.green,
                      onTap: () => context.push('/promoter/schools'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(context, isStudent, isParent,
          isTeacher, isAdmin, isAccountant, isDisciplineOfficer, isPromoter),
    );
  }

  Widget? _buildBottomNavigationBar(
      BuildContext context,
      bool isStudent,
      bool isParent,
      bool isTeacher,
      bool isAdmin,
      bool isAccountant,
      bool isDisciplineOfficer,
      bool isPromoter) {
    if (isStudent) {
      return NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go('/dashboard');
              break;
            case 1:
              context.push('/courses');
              break;
            case 2:
              context.push('/assignments');
              break;
            case 3:
              context.push('/library');
              break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Accueil'),
          NavigationDestination(icon: Icon(Icons.book), label: 'Cours'),
          NavigationDestination(icon: Icon(Icons.assignment), label: 'Devoirs'),
          NavigationDestination(
              icon: Icon(Icons.library_books), label: 'Bibliothèque'),
        ],
      );
    } else if (isParent) {
      return NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go('/dashboard');
              break;
            case 1:
              context.push('/grades');
              break;
            case 2:
              context.push('/presences');
              break;
            case 3:
              context.push('/payments');
              break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Accueil'),
          NavigationDestination(icon: Icon(Icons.grade), label: 'Notes'),
          NavigationDestination(
              icon: Icon(Icons.how_to_reg), label: 'Présences'),
          NavigationDestination(icon: Icon(Icons.payment), label: 'Paiements'),
        ],
      );
    } else if (isTeacher) {
      return NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go('/dashboard');
              break;
            case 1:
              context.push('/teacher/classes');
              break;
            case 2:
              context.push('/teacher/students');
              break;
            case 3:
              context.push('/teacher/assignments');
              break;
            case 4:
              context.push('/teacher/grades');
              break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Accueil'),
          NavigationDestination(icon: Icon(Icons.class_), label: 'Classes'),
          NavigationDestination(icon: Icon(Icons.people), label: 'Élèves'),
          NavigationDestination(icon: Icon(Icons.assignment), label: 'Devoirs'),
          NavigationDestination(icon: Icon(Icons.grade), label: 'Notes'),
        ],
      );
    } else if (isAdmin) {
      return NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go('/dashboard');
              break;
            case 1:
              context.push('/admin/enrollments');
              break;
            case 2:
              context.push('/admin/students');
              break;
            case 3:
              context.push('/admin/classes');
              break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Accueil'),
          NavigationDestination(
              icon: Icon(Icons.person_add), label: 'Inscriptions'),
          NavigationDestination(icon: Icon(Icons.people), label: 'Élèves'),
          NavigationDestination(icon: Icon(Icons.class_), label: 'Classes'),
        ],
      );
    } else if (isAccountant) {
      return NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go('/dashboard');
              break;
            case 1:
              context.push('/accountant/payments');
              break;
            case 2:
              context.push('/accountant/expenses');
              break;
            case 3:
              context.push('/accountant/caisse');
              break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Accueil'),
          NavigationDestination(icon: Icon(Icons.payment), label: 'Paiements'),
          NavigationDestination(icon: Icon(Icons.money_off), label: 'Dépenses'),
          NavigationDestination(
              icon: Icon(Icons.account_balance_wallet), label: 'Caisse'),
        ],
      );
    } else if (isDisciplineOfficer) {
      return NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go('/dashboard');
              break;
            case 1:
              context.push('/discipline-officer/discipline');
              break;
            case 2:
              context.push('/discipline-officer/meetings');
              break;
            case 3:
              context.push('/discipline-officer/communication');
              break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Accueil'),
          NavigationDestination(icon: Icon(Icons.gavel), label: 'Discipline'),
          NavigationDestination(icon: Icon(Icons.event), label: 'Réunions'),
          NavigationDestination(icon: Icon(Icons.message), label: 'Communication'),
        ],
      );
    } else if (isPromoter) {
      return NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go('/dashboard');
              break;
            case 1:
              context.push('/promoter');
              break;
            case 2:
              context.push('/promoter/schools');
              break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Accueil'),
          NavigationDestination(
              icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.school), label: 'Écoles'),
        ],
      );
    }
    return null;
  }
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardTheme.color ??
        Theme.of(context).colorScheme.surface;
    final useLightText = ThemeData.estimateBrightnessForColor(cardColor) ==
        Brightness.dark;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 6),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color:
                          useLightText ? Colors.white : AppTheme.textPrimary,
                    ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
