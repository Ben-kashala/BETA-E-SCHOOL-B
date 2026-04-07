import logging
from decimal import Decimal
from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.exceptions import PermissionDenied
from rest_framework.pagination import PageNumberPagination
from datetime import date as date_type, timedelta
from django.db.models import Avg, Count, F, Q
from django.shortcuts import get_object_or_404
from .models import AcademicYear, Grade, GradeBulletin, Attendance, DisciplineRecord, DisciplineRequest, ReportCard, EvaluationGrade
from apps.accounts.models import Student
from .filters import GradeBulletinFilterSet, AttendanceFilterSet
from .serializers import (
    AcademicYearSerializer, GradeSerializer, GradeBulletinSerializer,
    AttendanceSerializer, DisciplineRecordSerializer, DisciplineRequestSerializer, ReportCardSerializer,
    EvaluationGradeSerializer,
)
from apps.schools.models import SchoolClass, ClassSubject, StudentClassEnrollment


class GradePagination(PageNumberPagination):
    page_size = 50
    page_size_query_param = 'page_size'
    max_page_size = 500


class AcademicYearViewSet(viewsets.ModelViewSet):
    queryset = AcademicYear.objects.all()
    serializer_class = AcademicYearSerializer
    permission_classes = [permissions.IsAuthenticated]
    pagination_class = None  # liste complète pour filtres (années souvent < 50)
    filterset_fields = ['school', 'is_current']
    search_fields = ['name']
    
    def get_queryset(self):
        queryset = AcademicYear.objects.all()
        if self.request.user.school:
            queryset = queryset.filter(school=self.request.user.school)
        return queryset
    
    def perform_create(self, serializer):
        """Automatically assign the academic year to the user's school"""
        serializer.save(school=self.request.user.school)
    
    @action(detail=False, methods=['get'])
    def available(self, request):
        """
        Toutes les années scolaires utilisées : AcademicYear + SchoolClass + GradeBulletin.
        Réponse : { years: ["2026-2027", "2025-2026", ...], current: "2025-2026" | null }.
        Si la liste est vide, le frontend garde une saisie libre.
        """
        school = getattr(request.user, 'school', None)
        names = set()
        current = None
        if school:
            for n in AcademicYear.objects.filter(school=school).values_list('name', flat=True).distinct():
                if n:
                    names.add(str(n).strip())
            cur = AcademicYear.objects.filter(school=school, is_current=True).first()
            if cur and cur.name:
                current = str(cur.name).strip()
        # SchoolClass (toutes, pas seulement is_active) pour l'école
        if school:
            for n in SchoolClass.objects.filter(school=school).values_list('academic_year', flat=True).distinct():
                if n:
                    names.add(str(n).strip())
        # GradeBulletin : années présentes dans les bulletins des élèves de l'école
        if school:
            for n in GradeBulletin.objects.filter(student__user__school=school).values_list('academic_year', flat=True).distinct():
                if n:
                    names.add(str(n).strip())
        years = sorted(names, reverse=True) if names else []
        return Response({'years': years, 'current': current})


