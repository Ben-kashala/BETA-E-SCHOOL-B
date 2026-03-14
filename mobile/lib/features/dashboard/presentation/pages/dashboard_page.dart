import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/network/api_service.dart';
import '../../../parent/presentation/widgets/progress_charts_widget.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  List<dynamic> _childrenDashboard = [];
  Map<int, Map<String, dynamic>> _childrenDetails = {};
  bool _childrenLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChildrenIfParent();
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

      // Charger les détails pour chaque enfant (notes, présences)
      final detailsMap = <int, Map<String, dynamic>>{};
      for (var item in list) {
        final identity = item is Map
            ? (item['identity'] as Map?) ?? item
            : <String, dynamic>{};
        final studentId = identity['id'];
        if (studentId != null) {
          try {
            // Charger les notes
            final gradesResponse = await api.get(
              '/api/academics/grades/',
              queryParameters: {'student': studentId.toString()},
            );
            final grades = gradesResponse.data is List
                ? gradesResponse.data
                : (gradesResponse.data['results'] ?? []);

            detailsMap[studentId] = {
              'grades': grades,
              'attendance_by_week': item['attendance_by_week'] ?? [],
              'average_score': item['average_score'],
            };
          } catch (e) {
            // Ignore errors for individual children
          }
        }
      }

      if (mounted) {
        setState(() {
          _childrenDashboard = List<dynamic>.from(list);
          _childrenDetails = detailsMap;
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
        title: const Text('Tableau de bord'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push('/communication'),
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
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Bienvenue
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bonjour,',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?.fullName ??
                            (isStudent
                                ? 'Élève'
                                : isParent
                                    ? 'Parent'
                                    : isTeacher
                                        ? 'Enseignant'
                                        : isAdmin
                                            ? 'Administrateur'
                                            : isAccountant
                                                ? 'Comptable'
                                                : isDisciplineOfficer
                                                    ? 'Chargé de discipline'
                                                    : isPromoter
                                                        ? 'Promoteur'
                                                        : 'Utilisateur'),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      if (isStudent && user?.studentId != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Matricule: ${user!.studentId}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

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
                      title: 'Communication',
                      color: Colors.teal,
                      onTap: () => context.push('/communication'),
                    ),
                  ],
                ),
              ] else if (isParent) ...[
                // Dashboard Parent
                Text(
                  'Mes Enfants',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                if (_childrenLoading)
                  const Center(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator()))
                else if (_childrenDashboard.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Aucun enfant inscrit',
                        style: Theme.of(context).textTheme.bodyMedium,
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
                    final studentId = identity['id'];
                    final details =
                        studentId != null ? _childrenDetails[studentId] : null;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.person),
                            ),
                            title: Text(userName.isEmpty ? 'Enfant' : userName),
                            subtitle:
                                Text(className.isEmpty ? 'Classe' : className),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              if (studentId != null) {
                                context.push('/students/$studentId');
                              }
                            },
                          ),
                          // Graphiques de progression
                          if (details != null)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: ProgressChartsWidget(
                                attendanceData: List<Map<String, dynamic>>.from(
                                    details['attendance_by_week'] ?? []),
                                gradesData: List<Map<String, dynamic>>.from(
                                    details['grades'] ?? []),
                                averageScore:
                                    details['average_score']?.toDouble(),
                              ),
                            ),
                        ],
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
                      icon: Icons.event,
                      title: 'Réunions',
                      color: Colors.green,
                      onTap: () => context.push('/meetings'),
                    ),
                    _DashboardCard(
                      icon: Icons.payment,
                      title: 'Paiements',
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
                      title: 'Communication',
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
                      icon: Icons.class_,
                      title: 'Mes Classes',
                      color: Colors.blue,
                      onTap: () => context.push('/teacher/classes'),
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
                      title: 'Communication',
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
                      title: 'Paiements',
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
                      title: 'Communication',
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
                // Dashboard Comptable
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
                      title: 'Communication',
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
      bottomNavigationBar: _wrapBottomNavSafe(
          context,
          _buildBottomNavigationBar(context, isStudent, isParent, isTeacher,
              isAdmin, isAccountant, isDisciplineOfficer, isPromoter)),
    );
  }

  Widget? _wrapBottomNavSafe(BuildContext context, Widget? child) {
    if (child == null) return null;
    return SafeArea(child: child);
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
              context.push('/meetings');
              break;
            case 3:
              context.push('/payments');
              break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Accueil'),
          NavigationDestination(icon: Icon(Icons.grade), label: 'Notes'),
          NavigationDestination(icon: Icon(Icons.event), label: 'Réunions'),
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
              context.push('/teacher/assignments');
              break;
            case 3:
              context.push('/teacher/grades');
              break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Accueil'),
          NavigationDestination(icon: Icon(Icons.class_), label: 'Classes'),
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
                style: Theme.of(context).textTheme.titleSmall,
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
