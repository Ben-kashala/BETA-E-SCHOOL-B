from decimal import Decimal
from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from django.db.models import Q
from .models import EvaluationGrade, GradeBulletin
from .serializers import EvaluationGradeSerializer
from .views import GradePagination
from apps.schools.models import SchoolClass


class EvaluationGradeViewSet(viewsets.ModelViewSet):
    """
    Évaluations détaillées (devoirs, interrogations, examens) utilisées pour alimenter le bulletin RDC.
    """
    serializer_class = EvaluationGradeSerializer
    permission_classes = [permissions.IsAuthenticated]
    pagination_class = GradePagination
    filterset_fields = ['student', 'subject', 'school_class', 'academic_year', 'semester', 'period', 'eval_type']

    def get_queryset(self):
        qs = EvaluationGrade.objects.select_related(
            'student__user', 'subject', 'school_class'
        ).all()
        user = self.request.user
        if user.school:
            qs = qs.filter(student__user__school=user.school)
        if user.is_teacher and not getattr(user, 'is_admin', False):
            try:
                tp = user.teacher_profile
            except Exception:
                return EvaluationGrade.objects.none()
            class_ids = SchoolClass.objects.filter(
                Q(titulaire=tp) | Q(class_subjects__teacher=tp)
            ).values_list('id', flat=True)
            qs = qs.filter(school_class_id__in=class_ids).distinct()
        elif user.is_parent:
            qs = qs.filter(student__parent=user)
        elif user.is_student:
            qs = qs.filter(student__user=user)
        return qs

    def perform_create(self, serializer):
        data = serializer.validated_data
        sc = data.get('school_class')
        student = data.get('student')
        if not sc and student and getattr(student, 'school_class', None):
            serializer.save(school_class=student.school_class)
        else:
            serializer.save()

    @action(detail=False, methods=['post'], url_path='aggregate-to-bulletin')
    def aggregate_to_bulletin(self, request):
        """
        Agrège les évaluations et renseigne les champs du bulletin (s1_p1, s1_exam, etc.) pour chaque élève.

        Payload:
        - academic_year
        - school_class
        - subject
        - semester: "S1" | "S2"
        - period: entier (1 à 4)
        - target_field: champ GradeBulletin (ex: "s1_p1", "s1_exam")
        - eval_types: ["HOMEWORK","QUIZ","EXAM"]
        """
        data = request.data
        try:
            academic_year = str(data.get('academic_year', '')).strip()
            school_class_id = int(data.get('school_class'))
            subject_id = int(data.get('subject'))
            semester = str(data.get('semester', '')).strip()
            period = int(data.get('period'))
            target_field = str(data.get('target_field', '')).strip()
            eval_types = data.get('eval_types') or []
        except (TypeError, ValueError):
            return Response({'detail': 'Paramètres invalides.'}, status=status.HTTP_400_BAD_REQUEST)

        if semester not in ('S1', 'S2') or period < 1 or period > 4:
            return Response({'detail': 'Semestre ou période invalide.'}, status=status.HTTP_400_BAD_REQUEST)
        if target_field not in ('s1_p1', 's1_p2', 's1_exam', 's2_p3', 's2_p4', 's2_exam'):
            return Response({'detail': 'Champ cible invalide.'}, status=status.HTTP_400_BAD_REQUEST)

        qs = self.get_queryset().filter(
            academic_year=academic_year,
            school_class_id=school_class_id,
            subject_id=subject_id,
            semester=semester,
            period=period,
            eval_type__in=eval_types,
        )
        if not qs.exists():
            return Response({'detail': 'Aucune évaluation à agréger.'}, status=status.HTTP_200_OK)

        by_student: dict[int, list[Decimal]] = {}
        for ev in qs:
            try:
                score20 = (Decimal(str(ev.score)) / Decimal(str(ev.max_score or 1))) * Decimal('20')
            except Exception:
                score20 = Decimal('0')
            arr = by_student.setdefault(ev.student_id, [])
            arr.append(score20)

        updated = 0
        for sid, vals in by_student.items():
            if not vals:
                continue
            avg = sum(vals) / Decimal(len(vals))
            gb, _ = GradeBulletin.objects.get_or_create(
                student_id=sid,
                subject_id=subject_id,
                academic_year=academic_year,
                defaults={'school_class_id': school_class_id},
            )
            if not gb.school_class_id:
                gb.school_class_id = school_class_id
            setattr(gb, target_field, avg)
            gb.save()
            updated += 1

        return Response({'detail': f'Bulletins mis à jour pour {updated} élève(s).'}, status=status.HTTP_200_OK)