class GradeViewSet(viewsets.ModelViewSet):
    serializer_class = GradeSerializer
    permission_classes = [permissions.IsAuthenticated]
    pagination_class = GradePagination
    filterset_fields = ['student', 'student__school_class', 'subject', 'academic_year', 'term']
    
    def get_queryset(self):
        try:
            queryset = Grade.objects.select_related('student__user', 'student__parent', 'subject', 'teacher__user').all()
            if self.request.user.school:
                queryset = queryset.filter(student__user__school=self.request.user.school)
            # Les parents ne peuvent voir que les notes de leurs enfants
            if self.request.user.is_parent:
                # Filtrer par parent de l'élève spécifique
                queryset = queryset.filter(student__parent=self.request.user)
                # Si un paramètre student est fourni, filtrer aussi par cet étudiant spécifique
                student_id = self.request.query_params.get('student')
                if student_id:
                    try:
                        queryset = queryset.filter(student_id=int(student_id))
                    except (ValueError, TypeError):
                        pass  # Ignorer si student_id n'est pas un entier valide
            # Les élèves ne peuvent voir que leurs propres notes
            elif self.request.user.is_student:
                queryset = queryset.filter(student__user=self.request.user)
            return queryset.order_by('-academic_year', 'term', 'subject__name')
        except Exception as e:
            import logging
            logger = logging.getLogger(__name__)
            logger.error(f"Erreur dans get_queryset de GradeViewSet: {str(e)}")
            import traceback
            traceback.print_exc()
            # Retourner un queryset vide en cas d'erreur
            return Grade.objects.none()
    
    def list(self, request, *args, **kwargs):
        """Remplacer list pour gérer les erreurs de manière appropriée"""
        try:
            return super().list(request, *args, **kwargs)
        except Exception as e:
            import logging
            logger = logging.getLogger(__name__)
            logger.error(f"Erreur dans list de GradeViewSet: {str(e)}")
            import traceback
            traceback.print_exc()
            from rest_framework.response import Response
            from rest_framework import status
            return Response({'results': [], 'count': 0}, status=status.HTTP_200_OK)
    
    def create(self, request, *args, **kwargs):
        """Remplacer create pour gérer les erreurs de manière appropriée"""
        try:
            return super().create(request, *args, **kwargs)
        except Exception as e:
            import logging
            logger = logging.getLogger(__name__)
            logger.error(f"Erreur lors de la création d'une note: {str(e)}")
            import traceback
            logger.error(traceback.format_exc())
            from rest_framework.response import Response
            from rest_framework import status
            return Response(
                {'error': f'Erreur lors de la création de la note: {str(e)}', 'detail': str(e)},
                status=status.HTTP_400_BAD_REQUEST
            )
    
    def perform_create(self, serializer):
        """Assigner automatiquement l'enseignant si l'utilisateur est un enseignant"""
        try:
            if self.request.user.is_teacher:
                try:
                    teacher = self.request.user.teacher_profile
                    serializer.save(teacher=teacher)
                except Exception:
                    # Si le profil enseignant n'existe pas, enregistrer sans enseignant
                    serializer.save()
            else:
                serializer.save()
        except Exception as e:
            import logging
            logger = logging.getLogger(__name__)
            logger.error(f"Erreur dans perform_create de GradeViewSet: {str(e)}")
            import traceback
            logger.error(traceback.format_exc())
            raise
    
    @action(detail=False, methods=['get'])
    def statistics(self, request):
        """Obtenir les statistiques des notes pour les élèves"""
        student_id = request.query_params.get('student')
        academic_year = request.query_params.get('academic_year')
        term = request.query_params.get('term')
        
        queryset = self.get_queryset()
        if student_id:
            queryset = queryset.filter(student_id=student_id)
        if academic_year:
            queryset = queryset.filter(academic_year=academic_year)
        if term:
            queryset = queryset.filter(term=term)
        
        avg_score = queryset.aggregate(Avg('total_score'))['total_score__avg']
        total_subjects = queryset.count()
        
        return Response({
            'average_score': avg_score,
            'total_subjects': total_subjects,
            'grades': GradeSerializer(queryset, many=True).data
        })


