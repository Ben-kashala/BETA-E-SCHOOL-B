import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/splash_page.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/courses/presentation/pages/courses_page.dart';
import '../../features/courses/presentation/pages/course_detail_page.dart';
import '../../features/assignments/presentation/pages/assignments_page.dart';
import '../../features/assignments/presentation/pages/assignment_detail_page.dart';
import '../../features/exams/presentation/pages/exams_page.dart';
import '../../features/exams/presentation/pages/exam_detail_page.dart';
import '../../features/exams/presentation/pages/quiz_take_page.dart';
import '../../features/library/presentation/pages/library_page.dart';
import '../../features/library/presentation/pages/book_detail_page.dart';
import '../../features/library/presentation/pages/book_reader_page.dart';
import '../../features/grades/presentation/pages/grades_page.dart';
import '../../features/enrollment/presentation/pages/enrollment_page.dart';
import '../../features/meetings/presentation/pages/meetings_page.dart';
import '../../features/parent/presentation/pages/parent_presence_page.dart';
import '../../features/payments/presentation/pages/payments_page.dart';
import '../../features/payments/presentation/pages/payment_receipt_page.dart';
import '../../features/tutoring/presentation/pages/tutoring_page.dart';
import '../../features/discipline/presentation/pages/discipline_page.dart';
import '../../features/communication/presentation/pages/communication_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/preferences/presentation/pages/preferences_page.dart';
import '../../features/teacher/presentation/pages/teacher_classes_page.dart';
import '../../features/teacher/presentation/pages/teacher_assignments_page.dart';
import '../../features/teacher/presentation/pages/teacher_assignment_detail_page.dart';
import '../../features/teacher/presentation/pages/teacher_attendance_page.dart';
import '../../features/teacher/presentation/pages/teacher_grades_page.dart';
import '../../features/teacher/presentation/pages/teacher_quizzes_page.dart';
import '../../features/teacher/presentation/pages/teacher_quiz_detail_page.dart';
import '../../features/teacher/presentation/pages/teacher_courses_page.dart';
import '../../features/teacher/presentation/pages/teacher_course_form_page.dart';
import '../../features/teacher/presentation/pages/teacher_quiz_create_page.dart';
import '../../features/teacher/presentation/pages/teacher_my_class_page.dart';
import '../../features/teacher/presentation/pages/teacher_class_subjects_page.dart';
import '../../features/teacher/presentation/pages/teacher_students_page.dart';
import '../../features/admin/presentation/pages/admin_enrollments_page.dart';
import '../../features/admin/presentation/pages/admin_students_page.dart';
import '../../features/admin/presentation/pages/admin_classes_page.dart';
import '../../features/admin/presentation/pages/admin_class_detail_page.dart';
import '../../features/admin/presentation/pages/admin_payments_page.dart';
import '../../features/admin/presentation/pages/admin_communication_page.dart';
import '../../features/admin/presentation/pages/admin_teachers_page.dart';
import '../../features/admin/presentation/pages/admin_former_students_page.dart';
import '../../features/admin/presentation/pages/admin_elearning_page.dart';
import '../../features/accountant/presentation/pages/accountant_dashboard_page.dart';
import '../../features/accountant/presentation/pages/accountant_expenses_page.dart';
import '../../features/accountant/presentation/pages/accountant_caisse_page.dart';
import '../../features/accountant/presentation/pages/accountant_payments_page.dart';
import '../../features/students/presentation/pages/student_detail_page.dart';
import '../../features/promoter/presentation/pages/promoter_dashboard_page.dart';
import '../../features/promoter/presentation/pages/promoter_schools_page.dart';
import '../providers/auth_provider.dart';

