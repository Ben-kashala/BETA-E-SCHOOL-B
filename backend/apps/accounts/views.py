from decimal import Decimal
from datetime import date, timedelta
from django.db.models import Count, Q
from django.utils import timezone
from django.http import FileResponse
from django.shortcuts import get_object_or_404
from rest_framework import viewsets, status, permissions
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.exceptions import PermissionDenied, NotFound
from rest_framework.response import Response
from rest_framework_simplejwt.views import TokenObtainPairView
from django.contrib.auth import get_user_model
from .models import User, Teacher, Parent, Student
from .serializers import (
    UserSerializer, CustomTokenObtainPairSerializer, RegisterSerializer,
    ChangePasswordSerializer,
    TeacherSerializer, ParentSerializer, StudentSerializer
)
from apps.schools.models import StudentClassEnrollment, SchoolClass, School
from apps.schools.serializers import StudentClassEnrollmentSerializer
from apps.academics.models import Attendance, GradeBulletin, ReportCard
from apps.academics.serializers import GradeBulletinSerializer
from apps.academics.utils import get_class_ranking_map, generate_bulletin_grade_pdf, generate_bulletin_rdc_pdf
from apps.payments.models import Payment

User = get_user_model()


class CustomTokenObtainPairView(TokenObtainPairView):
    serializer_class = CustomTokenObtainPairSerializer


class UserViewSet(viewsets.ModelViewSet):
    queryset = User.objects.all()
    serializer_class = UserSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['role', 'school', 'is_active']
    search_fields = ['username', 'email', 'first_name', 'last_name', 'phone']
    
    def get_queryset(self):
        user = self.request.user
        queryset = User.objects.all()

        # Promoteur : voit uniquement les utilisateurs de SES écoles (multi-écoles)
        if getattr(user, 'is_promoter', False):
            school_ids = list(user.promoted_schools.values_list('id', flat=True))
            if school_ids:
                queryset = queryset.filter(school_id__in=school_ids)
            else:
                queryset = queryset.none()
            return queryset

        # Autres rôles : filtrage classique par école unique
        if user.school:
            queryset = queryset.filter(school=user.school)

        # Admins can see all users in their school
        # Discipline officers can see all users in their school
        # Teachers can see students and parents in their school
        # Parents can see their children
        # Students can see limited info
        if user.is_admin or getattr(user, 'is_discipline_officer', False):
            # Admins and discipline officers can see all users in their school
            pass  # Already filtered by school above
        elif user.is_teacher:
            queryset = queryset.filter(role__in=['STUDENT', 'PARENT'], school=user.school)
        elif user.is_parent:
            queryset = queryset.filter(id=user.id)  # Parents see only themselves
        elif user.is_student:
            queryset = queryset.filter(id=user.id)  # Students see only themselves
        
        return queryset
    
    @action(detail=False, methods=['get'], url_path='school-staff')
    def school_staff(self, request):
        """Retourne le personnel de l'école (enseignants, admins, etc.) pour permettre aux parents/élèves d'envoyer des messages"""
        user = request.user
        if not user.school:
            return Response({'detail': 'École non associée.'}, status=status.HTTP_400_BAD_REQUEST)
        
        # Retourner uniquement le personnel de l'école (pas les parents ni les élèves)
        staff_roles = ['TEACHER', 'ADMIN', 'ACCOUNTANT', 'DISCIPLINE_OFFICER']
        staff_users = User.objects.filter(
            school=user.school,
            role__in=staff_roles,
            is_active=True
        ).select_related('school').order_by('first_name', 'last_name')
        
        serializer = self.get_serializer(staff_users, many=True)
        return Response(serializer.data)
    
    @action(detail=False, methods=['get', 'put', 'patch'])
    def me(self, request):
        """Get or update current user profile"""
        serializer = self.get_serializer(request.user)
        if request.method in ['PUT', 'PATCH']:
            serializer = self.get_serializer(request.user, data=request.data, partial=True)
            serializer.is_valid(raise_exception=True)
            serializer.save()
            return Response(serializer.data)
        return Response(serializer.data)
    
    @action(detail=False, methods=['post'])
    def change_password(self, request):
        """Permet à l'utilisateur connecté (parent, élève, etc.) de changer son mot de passe"""
        serializer = ChangePasswordSerializer(data=request.data, context={'request': request})
        serializer.is_valid(raise_exception=True)
        user = request.user
        user.set_password(serializer.validated_data['new_password'])
        user.save()
        return Response({'message': 'Mot de passe modifié avec succès.'}, status=status.HTTP_200_OK)

    @action(detail=False, methods=['post'])
    def register(self, request):
        """Register a new user"""
        print(f"DEBUG REGISTER: User: {request.user.username}, Role: {request.user.role}, School: {request.user.school}")
        print(f"DEBUG REGISTER: Request data: {request.data}")
        
        serializer = RegisterSerializer(data=request.data)
        if serializer.is_valid():
            # Assigner automatiquement l'école de l'utilisateur qui crée le compte
            user = serializer.save()
            print(f"DEBUG REGISTER: User créé: {user.username}, School avant assignation: {user.school}")
            
            if request.user.school and not user.school:
                user.school = request.user.school
                user.save()
                print(f"DEBUG REGISTER: School assignée: {user.school}")
            
            # Passer le contexte de la requête au serializer
            serializer = UserSerializer(user, context={'request': request})
            return Response(serializer.data, status=status.HTTP_201_CREATED)
        else:
            print(f"DEBUG REGISTER: Erreurs de validation: {serializer.errors}")
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class TeacherViewSet(viewsets.ModelViewSet):
    serializer_class = TeacherSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['user__school']
    search_fields = ['user__username', 'employee_id', 'user__first_name', 'user__last_name']
    
    def get_queryset(self):
        queryset = Teacher.objects.all()
        if self.request.user.school:
            queryset = queryset.filter(user__school=self.request.user.school)
        return queryset