class GradeBulletinViewSet(viewsets.ModelViewSet):
    """Notes conforme bulletin RDC: 2 semestres, 4 périodes (Trav. journaliers), 2 examens, T.G., repêchage."""
    serializer_class = GradeBulletinSerializer
    permission_classes = [permissions.IsAuthenticated]
    pagination_class = GradePagination
    filterset_class = GradeBulletinFilterSet

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        if not serializer.is_valid(raise_exception=False):
            err = serializer.errors
            # Si la seule erreur est "unique" sur (student, subject, academic_year), faire un upsert
            nfe = err.get('non_field_errors') or []
            is_unique_only = (
                list(err.keys()) == ['non_field_errors']
                and nfe
                and any(getattr(e, 'code', None) in ('unique', 'unique_together') for e in nfe)
            )
            if is_unique_only:
                sid = request.data.get('student')
                subid = request.data.get('subject')
                ac = request.data.get('academic_year')
                if sid is not None and subid is not None and ac:
                    # Recherche large (hors get_queryset) : le bulletin peut avoir school_class=null
                    q = GradeBulletin.objects.filter(
                        student_id=sid, subject_id=subid, academic_year=str(ac).strip()
                    )
                    if self.request.user.school:
                        q = q.filter(student__user__school=self.request.user.school)
                    existing = q.select_related('student', 'subject', 'school_class').first()
                    if existing:
                        sc = None
                        if request.data.get('school_class'):
                            sc = SchoolClass.objects.filter(pk=request.data['school_class']).first()
                        if not sc:
                            sc = existing.school_class or (existing.student.school_class if existing.student else None)
                        self._check_can_manage_grade_bulletin(sc, existing.subject)
                        grade_fields = {'s1_p1', 's1_p2', 's1_exam', 's2_p3', 's2_p4', 's2_exam', 'school_class'}
                        partial_data = {k: request.data[k] for k in grade_fields if k in request.data}
                        if partial_data:
                            upd = self.get_serializer(existing, data=partial_data, partial=True)
                            if upd.is_valid(raise_exception=False):
                                self.perform_update(upd)
                                return Response(upd.data, status=status.HTTP_200_OK)
                            return Response(upd.errors, status=status.HTTP_400_BAD_REQUEST)
            logging.getLogger(__name__).warning(
                "POST /academics/grade-bulletins/ 400: data=%s errors=%s",
                request.data, serializer.errors,
            )
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        self.perform_create(serializer)
        headers = self.get_success_headers(serializer.data)
        return Response(serializer.data, status=status.HTTP_201_CREATED, headers=headers)

    def get_queryset(self):
        try:
            qs = GradeBulletin.objects.select_related(
                'student__user', 'student__school_class', 'subject', 'school_class', 'teacher__user'
            ).prefetch_related('student__school_class__class_subjects').all()
            if self.request.user.school:
                qs = qs.filter(student__user__school=self.request.user.school)
            if self.request.user.is_parent:
                qs = qs.filter(student__parent=self.request.user)
            elif self.request.user.is_student:
                qs = qs.filter(student__user=self.request.user)
            elif self.request.user.is_teacher and not getattr(self.request.user, 'is_admin', False):
                # Titulaire OU enseignant assigné à cette matière dans cette classe (ClassSubject.teacher)
                try:
                    tp = self.request.user.teacher_profile
                    qs = qs.filter(
                        Q(school_class__titulaire=tp)
                        | Q(school_class__isnull=False, school_class__class_subjects__subject=F('subject'), school_class__class_subjects__teacher=tp)
                        | Q(school_class__isnull=True, student__school_class__titulaire=tp)
                    ).distinct()
                except Exception:
                    qs = qs.none()
            return qs
        except Exception as e:
            import logging
            logging.getLogger(__name__).error(f"GradeBulletinViewSet get_queryset: {e}")
            return GradeBulletin.objects.none()

    def _check_can_manage_grade_bulletin(self, school_class, subject):
        """Titulaire de la classe OU enseignant assigné à cette matière (ClassSubject.teacher) OU admin."""
        if getattr(self.request.user, 'is_admin', False):
            return
        if not self.request.user.is_teacher:
            raise PermissionDenied("Accès refusé.")
        try:
            tp = self.request.user.teacher_profile
        except Exception:
            raise PermissionDenied("Profil enseignant introuvable.")
        sc = school_class
        if not sc:
            raise PermissionDenied("La classe est requise pour gérer les notes.")
        if getattr(self.request.user, 'school', None) and sc.school_id != self.request.user.school_id:
            raise PermissionDenied("Cette classe n'appartient pas à votre école.")
        # 1) Titulaire de la classe → peut saisir toutes les matières de cette classe
        if getattr(sc, 'titulaire_id', None) is not None and sc.titulaire_id == tp.pk:
            return
        # 2) Enseignant assigné à cette matière dans cette classe (ClassSubject.teacher)
        if ClassSubject.objects.filter(school_class=sc, subject=subject, teacher=tp).exists():
            return
        if getattr(sc, 'titulaire_id', None) is None:
            raise PermissionDenied(
                "Aucun titulaire défini pour cette classe. L'administrateur peut en désigner un dans Gestion des classes (Admin > Classes)."
            )
        raise PermissionDenied(
            "Seul le titulaire de la classe ou l'enseignant assigné à cette matière peut gérer ces notes. "
            "Vérifiez que vous êtes bien titulaire de cette classe dans Gestion des classes, ou que la matière vous est assignée dans Matières par classe."
        )
    
    def perform_create(self, serializer):
        student = serializer.validated_data.get('student')
        subject = serializer.validated_data.get('subject')
        school_class = serializer.validated_data.get('school_class')
        if not school_class and self.request.data.get('school_class'):
            school_class = SchoolClass.objects.filter(pk=self.request.data['school_class']).first()
        if not school_class and student:
            school_class = getattr(student, 'school_class', None)
        self._check_can_manage_grade_bulletin(school_class, subject)
        save_kw = {}
        if self.request.user.is_teacher:
            try:
                save_kw['teacher'] = self.request.user.teacher_profile
            except Exception:
                pass
        if school_class and not serializer.validated_data.get('school_class'):
            save_kw['school_class'] = school_class
        elif student and getattr(student, 'school_class_id', None) and not serializer.validated_data.get('school_class'):
            save_kw['school_class'] = student.school_class
        serializer.save(**save_kw)

    def perform_update(self, serializer):
        inst = serializer.instance
        sc = serializer.validated_data.get('school_class') or getattr(inst, 'school_class', None)
        if not sc and getattr(inst, 'student', None):
            sc = getattr(inst.student, 'school_class', None)
        if not sc and self.request.data.get('school_class'):
            sc = SchoolClass.objects.filter(pk=self.request.data['school_class']).first()
        self._check_can_manage_grade_bulletin(sc, inst.subject)
        super().perform_update(serializer)

    def perform_destroy(self, instance):
        sc = instance.school_class or (instance.student.school_class if instance.student else None)
        self._check_can_manage_grade_bulletin(sc, instance.subject)
        super().perform_destroy(instance)
    
    @action(detail=False, methods=['get'])
    def class_ranking(self, request):
        """
        Classement des élèves d'une classe pour une année scolaire.
        GET ?school_class=<id>&academic_year=<année>
        Réservé au titulaire de la classe ou à l'admin.
        """
        from decimal import Decimal
        from apps.accounts.models import Student
        
        sc_id = request.query_params.get('school_class')
        ac_year = request.query_params.get('academic_year', '').strip()
        if not sc_id or not ac_year:
            return Response(
                {'error': 'school_class et academic_year sont requis.'},
                status=status.HTTP_400_BAD_REQUEST
            )
        school_class = get_object_or_404(SchoolClass, pk=sc_id)
        if request.user.school and school_class.school_id != request.user.school_id:
            raise PermissionDenied("Cette classe n'appartient pas à votre école.")
        # Permission: admin ou titulaire
        if not getattr(request.user, 'is_admin', False):
            try:
                tp = request.user.teacher_profile
                if not school_class.titulaire_id or school_class.titulaire_id != tp.id:
                    raise PermissionDenied("Seul le titulaire de la classe ou l'admin peut consulter le classement.")
            except Exception:
                raise PermissionDenied("Accès refusé.")
        
        # Matières de la classe (ClassSubject) pour le calcul du max
        class_subjects = ClassSubject.objects.filter(school_class=school_class).select_related('subject')
        max_per_subject = {cs.subject_id: (cs.period_max or 20) * 8 for cs in class_subjects}
        subject_ids = list(max_per_subject.keys())
        total_max = sum(max_per_subject.values()) or 1
        
        # Inclure tous les élèves ayant un parcours dans cette classe (actifs, promus,
        # diplômés, désinscrits) pour retracer l'historique et afficher les promus (ex. Virginie en 4ème).
        # Repli: inclure aussi les élèves ayant des bulletins pour cette classe+année (données sans enrollment).
        # Aucun filtre sur le statut des enrollments : actifs, promus, diplômés, désinscrits doivent apparaître.
        enrollment_ids = set(StudentClassEnrollment.objects.filter(
            school_class=school_class
        ).values_list('student_id', flat=True).distinct())
        bulletin_ids = set(GradeBulletin.objects.filter(
            school_class=school_class, academic_year=ac_year
        ).values_list('student_id', flat=True).distinct())
        # Ne pas ajouter school_class=null ici : les mêmes matières existent dans d'autres classes (3ème, 5ème…),
        # on inclurait à tort des élèves qui ne sont pas de cette classe.
        student_ids = list(enrollment_ids | bulletin_ids)
        students = Student.objects.filter(id__in=student_ids).select_related('user')
        # Notes pour le calcul : school_class=classe OU school_class=null (legacy) pour ne pas perdre les points.
        bulletins = GradeBulletin.objects.filter(
            student__in=students,
            academic_year=ac_year,
            subject_id__in=subject_ids,
        ).filter(Q(school_class=school_class) | Q(school_class__isnull=True)).select_related('student', 'subject')
        
        by_student = {}
        for b in bulletins:
            sid = b.student_id
            if sid not in by_student:
                by_student[sid] = {}
            by_student[sid][b.subject_id] = (b.total_general or Decimal('0'))
        
        rows = []
        for s in students:
            pts = sum(by_student.get(s.id, {}).values())
            pct = (float(pts) / total_max * 100) if total_max else 0
            name = (s.user.get_full_name() or s.user.username) if s.user else f'Élève #{s.id}'
            rows.append({
                'student_id': s.id,
                'student_name': name,
                'user_name': getattr(s, 'user_name', None) or name,
                'matricule': getattr(s, 'student_id', None) or '',
                'total_points': float(pts),
                'max_points': total_max,
                'percentage': round(pct, 2),
            })
        rows.sort(key=lambda x: (-x['total_points'], x['student_name']))
        for i, r in enumerate(rows, 1):
            r['rank'] = i
        
        return Response({
            'school_class': school_class.name,
            'academic_year': ac_year,
            'results': rows,
        })


