from decimal import Decimal
from django.utils import timezone
from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.exceptions import PermissionDenied, ValidationError
from django.db.models import Q, Sum, Count
from .models import School, Section, SchoolClass, Subject, ClassSubject, StudentClassEnrollment
from apps.accounts.models import Student, User
from apps.payments.models import Payment, SchoolExpense
from .serializers import (
    SchoolSerializer, SectionSerializer, SchoolClassSerializer, SubjectSerializer, ClassSubjectSerializer,
    StudentClassEnrollmentSerializer,
)


class SchoolViewSet(viewsets.ModelViewSet):
    queryset = School.objects.filter(is_active=True)
    serializer_class = SchoolSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['country', 'city', 'is_active']
    search_fields = ['name', 'code', 'email']

    def get_queryset(self):
        """Superadmin et admin plateforme voient toutes les écoles ; les autres uniquement leur école."""
        user = self.request.user
        qs = School.objects.filter(is_active=True)
        if user.is_superuser or (getattr(user, 'is_platform_admin', False)):
            return qs
        if user.school_id:
            return qs.filter(pk=user.school_id)
        return qs.none()

    def perform_create(self, serializer):
        """Seul le superadmin ou un admin plateforme (ADMIN sans école) peut créer une école."""
        user = self.request.user
        if not (user.is_superuser or getattr(user, 'is_platform_admin', False)):
            raise PermissionDenied(
                "Seul le superadmin ou un administrateur plateforme (non rattaché à une école) peut créer une école."
            )
        serializer.save()
    
    @action(detail=False, methods=['get'])
    def my_school(self, request):
        """Get the current user's school"""
        if hasattr(request.user, 'school'):
            serializer = self.get_serializer(request.user.school)
            return Response(serializer.data)
        return Response({'detail': 'No school associated'}, status=404)

    @action(detail=False, methods=['get'], url_path='all-for-transfer')
    def all_for_transfer(self, request):
        """
        Liste de toutes les écoles actives de la plateforme, pour transfert / collaboration inter-écoles.
        Accès réservé aux admins d'école, promoteurs et superusers.
        """
        user = request.user
        if not (getattr(user, 'is_admin', False) or getattr(user, 'is_promoter', False) or user.is_superuser):
            raise PermissionDenied("Accès réservé aux administrateurs et promoteurs.")
        qs = School.objects.filter(is_active=True).order_by('name')
        data = [
            {
                'id': s.id,
                'name': s.name,
                'code': s.code,
                'city': s.city,
                'school_type': s.school_type,
            }
            for s in qs
        ]
        return Response({'results': data})

    @action(detail=False, methods=['get'], url_path='my-schools')
    def my_schools(self, request):
        """
        Liste des écoles du promoteur connecté, avec quelques statistiques de base
        (effectif élèves, totaux paiements/dépenses).
        """
        user = request.user
        if not getattr(user, 'is_promoter', False):
            return Response({'results': []})

        schools = School.objects.filter(promoters=user, is_active=True).order_by('name')
        school_ids = list(schools.values_list('id', flat=True))

        # Élèves par école
        students_counts = dict(
            Student.objects.filter(user__school_id__in=school_ids)
            .values_list('user__school_id')
            .annotate(count=Count('id'))
        )

        # Paiements complétés par école
        payments_totals = {}
        if school_ids:
            for row in (
                Payment.objects.filter(school_id__in=school_ids, status='COMPLETED')
                .values('school_id', 'currency')
                .annotate(total=Sum('amount'))
            ):
                key = (row['school_id'], row['currency'] or 'CDF')
                payments_totals[key] = float(row['total'] or 0)

        # Dépenses payées par école
        expenses_totals = {}
        if school_ids:
            for row in (
                SchoolExpense.objects.filter(school_id__in=school_ids, status='PAID')
                .values('school_id', 'currency')
                .annotate(total=Sum('amount'))
            ):
                key = (row['school_id'], row['currency'] or 'CDF')
                expenses_totals[key] = float(row['total'] or 0)

        data = []
        for school in schools:
            serialized = SchoolSerializer(school, context=self.get_serializer_context()).data
            sid = school.id
            serialized['students_count'] = students_counts.get(sid, 0)
            serialized['payments_totals'] = {
                currency: amount
                for (sch_id, currency), amount in payments_totals.items()
                if sch_id == sid
            }
            serialized['expenses_totals'] = {
                currency: amount
                for (sch_id, currency), amount in expenses_totals.items()
                if sch_id == sid
            }
            data.append(serialized)

        return Response({'results': data})

    @action(detail=False, methods=['get'], url_path='promoter-dashboard')
    def promoter_dashboard(self, request):
        """
        Tableau de bord global du promoteur :
        - Nombre d'écoles par type
        - Nombre total d'élèves
        - Totaux paiements et dépenses (toutes ses écoles)
        """
        user = request.user
        if not getattr(user, 'is_promoter', False):
            return Response(
                {'detail': "Accès réservé au promoteur."},
                status=status.HTTP_403_FORBIDDEN,
            )

        schools = School.objects.filter(promoters=user, is_active=True)
        school_ids = list(schools.values_list('id', flat=True))

        # Écoles par type
        type_counts = dict(
            schools.values_list('school_type').annotate(count=Count('id'))
        )

        # Élèves
        total_students = (
            Student.objects.filter(user__school_id__in=school_ids).count()
            if school_ids else 0
        )

        # Paiements complétés
        payments_by_currency = {}
        if school_ids:
            for row in (
                Payment.objects.filter(school_id__in=school_ids, status='COMPLETED')
                .values('currency')
                .annotate(total=Sum('amount'))
            ):
                currency = row['currency'] or 'CDF'
                payments_by_currency[currency] = float(row['total'] or 0)

        # Dépenses payées
        expenses_by_currency = {}
        if school_ids:
            for row in (
                SchoolExpense.objects.filter(school_id__in=school_ids, status='PAID')
                .values('currency')
                .annotate(total=Sum('amount'))
            ):
                currency = row['currency'] or 'CDF'
                expenses_by_currency[currency] = float(row['total'] or 0)

        return Response({
            'schools_total': len(school_ids),
            'schools_by_type': {
                key: type_counts.get(key, 0)
                for key in ['MATERNELLE', 'PRIMAIRE', 'HUMANITAIRE']
            },
            'students_total': total_students,
            'payments_by_currency': payments_by_currency,
            'expenses_by_currency': expenses_by_currency,
        })