class ParentViewSet(viewsets.ModelViewSet):
    serializer_class = ParentSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['user__school']
    search_fields = ['user__username', 'user__first_name', 'user__last_name']
    
    def get_queryset(self):
        queryset = Parent.objects.all()
        if self.request.user.school:
            queryset = queryset.filter(user__school=self.request.user.school)
        # Parents can only see their own profile
        if self.request.user.is_parent:
            queryset = queryset.filter(user=self.request.user)
        return queryset


class StudentViewSet(viewsets.ModelViewSet):
    serializer_class = StudentSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = [
        'school_class', 'academic_year', 'user__school', 'is_former_student',
        'school_class__is_terminal'
    ]
    search_fields = ['user__username', 'student_id', 'user__first_name', 'user__last_name', 'user__middle_name']
    
    def get_queryset(self):
        user = self.request.user
        queryset = Student.objects.select_related(
            'user', 'school_class', 'school_class__titulaire', 'school_class__titulaire__user', 'parent'
        ).all()

        # Promoteur : élèves dans toutes ses écoles
        if getattr(user, 'is_promoter', False):
            school_ids = list(user.promoted_schools.values_list('id', flat=True))
            if school_ids:
                queryset = queryset.filter(user__school_id__in=school_ids)
            else:
                queryset = queryset.none()
            return queryset

        if user.school:
            queryset = queryset.filter(user__school=user.school)
        # Parents can only see their children
        if user.is_parent:
            queryset = queryset.filter(parent=user)
        # Students can only see themselves
        elif user.is_student:
            queryset = queryset.filter(user=user)
        # Admin and Teacher see all students of the school (filter above)
        return queryset

    def perform_create(self, serializer):
        serializer.save()
        inst = getattr(serializer, 'instance', None)
        if inst and getattr(inst, 'school_class_id', None):
            StudentClassEnrollment.objects.get_or_create(
                student=inst, school_class=inst.school_class,
                defaults={'status': 'active'},
            )

    def perform_update(self, serializer):
        serializer.save()
        inst = serializer.instance
        if inst and getattr(inst, 'school_class_id', None):
            StudentClassEnrollment.objects.get_or_create(
                student=inst, school_class=inst.school_class,
                defaults={'status': 'active'},
            )
    
    @action(detail=True, methods=['post'], url_path='transfer')
    def transfer(self, request, pk=None):
        """
        Transférer le dossier d'un élève vers une autre école de la plateforme.
        Réservé à l'ADMIN de l'école actuelle.
        """
        student = self.get_object()
        user = request.user

        if not getattr(user, 'is_admin', False):
            raise PermissionDenied("Seul l'administrateur d'école peut transférer un élève.")
        if not user.school or user.school_id != getattr(student.user, 'school_id', None):
            raise PermissionDenied("Vous ne pouvez transférer que les élèves de votre école.")

        target_school_id = request.data.get('target_school')
        target_class_id = request.data.get('target_class')
        if not target_school_id:
            raise ValidationError({'target_school': "L'école cible est obligatoire."})
        if str(target_school_id) == str(user.school_id):
            raise ValidationError({'target_school': "L'école cible doit être différente de l'école actuelle."})

        target_school = School.objects.filter(pk=target_school_id, is_active=True).first()
        if not target_school:
            raise ValidationError({'target_school': "École cible introuvable."})

        target_class = None
        if target_class_id:
            target_class = SchoolClass.objects.filter(pk=target_class_id, school=target_school).first()
            if not target_class:
                raise ValidationError({'target_class': "Classe cible introuvable dans l'école sélectionnée."})

        # Clôturer l'inscription courante dans l'école A
        if student.school_class_id:
            StudentClassEnrollment.objects.filter(
                student=student,
                school_class=student.school_class,
                status='active',
            ).update(status='withdrawn', left_at=timezone.now())

        # Changer l'école de l'utilisateur élève
        student.user.school = target_school
        student.user.save(update_fields=['school'])

        # Rattacher éventuellement à une classe de l'école B
        if target_class:
            student.school_class = target_class
            student.academic_year = target_class.academic_year
            student.save(update_fields=['school_class', 'academic_year'])
            StudentClassEnrollment.objects.get_or_create(
                student=student,
                school_class=target_class,
                defaults={'status': 'active'},
            )
        else:
            student.school_class = None
            student.save(update_fields=['school_class'])

        # Notifier les admins de l'école B
        admins_b = User.objects.filter(school=target_school, role='ADMIN', is_active=True)
        from apps.communication.notifications import notify_users
        notify_users(
            target_school,
            admins_b,
            'GENERAL',
            "Nouveau dossier élève transféré",
            f"L'élève {student.user.get_full_name()} a été transféré depuis l'école {user.school.name}.",
            related_object_type='student',
            related_object_id=student.id,
        )

        return Response({'detail': 'Transfert effectué avec succès.'}, status=status.HTTP_200_OK)
    
    @action(detail=False, methods=['get'], url_path='parent_dashboard')
    def parent_dashboard(self, request):
        """
        Données du tableau de bord parent : pour chaque enfant : identité, moyenne générale,
        présences/absences par semaine (4 dernières semaines incluant la semaine courante).
        Réservé aux parents.
        """
        if not getattr(request.user, 'is_parent', False):
            return Response({'detail': 'Réservé aux parents.'}, status=status.HTTP_403_FORBIDDEN)
        queryset = self.get_queryset()
        today = date.today()
        result = []
        for student in queryset:
            identity = self.get_serializer(student).data
            # Dernier bulletin (moyenne générale)
            latest_rc = ReportCard.objects.filter(
                student=student, is_published=True
            ).order_by('-academic_year', '-term').first()
            average_score = float(latest_rc.average_score) if latest_rc and latest_rc.average_score is not None else None
            # Présences/absences par semaine (4 semaines)
            attendance_by_week = []
            for i in range(4):
                ref = today - timedelta(weeks=i)
                start = ref - timedelta(days=ref.weekday())
                end = start + timedelta(days=6)
                qs = Attendance.objects.filter(
                    student=student,
                    date__gte=start,
                    date__lte=end,
                )
                agg = qs.aggregate(
                    present=Count('id', filter=Q(status='PRESENT')),
                    absent=Count('id', filter=Q(status='ABSENT')),
                    late=Count('id', filter=Q(status='LATE')),
                    excused=Count('id', filter=Q(status='EXCUSED')),
                )
                total = (agg['present'] or 0) + (agg['absent'] or 0) + (agg['late'] or 0) + (agg['excused'] or 0)
                attendance_by_week.append({
                    'week_start': start.isoformat(),
                    'week_end': end.isoformat(),
                    'label': f'Sem. {start.strftime("%d/%m")}',
                    'present': agg['present'] or 0,
                    'absent': agg['absent'] or 0,
                    'late': agg['late'] or 0,
                    'excused': agg['excused'] or 0,
                    'total': total,
                })
            result.append({
                'identity': identity,
                'average_score': average_score,
                'attendance_by_week': attendance_by_week,
            })
        return Response(result)

    @action(detail=False, methods=['get'], url_path='student_dashboard')
    def student_dashboard(self, request):
        """
        Données du tableau de bord élève : identité (classe, année, titulaire),
        moyenne générale, présences/absences par semaine (4 dernières semaines).
        Réservé aux élèves.
        """
        if not getattr(request.user, 'is_student', False):
            return Response({'detail': 'Réservé aux élèves.'}, status=status.HTTP_403_FORBIDDEN)
        student = self.get_queryset().first()
        if not student:
            return Response({'detail': 'Profil élève introuvable.'}, status=status.HTTP_404_NOT_FOUND)
        identity = self.get_serializer(student).data
        latest_rc = ReportCard.objects.filter(
            student=student, is_published=True
        ).order_by('-academic_year', '-term').first()
        average_score = float(latest_rc.average_score) if latest_rc and latest_rc.average_score is not None else None
        today = date.today()
        attendance_by_week = []
        for i in range(4):
            ref = today - timedelta(weeks=i)
            start = ref - timedelta(days=ref.weekday())
            end = start + timedelta(days=6)
            qs = Attendance.objects.filter(student=student, date__gte=start, date__lte=end)
            agg = qs.aggregate(
                present=Count('id', filter=Q(status='PRESENT')),
                absent=Count('id', filter=Q(status='ABSENT')),
                late=Count('id', filter=Q(status='LATE')),
                excused=Count('id', filter=Q(status='EXCUSED')),
            )
            total = (agg['present'] or 0) + (agg['absent'] or 0) + (agg['late'] or 0) + (agg['excused'] or 0)
            attendance_by_week.append({
                'week_start': start.isoformat(),
                'week_end': end.isoformat(),
                'label': f'Sem. {start.strftime("%d/%m")}',
                'present': agg['present'] or 0,
                'absent': agg['absent'] or 0,
                'late': agg['late'] or 0,
                'excused': agg['excused'] or 0,
                'total': total,
            })
        return Response({
            'identity': identity,
            'average_score': average_score,
            'attendance_by_week': attendance_by_week,
        })

    @action(detail=True, methods=['get'])
    def full_detail(self, request, pk=None):
        """
        Détail complet de l'élève: identité, parcours (classes), notes/bulletins, paiements.
        """
        student = self.get_object()
        # Identité
        identity = self.get_serializer(student).data
        # Parcours (historique des classes) avec rang et pourcentage par (classe, année)
        enrollments = StudentClassEnrollment.objects.filter(
            student=student
        ).select_related('school_class').order_by('-enrolled_at')
        class_enrollments = StudentClassEnrollmentSerializer(enrollments, many=True).data
        ranking_cache = {}
        for i, e in enumerate(enrollments):
            sc = e.school_class
            ac = (getattr(sc, 'academic_year', None) or '').strip() if sc else ''
            key = (e.school_class_id, ac)
            if key not in ranking_cache:
                ranking_cache[key] = get_class_ranking_map(sc, ac)
            info = ranking_cache[key].get(student.id, {})
            class_enrollments[i]['rank'] = info.get('rank')
            class_enrollments[i]['percentage'] = info.get('percentage')
        # Notes bulletin RDC
        grade_bulletins = GradeBulletin.objects.filter(
            student=student
        ).select_related('subject', 'teacher__user').order_by('academic_year', 'subject__name')
        bulletins_data = GradeBulletinSerializer(grade_bulletins, many=True).data
        # Bulletins (décision, moyenne, etc.)
        report_cards = ReportCard.objects.filter(
            student=student
        ).select_related('reclamation_subject').order_by('-academic_year')
        report_cards_data = [
            {
                'id': rc.id,
                'academic_year': rc.academic_year,
                'term': rc.term,
                'average_score': float(rc.average_score) if rc.average_score is not None else None,
                'rank': rc.rank,
                'total_students': rc.total_students,
                'application': float(rc.application) if rc.application is not None else None,
                'conduite': float(rc.conduite) if rc.conduite is not None else None,
                'decision': rc.decision,
                'is_published': rc.is_published,
                'teacher_comment': rc.teacher_comment,
                'principal_comment': rc.principal_comment,
            }
            for rc in report_cards
        ]
        # Paiements (école de l'utilisateur)
        payments_qs = Payment.objects.filter(
            student=student,
            school=request.user.school
        ).order_by('-created_at') if request.user.school else Payment.objects.none()
        payments_data = [
            {
                'id': p.id,
                'payment_id': p.payment_id,
                'amount': float(p.amount),
                'currency': p.currency,
                'status': p.status,
                'payment_method': p.payment_method,
                'payment_date': p.payment_date.isoformat() if p.payment_date else None,
                'created_at': p.created_at.isoformat() if p.created_at else None,
                'description': p.description,
            }
            for p in payments_qs
        ]
        return Response({
            'identity': identity,
            'class_enrollments': class_enrollments,
            'grade_bulletins': bulletins_data,
            'report_cards': report_cards_data,
            'payments': payments_data,
        })

    @action(detail=True, methods=['post'], url_path='generate_annual_bulletin')
    def generate_annual_bulletin(self, request, pk=None):
        """
        Crée ou récupère le bulletin de décision annuel (term='AN') pour l'élève et l'année donnée.
        Corps : { "academic_year": "2025-2026" }. Calcule moyenne/rang si possible à partir des notes RDC.
        """
        student = self.get_object()
        academic_year = (request.data.get('academic_year') or request.query_params.get('academic_year') or '').strip()
        if not academic_year:
            return Response(
                {'error': "Le paramètre academic_year est obligatoire (ex. '2025-2026')."},
                status=status.HTTP_400_BAD_REQUEST
            )
        enrollment = StudentClassEnrollment.objects.filter(
            student=student
        ).select_related('school_class').filter(
            school_class__academic_year=academic_year
        ).first()
        school_class = enrollment.school_class if enrollment else None
        ranking_map = get_class_ranking_map(school_class, academic_year) if school_class else {}
        total_students = len(ranking_map)
        info = ranking_map.get(student.id, {})
        rank = info.get('rank')
        percentage = info.get('percentage')
        average_score = Decimal(str(round(percentage * 20 / 100, 2))) if percentage is not None else None
        total_subjects = GradeBulletin.objects.filter(
            student=student, academic_year=academic_year
        ).count()
        report_card, created = ReportCard.objects.get_or_create(
            student=student,
            academic_year=academic_year,
            term='AN',
            defaults={
                'total_subjects': total_subjects,
                'average_score': average_score,
                'rank': rank,
                'total_students': total_students if total_students else None,
            }
        )
        if not created:
            report_card.total_students = total_students or report_card.total_students
            report_card.rank = rank if rank is not None else report_card.rank
            if average_score is not None:
                report_card.average_score = average_score
            report_card.total_subjects = total_subjects
            report_card.save(update_fields=['total_students', 'rank', 'average_score', 'total_subjects'])
        report_cards_data = [{
            'id': report_card.id,
            'academic_year': report_card.academic_year,
            'term': report_card.term,
            'average_score': float(report_card.average_score) if report_card.average_score is not None else None,
            'rank': report_card.rank,
            'total_students': report_card.total_students,
            'application': float(report_card.application) if report_card.application is not None else None,
            'conduite': float(report_card.conduite) if report_card.conduite is not None else None,
            'decision': report_card.decision,
            'is_published': report_card.is_published,
            'teacher_comment': report_card.teacher_comment,
            'principal_comment': report_card.principal_comment,
        }]
        return Response({
            'report_card': report_cards_data[0],
            'created': created,
            'message': 'Bulletin annuel créé.' if created else 'Bulletin annuel déjà existant.',
        }, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)

    @action(detail=True, methods=['get'], url_path='bulletin_pdf')
    def bulletin_pdf(self, request, pk=None):
        """
        Télécharge le bulletin PDF pour une classe et une année scolaire.
        Si un bulletin de décision (ReportCard annuel) existe pour cette année, on sert ce PDF officiel.
        Sinon, on génère le bulletin « notes par matière » (generate_bulletin_grade_pdf).
        Query params: school_class (id), academic_year (obligatoires).
        """
        school_class_id = request.query_params.get('school_class')
        academic_year = (request.query_params.get('academic_year') or '').strip()
        if not school_class_id or not academic_year:
            return Response(
                {'error': 'Les paramètres school_class et academic_year sont obligatoires.'},
                status=status.HTTP_400_BAD_REQUEST
            )
        student = self.get_object()
        school_class = get_object_or_404(SchoolClass, pk=school_class_id)
        if request.user.school and school_class.school_id != request.user.school_id:
            raise PermissionDenied('Classe non accessible.')
        # Préférer le bulletin de décision (officiel RDC) si existant pour cette année (régénéré à chaque fois)
        report_card = ReportCard.objects.filter(
            student=student, academic_year=academic_year, term='AN'
        ).first()
        if report_card:
            try:
                report_card.pdf_file = generate_bulletin_rdc_pdf(report_card)
                report_card.save(update_fields=['pdf_file'])
            except Exception as e:
                return Response(
                    {'error': 'Échec de la génération du PDF', 'detail': str(e)},
                    status=status.HTTP_500_INTERNAL_SERVER_ERROR
                )
            fn = f'bulletin_{student.id}_{school_class.id}_{academic_year.replace("/", "-")}.pdf'
            return FileResponse(report_card.pdf_file.open(), content_type='application/pdf', as_attachment=True, filename=fn)
        buffer = generate_bulletin_grade_pdf(student, school_class, academic_year)
        fn = f'bulletin_{student.id}_{school_class.id}_{academic_year.replace("/", "-")}.pdf'
        return FileResponse(buffer, content_type='application/pdf', as_attachment=True, filename=fn)


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def bulletin_pdf_download(request, pk):
    """
    Vue en secours pour le bulletin PDF (même logique que StudentViewSet.bulletin_pdf).
    Route explicite pour éviter les 404 avec le routeur DRF.
    GET /api/accounts/students/<pk>/bulletin_pdf/?school_class=&academic_year=
    """
    from apps.accounts.models import Student

    school_class_id = request.query_params.get('school_class')
    academic_year = (request.query_params.get('academic_year') or '').strip()
    if not school_class_id or not academic_year:
        return Response(
            {'error': 'Les paramètres school_class et academic_year sont obligatoires.'},
            status=status.HTTP_400_BAD_REQUEST
        )
    qs = Student.objects.select_related('user', 'school_class', 'parent').all()
    if request.user.school:
        qs = qs.filter(user__school=request.user.school)
    if getattr(request.user, 'is_parent', False):
        qs = qs.filter(parent=request.user)
    elif getattr(request.user, 'is_student', False):
        qs = qs.filter(user=request.user)
    student = qs.filter(pk=pk).first()
    if not student:
        raise NotFound('Élève introuvable ou accès refusé.')
    school_class = SchoolClass.objects.filter(pk=school_class_id).first()
    if not school_class:
        return Response(
            {'error': 'Classe introuvable.', 'detail': f'school_class={school_class_id}'},
            status=status.HTTP_400_BAD_REQUEST
        )
    if request.user.school and school_class.school_id != request.user.school_id:
        raise PermissionDenied('Classe non accessible.')
    report_card = ReportCard.objects.filter(
        student=student, academic_year=academic_year, term='AN'
    ).first()
    if report_card:
        try:
            from apps.academics.utils import generate_bulletin_rdc_pdf
            report_card.pdf_file = generate_bulletin_rdc_pdf(report_card)
            report_card.save(update_fields=['pdf_file'])
        except Exception as e:
            return Response(
                {'error': 'Échec de la génération du PDF', 'detail': str(e)},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )
        fn = f'bulletin_{student.id}_{school_class.id}_{academic_year.replace("/", "-")}.pdf'
        return FileResponse(report_card.pdf_file.open(), content_type='application/pdf', as_attachment=True, filename=fn)
    buffer = generate_bulletin_grade_pdf(student, school_class, academic_year)
    fn = f'bulletin_{student.id}_{school_class.id}_{academic_year.replace("/", "-")}.pdf'
    return FileResponse(buffer, content_type='application/pdf', as_attachment=True, filename=fn)