class AttendanceViewSet(viewsets.ModelViewSet):
    serializer_class = AttendanceSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_class = AttendanceFilterSet
    
    def create(self, request, *args, **kwargs):
        """Upsert : une présence par (student, school_class, date). Si existe → mise à jour."""
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        v = serializer.validated_data
        existing = Attendance.objects.filter(
            student=v['student'], school_class=v['school_class'], date=v['date']
        ).first()
        if existing:
            for k in ['status', 'subject', 'notes']:
                if k in v:
                    setattr(existing, k, v[k])
            existing.save()
            out = AttendanceSerializer(existing).data
            return Response(out, status=status.HTTP_200_OK)
        self.perform_create(serializer)
        headers = self.get_success_headers(serializer.data)
        return Response(serializer.data, status=status.HTTP_201_CREATED, headers=headers)
    
    def get_queryset(self):
        try:
            queryset = Attendance.objects.select_related('student__user', 'school_class', 'subject', 'teacher__user').all()
            if self.request.user.school:
                queryset = queryset.filter(student__user__school=self.request.user.school)
            # Les parents ne peuvent voir que les présences de leurs enfants
            if self.request.user.is_parent:
                queryset = queryset.filter(student__parent=self.request.user)
            # Les élèves ne peuvent voir que leurs propres présences
            elif self.request.user.is_student:
                queryset = queryset.filter(student__user=self.request.user)
            return queryset
        except Exception as e:
            import logging
            logger = logging.getLogger(__name__)
            logger.error(f"Erreur dans get_queryset de AttendanceViewSet: {str(e)}")
            import traceback
            traceback.print_exc()
            # Retourner un queryset vide en cas d'erreur pour éviter les erreurs
            return Attendance.objects.none()
    
    def perform_create(self, serializer):
        """Assigner automatiquement l'enseignant si l'utilisateur est un enseignant"""
        if self.request.user.is_teacher:
            try:
                teacher = self.request.user.teacher_profile
                serializer.save(teacher=teacher)
            except Exception:
                # Si le profil enseignant n'existe pas, enregistrer sans enseignant
                serializer.save()
        else:
            serializer.save()
    
    @action(detail=False, methods=['get'])
    def statistics(self, request):
        """Obtenir les statistiques de présence"""
        student_id = request.query_params.get('student')
        start_date = request.query_params.get('start_date')
        end_date = request.query_params.get('end_date')
        
        queryset = self.get_queryset()
        if student_id:
            queryset = queryset.filter(student_id=student_id)
        if start_date:
            queryset = queryset.filter(date__gte=start_date)
        if end_date:
            queryset = queryset.filter(date__lte=end_date)
        
        total = queryset.count()
        present = queryset.filter(status='PRESENT').count()
        absent = queryset.filter(status='ABSENT').count()
        late = queryset.filter(status='LATE').count()
        
        attendance_rate = (present / total * 100) if total > 0 else 0
        
        return Response({
            'total': total,
            'present': present,
            'absent': absent,
            'late': late,
            'attendance_rate': round(attendance_rate, 2)
        })

    @action(detail=False, methods=['get'], url_path='attendance_summary')
    def attendance_summary(self, request):
        """
        Situation des présences par semaine ou par mois pour tous les élèves de la classe.
        Réservé au titulaire de la classe ou à l'admin.
        GET ?school_class=<id>&period=week|month|day&date=YYYY-MM-DD
        period=day : uniquement la date du jour (présence du jour).
        """
        sc_id = request.query_params.get('school_class')
        period = (request.query_params.get('period') or '').strip().lower()
        date_str = (request.query_params.get('date') or '').strip()
        if not sc_id or period not in ('week', 'month', 'day') or not date_str:
            return Response(
                {'error': 'school_class, period (week|month|day) et date (YYYY-MM-DD) sont requis.'},
                status=status.HTTP_400_BAD_REQUEST
            )
        try:
            ref = date_type.fromisoformat(date_str)
        except ValueError:
            return Response({'error': 'date invalide (attendu YYYY-MM-DD).'}, status=status.HTTP_400_BAD_REQUEST)
        school_class = get_object_or_404(SchoolClass, pk=sc_id)
        if request.user.school and school_class.school_id != request.user.school_id:
            raise PermissionDenied("Cette classe n'appartient pas à votre école.")
        if not getattr(request.user, 'is_admin', False):
            try:
                tp = request.user.teacher_profile
                if not school_class.titulaire_id or school_class.titulaire_id != tp.id:
                    raise PermissionDenied("Seul le titulaire de la classe ou l'admin peut consulter cette vue.")
            except Exception:
                raise PermissionDenied("Accès refusé.")
        if period == 'day':
            start = end = ref
        elif period == 'week':
            # Lundi à dimanche de la semaine contenant ref
            start = ref - timedelta(days=ref.weekday())
            end = start + timedelta(days=6)
        else:
            # month : 1er et dernier jour du mois
            start = ref.replace(day=1)
            if ref.month == 12:
                end = ref.replace(day=31)
            else:
                end = (ref.replace(month=ref.month + 1, day=1) - timedelta(days=1))
        date_after, date_before = start.isoformat(), end.isoformat()
        enrollment_ids = set(StudentClassEnrollment.objects.filter(
            school_class=school_class
        ).values_list('student_id', flat=True).distinct())
        student_ids = list(enrollment_ids) if enrollment_ids else []
        if not student_ids:
            return Response({
                'period': period,
                'date': date_str,
                'date_after': date_after,
                'date_before': date_before,
                'school_class_name': school_class.name,
                'results': [],
            })
        students = Student.objects.filter(id__in=student_ids).select_related('user')
        attendances = Attendance.objects.filter(
            student_id__in=student_ids,
            school_class=school_class,
            date__gte=start,
            date__lte=end,
        ).values('student_id', 'status').annotate(n=Count('id'))
        by_student = {s.id: {'present': 0, 'absent': 0, 'late': 0, 'excused': 0, 'total': 0} for s in students}
        for row in attendances:
            sid = row['student_id']
            if sid not in by_student:
                by_student[sid] = {'present': 0, 'absent': 0, 'late': 0, 'excused': 0, 'total': 0}
            by_student[sid]['total'] += row['n']
            k = row['status'].lower()
            if k == 'present':
                by_student[sid]['present'] += row['n']
            elif k == 'absent':
                by_student[sid]['absent'] += row['n']
            elif k == 'late':
                by_student[sid]['late'] += row['n']
            elif k == 'excused':
                by_student[sid]['excused'] += row['n']
        results = []
        for s in students:
            rec = by_student.get(s.id, {'present': 0, 'absent': 0, 'late': 0, 'excused': 0, 'total': 0})
            name = (s.user.get_full_name() or s.user.username) if s.user else f'Élève #{s.id}'
            results.append({
                'student_id': s.id,
                'student_name': name,
                'matricule': getattr(s, 'student_id', None) or '',
                'present': rec['present'],
                'absent': rec['absent'],
                'late': rec['late'],
                'excused': rec['excused'],
                'total': rec['total'],
            })
        results.sort(key=lambda x: x['student_name'])
        return Response({
            'period': period,
            'date': date_str,
            'date_after': date_after,
            'date_before': date_before,
            'school_class_name': school_class.name,
            'results': results,
        })