/// Clé utilisée pour la navigation depuis les notifications (hors build).
final globalNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    navigatorKey: globalNavigatorKey,
    initialLocation: '/splash',
    redirect: (context, state) {
      final isAuthenticated = authState.isAuthenticated;
      final isLoggingIn = state.matchedLocation == '/login';
      final user = authState.user;
      final userRole = user?.role;

      // Redirection si non authentifié
      if (!isAuthenticated && !isLoggingIn) {
        return '/login';
      }

      // Redirection si authentifié et sur la page de login
      if (isAuthenticated && isLoggingIn) {
        return '/dashboard';
      }

      // Vérification des routes selon le rôle
      if (isAuthenticated && userRole != null) {
        final path = state.matchedLocation;

        // Élève : pas d'accès inscription, réunions, paiements, encadrement (réservés aux parents)
        if (userRole == 'STUDENT') {
          if (path.startsWith('/enrollment') ||
              path.startsWith('/meetings') ||
              path.startsWith('/payments') ||
              path.startsWith('/tutoring') ||
              path.startsWith('/teacher') ||
              path.startsWith('/admin') ||
              path.startsWith('/accountant') ||
              path.startsWith('/discipline-officer') ||
              path.startsWith('/promoter')) {
            return '/dashboard';
          }
        }
        // Parent : pas d'accès cours, devoirs, examens (réservés aux élèves)
        if (userRole == 'PARENT') {
          if (path.startsWith('/courses') ||
              path.startsWith('/assignments') ||
              path.startsWith('/exams') ||
              path.startsWith('/teacher') ||
              path.startsWith('/admin') ||
              path.startsWith('/accountant') ||
              path.startsWith('/discipline-officer') ||
              path.startsWith('/promoter')) {
            return '/dashboard';
          }
        }
        // Enseignant : parcours dédié /teacher/* (évite notes, biblio, etc. « parent/élève »)
        if (userRole == 'TEACHER') {
          if (path.startsWith('/grades')) {
            return '/teacher/grades';
          }
          if (path.startsWith('/library')) {
            return '/teacher/library${path.substring('/library'.length)}';
          }
          if (path.startsWith('/communication')) {
            return '/teacher/communication';
          }
          if (path.startsWith('/discipline')) {
            return '/teacher/discipline';
          }
          if (path.startsWith('/presences')) {
            return '/teacher/attendance';
          }
          if (path.startsWith('/courses') ||
              path.startsWith('/assignments') ||
              path.startsWith('/exams') ||
              path.startsWith('/enrollment') ||
              path.startsWith('/meetings') ||
              path.startsWith('/payments') ||
              path.startsWith('/tutoring') ||
              path.startsWith('/admin') ||
              path.startsWith('/accountant') ||
              path.startsWith('/discipline-officer') ||
              path.startsWith('/promoter')) {
            return '/dashboard';
          }
        }
        // Admin : accès uniquement aux routes admin
        if (userRole == 'ADMIN') {
          if (path.startsWith('/courses') ||
              path.startsWith('/assignments') ||
              path.startsWith('/exams') ||
              path.startsWith('/teacher') ||
              path.startsWith('/accountant') ||
              path.startsWith('/discipline-officer') ||
              path.startsWith('/promoter')) {
            return '/dashboard';
          }
        }
        // Comptable : accès uniquement aux routes accountant
        if (userRole == 'ACCOUNTANT') {
          if (path.startsWith('/courses') ||
              path.startsWith('/assignments') ||
              path.startsWith('/exams') ||
              path.startsWith('/teacher') ||
              path.startsWith('/admin') ||
              path.startsWith('/discipline-officer') ||
              path.startsWith('/promoter')) {
            return '/dashboard';
          }
        }
        // Chargé de discipline : accès uniquement aux routes discipline-officer
        if (userRole == 'DISCIPLINE_OFFICER') {
          if (path.startsWith('/courses') ||
              path.startsWith('/assignments') ||
              path.startsWith('/exams') ||
              path.startsWith('/teacher') ||
              path.startsWith('/admin') ||
              path.startsWith('/accountant') ||
              path.startsWith('/promoter')) {
            return '/dashboard';
          }
        }
        // Promoteur : accès uniquement aux routes promoteur
        if (userRole == 'PROMOTER') {
          if (path.startsWith('/courses') ||
              path.startsWith('/assignments') ||
              path.startsWith('/exams') ||
              path.startsWith('/enrollment') ||
              path.startsWith('/meetings') ||
              path.startsWith('/payments') ||
              path.startsWith('/tutoring') ||
              path.startsWith('/teacher') ||
              path.startsWith('/admin') ||
              path.startsWith('/accountant') ||
              path.startsWith('/discipline-officer')) {
            return '/dashboard';
          }
        }
        // Présences parent : réservé aux parents ; enseignant → feuille de présence
        if (path.startsWith('/presences')) {
          if (userRole == 'PARENT') {
            return null;
          }
          if (userRole == 'TEACHER') {
            return '/teacher/attendance';
          }
          return '/dashboard';
        }
      }

      return null;
    },
    routes: [
      // Évite GoException si l’app ouvre « / » (web, lien, bouton Home de l’erreur go_router).
      GoRoute(
        path: '/',
        redirect: (context, state) {
          final isAuthenticated = authState.isAuthenticated;
          if (!isAuthenticated) return '/login';
          return '/dashboard';
        },
      ),
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardPage(),
      ),
      // Routes pour les élèves
      GoRoute(
        path: '/courses',
        builder: (context, state) => const CoursesPage(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return CourseDetailPage(courseId: int.parse(id));
            },
          ),
        ],
      ),
      GoRoute(
        path: '/assignments',
        builder: (context, state) => const AssignmentsPage(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return AssignmentDetailPage(assignmentId: int.parse(id));
            },
          ),
        ],
      ),
      GoRoute(
        path: '/exams',
        builder: (context, state) => const ExamsPage(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return ExamDetailPage(examId: int.parse(id));
            },
            routes: [
              GoRoute(
                path: 'take/:attemptId',
                builder: (context, state) {
                  final quizId = int.parse(state.pathParameters['id']!);
                  final attemptId =
                      int.parse(state.pathParameters['attemptId']!);
                  return QuizTakePage(quizId: quizId, attemptId: attemptId);
                },
              ),
            ],
          ),
        ],
      ),
      // Routes pour les parents
      GoRoute(
        path: '/enrollment',
        builder: (context, state) => const EnrollmentPage(),
      ),
      GoRoute(
        path: '/meetings',
        builder: (context, state) => const MeetingsPage(),
      ),
      GoRoute(
        path: '/presences',
        builder: (context, state) => const ParentPresencePage(),
      ),
      GoRoute(
        path: '/payments',
        builder: (context, state) => const PaymentsPage(),
        routes: [
          GoRoute(
            path: ':id/receipt',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return PaymentReceiptPage(paymentId: int.parse(id));
            },
          ),
        ],
      ),
      GoRoute(
        path: '/tutoring',
        builder: (context, state) => const TutoringPage(),
      ),
      GoRoute(
        path: '/discipline',
        builder: (context, state) => const DisciplinePage(),
      ),
      GoRoute(
        path: '/communication',
        builder: (context, state) => const CommunicationPage(),
      ),
      // Routes communes
      GoRoute(
        path: '/library',
        builder: (context, state) => const LibraryPage(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return BookDetailPage(bookId: int.parse(id));
            },
            routes: [
              GoRoute(
                path: 'read',
                builder: (context, state) {
                  final bookId = int.parse(state.pathParameters['id']!);
                  return BookReaderPage(bookId: bookId);
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/grades',
        builder: (context, state) => const GradesPage(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfilePage(),
      ),
      GoRoute(
        path: '/preferences',
        builder: (context, state) => const PreferencesPage(),
      ),
      // Route détail élève (utilisée par parent et admin)
      GoRoute(
        path: '/students/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          final sid = int.tryParse(id) ?? num.tryParse(id)?.toInt();
          if (sid == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Erreur')),
              body: const Center(child: Text('Identifiant élève invalide')),
            );
          }
          return StudentDetailPage(studentId: sid);
        },
      ),
      // Routes pour les enseignants
      GoRoute(
        path: '/teacher/classes',
        builder: (context, state) => const TeacherClassesPage(),
      ),
      GoRoute(
        path: '/teacher/assignments',
        builder: (context, state) => const TeacherAssignmentsPage(),
      ),
      GoRoute(
        path: '/teacher/assignments/:id',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          if (id == null) {
            return const TeacherAssignmentsPage();
          }
          return TeacherAssignmentDetailPage(assignmentId: id);
        },
      ),
      GoRoute(
        path: '/teacher/attendance',
        builder: (context, state) => const TeacherAttendancePage(),
      ),
      GoRoute(
        path: '/teacher/quizzes',
        builder: (context, state) => const TeacherQuizzesPage(),
        routes: [
          GoRoute(
            path: 'create',
            builder: (context, state) => const TeacherQuizCreatePage(),
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              if (id == null) {
                return const TeacherQuizzesPage();
              }
              return TeacherQuizDetailPage(quizId: id);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/teacher/courses',
        builder: (context, state) => const TeacherCoursesPage(),
        routes: [
          GoRoute(
            path: 'create',
            builder: (context, state) => const TeacherCourseFormPage(),
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              if (id == null) {
                return const TeacherCoursesPage();
              }
              return CourseDetailPage(courseId: id);
            },
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) {
                  final id = int.tryParse(state.pathParameters['id'] ?? '');
                  if (id == null) {
                    return const TeacherCoursesPage();
                  }
                  return TeacherCourseFormPage(courseId: id);
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/teacher/grades',
        builder: (context, state) => const TeacherGradesPage(),
      ),
      GoRoute(
        path: '/teacher/discipline',
        builder: (context, state) =>
            const DisciplinePage(), // Réutiliser DisciplinePage
      ),
      GoRoute(
        path: '/teacher/my-class',
        builder: (context, state) {
          final extra = state.extra;
          int? initialId;
          if (extra is int) {
            initialId = extra;
          } else if (extra is num) {
            initialId = extra.toInt();
          }
          return TeacherMyClassPage(initialClassId: initialId);
        },
      ),
      GoRoute(
        path: '/teacher/class-subjects',
        builder: (context, state) => TeacherClassSubjectsPage(
          initialClassId: state.extra as int?,
        ),
      ),
      GoRoute(
        path: '/teacher/students',
        builder: (context, state) => const TeacherStudentsPage(),
      ),
      GoRoute(
        path: '/teacher/tutoring',
        builder: (context, state) =>
            const TutoringPage(), // Réutiliser TutoringPage
      ),
      GoRoute(
        path: '/teacher/library',
        builder: (context, state) => const LibraryPage(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return BookDetailPage(bookId: int.parse(id));
            },
            routes: [
              GoRoute(
                path: 'read',
                builder: (context, state) {
                  final bookId = int.parse(state.pathParameters['id']!);
                  return BookReaderPage(bookId: bookId);
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/teacher/meetings',
        builder: (context, state) =>
            const MeetingsPage(), // Réutiliser MeetingsPage
      ),
      GoRoute(
        path: '/teacher/communication',
        builder: (context, state) =>
            const CommunicationPage(), // Réutiliser CommunicationPage
      ),
      GoRoute(
        path: '/teacher/elearning',
        builder: (context, state) =>
            const AdminElearningPage(), // Réutiliser AdminElearningPage
      ),
      // Routes pour les admins
      GoRoute(
        path: '/admin/enrollments',
        builder: (context, state) => const AdminEnrollmentsPage(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => const EnrollmentPage(),
          ),
        ],
      ),
      GoRoute(
        path: '/admin/students',
        builder: (context, state) => const AdminStudentsPage(),
      ),
      GoRoute(
        path: '/admin/classes',
        builder: (context, state) => const AdminClassesPage(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              if (id == null) {
                return const AdminClassesPage();
              }
              return AdminClassDetailPage(classId: id);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/admin/teachers',
        builder: (context, state) => const AdminTeachersPage(),
      ),
      GoRoute(
        path: '/admin/payments',
        builder: (context, state) => const AdminPaymentsPage(),
      ),
      GoRoute(
        path: '/admin/expenses',
        builder: (context, state) =>
            const AccountantExpensesPage(), // Réutiliser AccountantExpensesPage
      ),
      GoRoute(
        path: '/admin/caisse',
        builder: (context, state) =>
            const AccountantCaissePage(), // Réutiliser AccountantCaissePage
      ),
      GoRoute(
        path: '/admin/library',
        builder: (context, state) =>
            const LibraryPage(), // Réutiliser LibraryPage
      ),
      GoRoute(
        path: '/admin/meetings',
        builder: (context, state) =>
            const MeetingsPage(), // Réutiliser MeetingsPage
      ),
      GoRoute(
        path: '/admin/tutoring',
        builder: (context, state) =>
            const TutoringPage(), // Réutiliser TutoringPage
      ),
      GoRoute(
        path: '/admin/discipline',
        builder: (context, state) =>
            const DisciplinePage(), // Réutiliser DisciplinePage
      ),
      GoRoute(
        path: '/admin/communication',
        builder: (context, state) => const AdminCommunicationPage(),
      ),
      GoRoute(
        path: '/admin/former-students',
        builder: (context, state) => const AdminFormerStudentsPage(),
      ),
      GoRoute(
        path: '/admin/elearning',
        builder: (context, state) => const AdminElearningPage(),
      ),
      // Routes pour les comptables
      GoRoute(
        path: '/accountant',
        builder: (context, state) => const AccountantDashboardPage(),
      ),
      GoRoute(
        path: '/accountant/enrollments',
        builder: (context, state) =>
            const AdminEnrollmentsPage(baseRoute: '/accountant/enrollments'),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => const EnrollmentPage(),
          ),
        ],
      ),
      GoRoute(
        path: '/accountant/payments',
        builder: (context, state) => const AccountantPaymentsPage(),
      ),
      GoRoute(
        path: '/accountant/expenses',
        builder: (context, state) => const AccountantExpensesPage(),
      ),
      GoRoute(
        path: '/accountant/caisse',
        builder: (context, state) => const AccountantCaissePage(),
      ),
      GoRoute(
        path: '/accountant/communication',
        builder: (context, state) => const CommunicationPage(),
      ),
      // Routes pour les chargés de discipline
      GoRoute(
        path: '/discipline-officer/discipline',
        builder: (context, state) =>
            const DisciplinePage(), // Réutiliser DisciplinePage
      ),
      GoRoute(
        path: '/discipline-officer/meetings',
        builder: (context, state) =>
            const MeetingsPage(), // Réutiliser MeetingsPage
      ),
      GoRoute(
        path: '/discipline-officer/communication',
        builder: (context, state) =>
            const CommunicationPage(), // Réutiliser CommunicationPage
      ),
      // Routes pour les promoteurs
      GoRoute(
        path: '/promoter',
        builder: (context, state) => const PromoterDashboardPage(),
      ),
      GoRoute(
        path: '/promoter/schools',
        builder: (context, state) => const PromoterSchoolsPage(),
      ),
    ],
  );
});