class SectionViewSet(viewsets.ModelViewSet):
    serializer_class = SectionSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['school', 'is_active']
    search_fields = ['name']
    
    def get_queryset(self):
        queryset = Section.objects.filter(is_active=True)
        # Filter by user's school
        if self.request.user.school:
            queryset = queryset.filter(school=self.request.user.school)
        # Filter by school if provided in query params
        school_id = self.request.query_params.get('school', None)
        if school_id:
            queryset = queryset.filter(school_id=school_id)
        return queryset
    
    def perform_create(self, serializer):
        """Automatically assign the section to the user's school"""
        if not self.request.user.school:
            raise ValidationError({
                'non_field_errors': ['Vous devez être associé à une école pour créer une section. Veuillez contacter l\'administrateur système.']
            })
        serializer.save(school=self.request.user.school)


class SchoolClassViewSet(viewsets.ModelViewSet):
    serializer_class = SchoolClassSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['school', 'level', 'grade', 'academic_year', 'is_active', 'titulaire']
    search_fields = ['name']
    
    @action(detail=False, methods=['get'])
    def my_titular(self, request):
        """
        Classes dont l'utilisateur connecté est le titulaire (et uniquement celles-là).
        Inclut les classes inactives (années passées) pour consulter l'historique et les promus.
        Si une classe incorrecte apparaît (ex. 1ère au lieu de 2ème), l'admin doit corriger
        le champ « Enseignant titulaire » dans Gestion des classes (Admin > Classes).
        """
        if not getattr(request.user, 'is_teacher', False):
            return Response({'results': []})
        try:
            teacher = request.user.teacher_profile
        except Exception:
            return Response({'results': []})
        if not teacher or not getattr(teacher, 'pk', None):
            return Response({'results': []})
        # Filtre strict : uniquement les classes où titulaire_id = moi
        qs = SchoolClass.objects.filter(titulaire_id=teacher.pk).select_related('school', 'section', 'titulaire__user')
        if request.user.school:
            qs = qs.filter(school=request.user.school)
        qs = qs.order_by('-academic_year', 'name')
        serializer = self.get_serializer(qs, many=True)
        return Response({'results': serializer.data})

    @action(detail=False, methods=['get'])
    def my_grades_classes(self, request):
        """Classes où l'enseignant peut saisir des notes : titulaire OU enseignant assigné à au moins une matière (ClassSubject.teacher). Utilisé par Gestion des notes."""
        if not getattr(request.user, 'is_teacher', False):
            return Response({'results': []})
        try:
            teacher = request.user.teacher_profile
        except Exception:
            return Response({'results': []})
        # Titulaire OU au moins une ClassSubject avec teacher=me
        teaching_class_ids = ClassSubject.objects.filter(teacher=teacher).values_list('school_class_id', flat=True).distinct()
        qs = SchoolClass.objects.filter(
            Q(titulaire=teacher) | Q(id__in=teaching_class_ids),
            is_active=True,
        ).select_related('school', 'section', 'titulaire__user')
        if request.user.school:
            qs = qs.filter(school=request.user.school)
        qs = qs.distinct()
        serializer = self.get_serializer(qs, many=True)
        return Response({'results': serializer.data})

    def get_queryset(self):
        queryset = SchoolClass.objects.filter(is_active=True)
        school_id = self.request.query_params.get('school', None)
        user = self.request.user
        can_see_other_schools = getattr(user, 'is_admin', False) or getattr(user, 'is_promoter', False) or user.is_superuser
        # Transfert : admin/promoter/superuser peut demander les classes d'une autre école via ?school=
        if school_id and can_see_other_schools:
            return queryset.filter(school_id=school_id)
        if user.school:
            queryset = queryset.filter(school=user.school)
            if school_id and str(user.school_id) != str(school_id):
                return queryset.none()
        elif school_id:
            queryset = queryset.filter(school_id=school_id)
        return queryset
    
    def create(self, request, *args, **kwargs):
        """Override create to add debug logging"""
        # Debug: Vérifier l'utilisateur et son école AVANT la validation
        user = request.user
        print(f"DEBUG CREATE: User: {user.username}, Role: {user.role}, School: {user.school}")
        print(f"DEBUG CREATE: Request data: {request.data}")
        
        # Vérifier si l'utilisateur a une école
        if not user.school:
            print(f"DEBUG CREATE: ERREUR - L'utilisateur {user.username} n'a pas d'école associée")
            return Response({
                'non_field_errors': ['Vous devez être associé à une école pour créer une classe. Veuillez contacter l\'administrateur système.']
            }, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            response = super().create(request, *args, **kwargs)
            print(f"DEBUG CREATE: Succès - Classe créée")
            return response
        except Exception as e:
            print(f"DEBUG CREATE: ERREUR lors de la création: {type(e).__name__}: {str(e)}")
            import traceback
            traceback.print_exc()
            raise
    
    def perform_create(self, serializer):
        """Automatically assign the class to the user's school"""
        user = self.request.user
        print(f"DEBUG PERFORM_CREATE: User: {user.username}, School: {user.school.name if user.school else None}")
        serializer.save(school=user.school)

    @action(detail=True, methods=['post'])
    def promote_admitted(self, request, pk=None):
        """
        En fin d'année:
        - Élèves avec T.G. ≥ 50% :
          - Année terminale (is_terminal) : sortie de l'école → anciens élèves.
          - Sinon : promotion vers la classe suivante (next_class_name, année suivante).
        - Élèves avec T.G. < 50% : statut Échec, ils reprennent la MÊME classe pour l'année suivante (année+1).
        Réservé au titulaire ou à l'admin.
        """
        from apps.accounts.models import Student
        from apps.academics.models import GradeBulletin

        school_class = self.get_object()
        if request.user.school and school_class.school_id != request.user.school_id:
            raise PermissionDenied("Cette classe n'appartient pas à votre école.")
        if not getattr(request.user, 'is_admin', False):
            try:
                tp = request.user.teacher_profile
                if not school_class.titulaire_id or school_class.titulaire_id != tp.id:
                    raise PermissionDenied("Seul le titulaire de la classe ou l'admin peut lancer la promotion.")
            except Exception:
                raise PermissionDenied("Accès refusé.")

        ac = (school_class.academic_year or '').strip()
        parts = ac.split('-')
        if len(parts) != 2:
            return Response(
                {'error': f"Format d'année scolaire invalide: « {ac} ». Attendu: 2025-2026."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            next_year = f"{int(parts[0]) + 1}-{int(parts[1]) + 1}"
        except ValueError:
            return Response(
                {'error': f"Année scolaire invalide: « {ac} »."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        class_subjects = ClassSubject.objects.filter(school_class=school_class)
        max_per_subject = {cs.subject_id: (cs.period_max or 20) * 8 for cs in class_subjects}
        subject_ids = list(max_per_subject.keys())
        total_max = sum(max_per_subject.values()) or 1

        students = Student.objects.filter(school_class=school_class).select_related('user')
        bulletins = GradeBulletin.objects.filter(
            student__in=students, academic_year=ac, subject_id__in=subject_ids
        )
        by_student = {}
        for b in bulletins:
            by_student.setdefault(b.student_id, {})[b.subject_id] = (b.total_general or Decimal('0'))

        to_graduate = []
        to_promote = []
        to_repeat = []
        for s in students:
            pts = sum(by_student.get(s.id, {}).values())
            pct = (float(pts) / total_max * 100) if total_max else 0
            if pct >= 50:
                if getattr(school_class, 'is_terminal', False):
                    to_graduate.append(s)
                else:
                    to_promote.append(s)
            else:
                to_repeat.append(s)

        if getattr(school_class, 'is_terminal', False):
            # Année terminale : ≥50% → sortie (graduated) ; <50% → Échec + reprise même classe (année+1)
            if to_repeat:
                repeat_class = SchoolClass.objects.filter(
                    school=school_class.school, name=school_class.name, academic_year=next_year, is_active=True
                ).first()
                if not repeat_class:
                    return Response(
                        {
                            'error': f"La classe « {school_class.name} » pour l'année {next_year} n'existe pas.",
                            'detail': "Créez cette classe pour l'année suivante afin que les élèves en échec (<50%) puissent la reprendre.",
                        },
                        status=status.HTTP_400_BAD_REQUEST,
                    )
            for s in to_graduate:
                old = StudentClassEnrollment.objects.filter(student=s, school_class=school_class).first()
                if old:
                    old.status = 'graduated'
                    old.left_at = timezone.now()
                    old.save(update_fields=['status', 'left_at'])
                else:
                    StudentClassEnrollment.objects.create(
                        student=s, school_class=school_class, status='graduated', left_at=timezone.now(),
                    )
                s.school_class = None
                s.is_former_student = True
                s.graduation_year = ac
                s.save(update_fields=['school_class', 'is_former_student', 'graduation_year'])
            for s in to_repeat:
                old = StudentClassEnrollment.objects.filter(student=s, school_class=school_class).first()
                if old:
                    old.status = 'echec'
                    old.left_at = timezone.now()
                    old.save(update_fields=['status', 'left_at'])
                else:
                    StudentClassEnrollment.objects.create(
                        student=s, school_class=school_class, status='echec', left_at=timezone.now(),
                    )
                StudentClassEnrollment.objects.create(student=s, school_class=repeat_class, status='active')
                s.school_class = repeat_class
                s.save(update_fields=['school_class'])
            return Response({
                'promoted': len(to_graduate),
                'repeated': len(to_repeat),
                'not_promoted': len(to_repeat),
                'graduated': True,
                'message': f"{len(to_graduate)} élève(s) sorti(s) de l'école. {len(to_repeat)} en échec (<50%), reprennent la même classe pour l'année {next_year}.",
            })

        # Promotion vers la classe suivante (non terminal)
        if to_promote:
            ncn = (school_class.next_class_name or '').strip()
            if not ncn:
                return Response(
                    {
                        'error': "La « classe suivante » (promotion) n'est pas définie pour cette classe.",
                        'detail': "L'administrateur peut l'ajouter dans la fiche de la classe (ex. 4ème CG pour 3ème CG).",
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
            target_class = SchoolClass.objects.filter(
                school=school_class.school, name=ncn, academic_year=next_year, is_active=True
            ).first()
            if not target_class:
                return Response(
                    {
                        'error': f"La classe cible « {ncn} » pour l'année {next_year} n'existe pas.",
                        'detail': "Créez d'abord cette classe pour l'année suivante avant de lancer la promotion.",
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
        else:
            target_class = None

        if to_repeat:
            repeat_class = SchoolClass.objects.filter(
                school=school_class.school, name=school_class.name, academic_year=next_year, is_active=True
            ).first()
            if not repeat_class:
                return Response(
                    {
                        'error': f"La classe « {school_class.name} » pour l'année {next_year} n'existe pas.",
                        'detail': "Créez cette classe pour l'année suivante afin que les élèves en échec (<50%) puissent la reprendre.",
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

        for s in to_promote:
            old = StudentClassEnrollment.objects.filter(student=s, school_class=school_class).first()
            if old:
                old.status = 'promoted'
                old.left_at = timezone.now()
                old.save(update_fields=['status', 'left_at'])
            else:
                StudentClassEnrollment.objects.create(
                    student=s, school_class=school_class, status='promoted', left_at=timezone.now(),
                )
            StudentClassEnrollment.objects.create(student=s, school_class=target_class, status='active')
            s.school_class = target_class
            s.save(update_fields=['school_class'])

        for s in to_repeat:
            old = StudentClassEnrollment.objects.filter(student=s, school_class=school_class).first()
            if old:
                old.status = 'echec'
                old.left_at = timezone.now()
                old.save(update_fields=['status', 'left_at'])
            else:
                StudentClassEnrollment.objects.create(
                    student=s, school_class=school_class, status='echec', left_at=timezone.now(),
                )
            StudentClassEnrollment.objects.create(student=s, school_class=repeat_class, status='active')
            s.school_class = repeat_class
            s.save(update_fields=['school_class'])

        msg = f"{len(to_promote)} élève(s) promu(s) vers {target_class.name} ({next_year})." if target_class else ""
        if to_repeat:
            msg += f" {len(to_repeat)} en échec (<50%), reprennent la même classe pour l'année {next_year}."
        if not msg:
            msg = "Aucun élève à traiter."
        return Response({
            'promoted': len(to_promote),
            'repeated': len(to_repeat),
            'not_promoted': len(to_repeat),
            'target_class': target_class.name if target_class else None,
            'target_year': next_year,
            'message': msg.strip(),
        })

    @action(detail=True, methods=['get'])
    def enrollments(self, request, pk=None):
        """
        Liste des inscriptions (parcours) dans cette classe : actifs, promus, diplômés, etc.
        Permet de garder l'historique dans l'ancienne classe après promotion.
        """
        from apps.accounts.models import Student

        school_class = self.get_object()
        if request.user.school and school_class.school_id != request.user.school_id:
            raise PermissionDenied("Cette classe n'appartient pas à votre école.")

        # Compléter: élèves avec school_class=cette classe mais sans enrollment (cas rare)
        for s in Student.objects.filter(school_class=school_class):
            StudentClassEnrollment.objects.get_or_create(
                student=s, school_class=school_class, defaults={'status': 'active'},
            )

        qs = StudentClassEnrollment.objects.filter(
            school_class=school_class
        ).select_related('student', 'student__user').order_by('-enrolled_at')
        return Response({
            'results': StudentClassEnrollmentSerializer(qs, many=True).data,
        })


class SubjectViewSet(viewsets.ModelViewSet):
    serializer_class = SubjectSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['school', 'is_active']
    search_fields = ['name', 'code']
    
    def get_queryset(self):
        queryset = Subject.objects.filter(is_active=True)
        # Filter by user's school
        if self.request.user.school:
            queryset = queryset.filter(school=self.request.user.school)
        # Filter by school if provided in query params
        school_id = self.request.query_params.get('school', None)
        if school_id:
            queryset = queryset.filter(school_id=school_id)
        return queryset
    
    def perform_create(self, serializer):
        """Création réservée à l'admin ou aux enseignants ; école = école de l'utilisateur."""
        if not getattr(self.request.user, 'is_admin', False) and not self.request.user.is_teacher:
            raise PermissionDenied("Seuls l'administrateur et les enseignants peuvent créer une matière.")
        if not self.request.user.school:
            raise ValidationError({
                'non_field_errors': ['Vous devez être associé à une école pour créer une matière. Veuillez contacter l\'administrateur système.']
            })
        serializer.save(school=self.request.user.school)


class ClassSubjectViewSet(viewsets.ModelViewSet):
    """
    Matières par classe avec note de base (période/interrogation et examen = 2×).
    Création, modification, suppression réservées au titulaire de la classe ou à l'admin.
    """
    serializer_class = ClassSubjectSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['school_class', 'subject']
    search_fields = ['subject__name', 'school_class__name']
    
    def get_queryset(self):
        qs = ClassSubject.objects.select_related(
            'school_class', 'school_class__titulaire', 'subject', 'teacher', 'teacher__user'
        ).all()
        if self.request.user.school:
            qs = qs.filter(school_class__school=self.request.user.school)
        if self.request.user.is_teacher and not getattr(self.request.user, 'is_admin', False):
            try:
                tp = self.request.user.teacher_profile
                # Titulaire: voit toutes les matières de ses classes. Assigné (teacher=): voit au moins ses matières (pour period_max en saisie de notes).
                qs = qs.filter(Q(school_class__titulaire=tp) | Q(teacher=tp))
            except Exception:
                qs = qs.none()
        return qs
    
    def _check_titulaire_or_admin(self, school_class):
        if getattr(self.request.user, 'is_admin', False):
            return
        if not self.request.user.is_teacher:
            raise PermissionDenied("Seul le titulaire de la classe ou l'admin peut gérer les matières de la classe.")
        if not school_class or not getattr(school_class, 'titulaire_id', None):
            raise PermissionDenied("Aucun titulaire défini pour cette classe. L'admin peut gérer les matières ou désigner un titulaire.")
        try:
            tp = self.request.user.teacher_profile
        except Exception:
            raise PermissionDenied("Profil enseignant introuvable.")
        if school_class.titulaire_id != tp.id:
            raise PermissionDenied("Seul le titulaire de cette classe peut créer, modifier ou supprimer ses matières.")
    
    def _validate_teacher_school(self, teacher, school_class):
        """L'enseignant assigné doit appartenir à la même école que la classe."""
        if not teacher or not school_class:
            return
        t_school = getattr(teacher.user, 'school_id', None) if teacher.user else None
        if t_school is not None and school_class.school_id != t_school:
            raise ValidationError({
                'teacher': "L'enseignant assigné doit appartenir à la même école que la classe."
            })

    def perform_create(self, serializer):
        school_class = serializer.validated_data.get('school_class')
        self._check_titulaire_or_admin(school_class)
        teacher = serializer.validated_data.get('teacher')
        self._validate_teacher_school(teacher, school_class)
        serializer.save()

    def perform_update(self, serializer):
        self._check_titulaire_or_admin(serializer.instance.school_class)
        teacher = serializer.validated_data.get('teacher', serializer.instance.teacher)
        self._validate_teacher_school(teacher, serializer.instance.school_class)
        super().perform_update(serializer)
    
    def perform_destroy(self, instance):
        self._check_titulaire_or_admin(instance.school_class)
        super().perform_destroy(instance)