class DisciplineRecordViewSet(viewsets.ModelViewSet):
    serializer_class = DisciplineRecordSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['student', 'school_class', 'type', 'severity', 'status', 'date']
    
    def get_queryset(self):
        queryset = DisciplineRecord.objects.all()
        if self.request.user.school:
            queryset = queryset.filter(student__user__school=self.request.user.school)
        # Les parents ne peuvent voir que les fiches de discipline de leurs enfants
        if self.request.user.is_parent:
            queryset = queryset.filter(student__parent=self.request.user)
        # Les élèves ne peuvent voir que leurs propres fiches de discipline
        elif self.request.user.is_student:
            queryset = queryset.filter(student__user=self.request.user)
        return queryset
    
    def perform_create(self, serializer):
        record = serializer.save(recorded_by=self.request.user, status='OPEN')
        from apps.communication.notifications import notify_discipline_record_created
        notify_discipline_record_created(record)

    @action(detail=True, methods=['post'])
    def resolve(self, request, pk=None):
        """Résoudre une fiche de discipline (Admin et Enseignant)"""
        record = self.get_object()
        
        # Vérifier les permissions (Admin, Enseignant, Chargé de discipline)
        if not (request.user.is_admin or request.user.is_teacher or request.user.is_discipline_officer):
            return Response(
                {'error': 'Vous n\'avez pas la permission de résoudre une fiche de discipline.'},
                status=status.HTTP_403_FORBIDDEN
            )
        
        resolution_notes = request.data.get('resolution_notes', '')
        
        from django.utils import timezone
        record.status = 'RESOLVED'
        record.resolution_notes = resolution_notes
        record.resolved_by = request.user
        record.resolved_at = timezone.now()
        record.save()
        
        serializer = self.get_serializer(record)
        return Response(serializer.data)
    
    @action(detail=True, methods=['post'])
    def close(self, request, pk=None):
        """Fermer une fiche de discipline (Admin uniquement)"""
        record = self.get_object()
        
        # Admins et chargés de discipline peuvent fermer
        if not (request.user.is_admin or request.user.is_discipline_officer):
            return Response(
                {'error': 'Seuls les administrateurs ou le chargé de discipline peuvent fermer une fiche.'},
                status=status.HTTP_403_FORBIDDEN
            )
        
        from django.utils import timezone
        record.status = 'CLOSED'
        record.closed_by = request.user
        record.closed_at = timezone.now()
        record.save()
        
        serializer = self.get_serializer(record)
        return Response(serializer.data)
    
    def get_serializer_class(self):
        """Utiliser un serializer différent selon l'action"""
        if self.action in ['create', 'update', 'partial_update']:
            return DisciplineRecordSerializer
        return DisciplineRecordSerializer


class DisciplineRequestViewSet(viewsets.ModelViewSet):
    serializer_class = DisciplineRequestSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['discipline_record', 'parent', 'request_type', 'status']
    
    def get_queryset(self):
        queryset = DisciplineRequest.objects.all()
        
        # Filtrer par école
        if self.request.user.school:
            queryset = queryset.filter(discipline_record__student__user__school=self.request.user.school)
        
        # Parents ne voient que leurs propres demandes
        if self.request.user.is_parent:
            queryset = queryset.filter(parent__user=self.request.user)
        
        # Admins et enseignants voient toutes les demandes de leur école
        return queryset
    
    def perform_create(self, serializer):
        # Vérifier que l'utilisateur est un parent
        if not self.request.user.is_parent:
            raise PermissionDenied("Seuls les parents peuvent créer des demandes de discipline")
        
        # Récupérer le profil parent
        try:
            parent = self.request.user.parent_profile
        except:
            raise PermissionDenied("Profil parent non trouvé")
        
        # Vérifier que la fiche de discipline appartient à un enfant du parent
        discipline_record = serializer.validated_data['discipline_record']
        if discipline_record.student.parent != self.request.user:
            raise PermissionDenied("Vous ne pouvez créer une demande que pour vos propres enfants")
        
        serializer.save(parent=parent, status='PENDING')
    
    @action(detail=True, methods=['post'])
    def approve(self, request, pk=None):
        """Approuver une demande (Admin uniquement)"""
        discipline_request = self.get_object()
        
        # Seuls les admins peuvent approuver
        if not (request.user.is_admin or request.user.is_discipline_officer):
            return Response(
                {'error': 'Seuls les administrateurs ou le chargé de discipline peuvent approuver une demande.'},
                status=status.HTTP_403_FORBIDDEN
            )
        
        response_text = request.data.get('response', 'Demande approuvée')
        
        from django.utils import timezone
        discipline_request.status = 'APPROVED'
        discipline_request.response = response_text
        discipline_request.responded_by = request.user
        discipline_request.responded_at = timezone.now()
        discipline_request.save()
        
        serializer = self.get_serializer(discipline_request)
        return Response(serializer.data)
    
    @action(detail=True, methods=['post'])
    def reject(self, request, pk=None):
        """Rejeter une demande (Admin uniquement)"""
        discipline_request = self.get_object()
        
        # Seuls les admins peuvent rejeter
        if not (request.user.is_admin or request.user.is_discipline_officer):
            return Response(
                {'error': 'Seuls les administrateurs ou le chargé de discipline peuvent rejeter une demande.'},
                status=status.HTTP_403_FORBIDDEN
            )
        
        response_text = request.data.get('response', 'Demande rejetée')
        
        from django.utils import timezone
        discipline_request.status = 'REJECTED'
        discipline_request.response = response_text
        discipline_request.responded_by = request.user
        discipline_request.responded_at = timezone.now()
        discipline_request.save()
        
        serializer = self.get_serializer(discipline_request)
        return Response(serializer.data)


class ReportCardViewSet(viewsets.ModelViewSet):
    serializer_class = ReportCardSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['student', 'academic_year', 'term', 'is_published']
    
    def get_queryset(self):
        queryset = ReportCard.objects.all()
        if self.request.user.school:
            queryset = queryset.filter(student__user__school=self.request.user.school)
        # Les parents ne peuvent voir que les bulletins de leurs enfants
        if self.request.user.is_parent:
            queryset = queryset.filter(student__parent=self.request.user)
        # Les élèves ne peuvent voir que leurs propres bulletins
        elif self.request.user.is_student:
            queryset = queryset.filter(student__user=self.request.user)
        return queryset
    
    @action(detail=True, methods=['get'])
    def download_pdf(self, request, pk=None):
        """Télécharge le bulletin en PDF. Régénération à chaque téléchargement. Format annuel RDC pour toutes les périodes (T1, T2, T3, AN)."""
        report_card = self.get_object()
        from .utils import generate_bulletin_rdc_pdf
        from django.http import FileResponse
        try:
            pdf_file = generate_bulletin_rdc_pdf(report_card)
            report_card.pdf_file = pdf_file
            report_card.save(update_fields=['pdf_file'])
        except Exception as e:
            logging.getLogger(__name__).exception("download_pdf: %s", e)
            return Response({'error': 'Échec de la génération du PDF', 'detail': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
        return FileResponse(report_card.pdf_file.open(), content_type='application/pdf')
