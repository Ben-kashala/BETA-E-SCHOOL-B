import json
from difflib import SequenceMatcher

from django.db.models import Q
from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.parsers import MultiPartParser, FormParser, JSONParser
from django.utils import timezone
from .models import Course, Assignment, AssignmentQuestion, AssignmentSubmission, Quiz, QuizQuestion, QuizAttempt, QuizAnswer
from .serializers import (
    CourseSerializer, AssignmentSerializer, AssignmentQuestionSerializer, AssignmentSubmissionSerializer,
    QuizSerializer, QuizQuestionSerializer, QuizAttemptSerializer, QuizAnswerSerializer
)


def _evaluate_answer(question_type, student_answer, correct_answer, points):
    """Évalue une réponse (quiz ou devoir). Utilise la similarité pour TEXT/SHORT_ANSWER/ESSAY."""
    ans = (student_answer or '').strip()
    correct = (correct_answer or '').strip()
    pts = float(points or 0)

    if question_type in ('SINGLE_CHOICE', 'MULTIPLE_CHOICE'):
        is_correct = ans.upper() == correct.upper()
        return is_correct, pts if is_correct else 0
    if question_type == 'TRUE_FALSE':
        is_correct = ans.lower() == correct.lower()
        return is_correct, pts if is_correct else 0
    if question_type in ('TEXT', 'SHORT_ANSWER', 'ESSAY'):
        if correct and ans:
            ratio = SequenceMatcher(None, ans.lower(), correct.lower()).ratio()
            if ratio >= 0.65:
                return True, pts
            if ratio >= 0.4:
                return False, round(pts * ratio, 2)
        else:
            is_correct = not ans and not correct
            return is_correct, pts if is_correct else 0
        return False, 0
    if question_type == 'NUMBER':
        try:
            is_correct = float(ans) == float(correct)
            return is_correct, pts if is_correct else 0
        except (ValueError, TypeError):
            return False, 0
    is_correct = ans == correct
    return is_correct, pts if is_correct else 0


class CourseViewSet(viewsets.ModelViewSet):
    serializer_class = CourseSerializer
    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser, JSONParser]
    filterset_fields = ['subject', 'school_class', 'teacher', 'academic_year', 'is_published']
    search_fields = ['title', 'description']
    
    def get_queryset(self):
        user = self.request.user
        school = getattr(user, 'school', None)
        base = Course.objects.all()
        if school:
            base = base.filter(school_class__school=school)
        if getattr(user, 'is_admin', False):
            return base
        if user.is_teacher:
            try:
                return base.filter(teacher=user.teacher_profile)
            except Exception:
                return Course.objects.none()
        base = base.filter(is_published=True)
        if user.is_student:
            try:
                return base.filter(school_class=user.student_profile.school_class)
            except Exception:
                return Course.objects.none()
        return base
    
    def perform_create(self, serializer):
        """Enseignant : assigné automatiquement ; Admin : enseignant depuis le formulaire."""
        if getattr(self.request.user, 'is_admin', False) and serializer.validated_data.get('teacher'):
            serializer.save()
        elif self.request.user.is_teacher:
            try:
                serializer.save(teacher=self.request.user.teacher_profile)
            except Exception:
                from rest_framework.exceptions import ValidationError
                raise ValidationError({'teacher': 'Vous devez avoir un profil enseignant pour créer un cours.'})
        else:
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied('Seuls les enseignants ou l\'admin peuvent créer des cours.')


class AssignmentViewSet(viewsets.ModelViewSet):
    serializer_class = AssignmentSerializer
    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser, JSONParser]  # Support pour les fichiers
    filterset_fields = ['subject', 'school_class', 'teacher', 'academic_year', 'is_published']
    search_fields = ['title', 'description']
    
    def get_queryset(self):
        """
        Accès aux devoirs limité à :
        - Admin école : tous les devoirs de l'école
        - Enseignant créateur : les devoirs qu'il a créés
        - Titulaire de la classe : les devoirs des classes dont il est titulaire
        - Élèves : les devoirs publiés de leur classe
        """
        user = self.request.user
        school = getattr(user, 'school', None)
        if not school:
            return Assignment.objects.none()
        base = Assignment.objects.filter(
            school_class__school=school
        ).select_related('school_class', 'teacher', 'teacher__user', 'subject')

        if getattr(user, 'is_admin', False):
            return base
        if user.is_teacher:
            try:
                teacher_profile = user.teacher_profile
                return base.filter(
                    Q(teacher=teacher_profile) | Q(school_class__titulaire=teacher_profile)
                )
            except Exception:
                return Assignment.objects.none()
        if user.is_student:
            try:
                my_class = user.student_profile.school_class
                return base.filter(school_class=my_class, is_published=True)
            except Exception:
                return Assignment.objects.none()
        return Assignment.objects.none()
    
    def perform_create(self, serializer):
        """Assigner automatiquement l'enseignant connecté"""
        if self.request.user.is_teacher:
            try:
                teacher_profile = self.request.user.teacher_profile
                serializer.save(teacher=teacher_profile)
            except:
                from rest_framework.exceptions import ValidationError
                raise ValidationError({'teacher': 'Vous devez avoir un profil enseignant pour créer un devoir.'})
        else:
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied('Seuls les enseignants peuvent créer des devoirs.')

    @action(detail=True, methods=['get', 'post'], url_path='questions')
    def questions(self, request, pk=None):
        """Liste (GET) ou création (POST) des questions du devoir."""
        assignment = self.get_object()
        if request.method == 'GET':
            qs = AssignmentQuestion.objects.filter(assignment=assignment).order_by('order')
            return Response(AssignmentQuestionSerializer(qs, many=True).data)
        data = {**request.data, 'assignment': assignment.id}
        ser = AssignmentQuestionSerializer(data=data)
        ser.is_valid(raise_exception=True)
        ser.save()
        return Response(ser.data, status=status.HTTP_201_CREATED)
    
    @action(detail=True, methods=['post'])
    def submit(self, request, pk=None):
        """Submit an assignment. Une seule soumission autorisée sauf si l'enseignant a autorisé une nouvelle."""
        assignment = self.get_object()
        student = request.user.student_profile

        existing = AssignmentSubmission.objects.filter(
            assignment=assignment,
            student=student,
        ).first()

        if existing and not existing.allow_resubmit:
            return Response(
                {'detail': 'Une seule soumission est autorisée pour ce devoir. Demandez à votre enseignant d\'autoriser une nouvelle soumission.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        submission, created = AssignmentSubmission.objects.get_or_create(
            assignment=assignment,
            student=student,
            defaults={
                'submission_text': request.data.get('submission_text', ''),
                'submission_file': request.FILES.get('submission_file'),
            }
        )

        if not created:
            submission.submission_text = request.data.get('submission_text', submission.submission_text)
            if 'submission_file' in request.FILES:
                submission.submission_file = request.FILES['submission_file']
            submission.allow_resubmit = False  # une seule nouvelle soumission après autorisation
            submission.save()

        # Check if late
        if timezone.now() > assignment.due_date:
            submission.status = 'LATE'
            submission.save()

        # Évaluation automatique (même logique que quiz, similarité pour TEXT) + answer_grades par question
        if submission.submission_text:
            try:
                answers_dict = json.loads(submission.submission_text)
            except (json.JSONDecodeError, TypeError):
                answers_dict = {}
            questions = AssignmentQuestion.objects.filter(assignment=assignment).order_by('order')
            auto_score = 0
            answer_grades = {}
            for q in questions:
                ans = answers_dict.get(str(q.id)) or answers_dict.get(q.id) or ''
                is_correct, pts = _evaluate_answer(q.question_type, ans, q.correct_answer, q.points)
                auto_score += pts
                answer_grades[str(q.id)] = {'points_earned': float(pts), 'teacher_feedback': ''}
            submission.answer_grades = answer_grades
            submission.score = round(auto_score, 2)
            submission.save()

        return Response(AssignmentSubmissionSerializer(submission).data, status=status.HTTP_201_CREATED)


class AssignmentQuestionViewSet(viewsets.ModelViewSet):
    """CRUD sur une question de devoir (update/delete). List/create via assignment action."""
    serializer_class = AssignmentQuestionSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        school = getattr(user, 'school', None)
        if not school:
            return AssignmentQuestion.objects.none()
        base = Assignment.objects.filter(school_class__school=school)
        if getattr(user, 'is_admin', False):
            pass
        elif user.is_teacher:
            try:
                tp = user.teacher_profile
                base = base.filter(Q(teacher=tp) | Q(school_class__titulaire=tp))
            except Exception:
                return AssignmentQuestion.objects.none()
        elif user.is_student:
            try:
                base = base.filter(school_class=user.student_profile.school_class, is_published=True)
            except Exception:
                return AssignmentQuestion.objects.none()
        else:
            return AssignmentQuestion.objects.none()
        return AssignmentQuestion.objects.filter(assignment__in=base).select_related('assignment')


class AssignmentSubmissionViewSet(viewsets.ModelViewSet):
    serializer_class = AssignmentSubmissionSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['assignment', 'student', 'status']

    def _allowed_assignment_queryset(self):
        """Même logique d'accès que AssignmentViewSet : admin, créateur, titulaire, élèves de la classe."""
        user = self.request.user
        school = getattr(user, 'school', None)
        if not school:
            return Assignment.objects.none()
        base = Assignment.objects.filter(school_class__school=school)
        if getattr(user, 'is_admin', False):
            return base
        if user.is_teacher:
            try:
                tp = user.teacher_profile
                return base.filter(Q(teacher=tp) | Q(school_class__titulaire=tp))
            except Exception:
                return Assignment.objects.none()
        if user.is_student:
            try:
                return base.filter(school_class=user.student_profile.school_class, is_published=True)
            except Exception:
                return Assignment.objects.none()
        return Assignment.objects.none()

    def get_queryset(self):
        allowed_assignments = self._allowed_assignment_queryset()
        queryset = AssignmentSubmission.objects.filter(
            assignment__in=allowed_assignments
        ).select_related('assignment', 'assignment__subject', 'student', 'student__user')
        if self.request.user.is_student:
            queryset = queryset.filter(student__user=self.request.user)
        return queryset
    
    @action(detail=True, methods=['post'])
    def grade(self, request, pk=None):
        """Grade an assignment submission - correction par question (comme Quiz)."""
        submission = self.get_object()
        submission.feedback = request.data.get('feedback', submission.feedback or '')
        answers = request.data.get('answers', [])
        if answers:
            answer_grades = dict(submission.answer_grades) if submission.answer_grades else {}
            total = 0
            for item in answers:
                qid = item.get('question_id')
                if qid is None:
                    continue
                pts = item.get('points_earned')
                try:
                    pts_num = float(pts) if pts is not None and pts != '' else 0
                except (ValueError, TypeError):
                    pts_num = 0
                fb = item.get('teacher_feedback', '') or ''
                answer_grades[str(qid)] = {'points_earned': pts_num, 'teacher_feedback': fb}
                total += pts_num
            submission.answer_grades = answer_grades
            submission.score = round(total, 2)
        else:
            score_val = request.data.get('score')
            if score_val is not None:
                try:
                    submission.score = float(score_val)
                except (ValueError, TypeError):
                    pass
        submission.graded_by = request.user.teacher_profile
        submission.graded_at = timezone.now()
        submission.status = 'GRADED'
        submission.save()
        return Response(AssignmentSubmissionSerializer(submission).data)

    @action(detail=True, methods=['post'])
    def allow_resubmit(self, request, pk=None):
        """Autoriser l'élève à soumettre à nouveau ce devoir (une seule fois). Réservé aux enseignants."""
        submission = self.get_object()
        if not request.user.is_teacher:
            return Response(
                {'detail': 'Seul l\'enseignant peut autoriser une nouvelle soumission.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        submission.allow_resubmit = True
        submission.save()
        return Response(AssignmentSubmissionSerializer(submission).data)


class QuizViewSet(viewsets.ModelViewSet):
    serializer_class = QuizSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['subject', 'school_class', 'teacher', 'academic_year', 'is_published']
    search_fields = ['title', 'description']

    def get_queryset(self):
        """
        Admin école : tous les quiz. Enseignant : ses quiz + classes dont il est titulaire.
        Élèves : quiz publiés de leur classe.
        """
        user = self.request.user
        school = getattr(user, 'school', None)
        if not school:
            return Quiz.objects.none()
        base = Quiz.objects.filter(school_class__school=school).select_related('school_class', 'teacher', 'subject')
        if getattr(user, 'is_admin', False):
            return base
        if user.is_teacher:
            try:
                tp = user.teacher_profile
                return base.filter(Q(teacher=tp) | Q(school_class__titulaire=tp))
            except Exception:
                return Quiz.objects.none()
        if user.is_student:
            try:
                return base.filter(school_class=user.student_profile.school_class, is_published=True)
            except Exception:
                return Quiz.objects.none()
        return Quiz.objects.none()

    def perform_create(self, serializer):
        if self.request.user.is_teacher:
            try:
                serializer.save(teacher=self.request.user.teacher_profile)
            except Exception:
                from rest_framework.exceptions import ValidationError
                raise ValidationError({'teacher': 'Profil enseignant requis.'})
        else:
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied('Réservé aux enseignants.')

    @action(detail=True, methods=['get', 'post'], url_path='questions')
    def questions(self, request, pk=None):
        """Liste (GET) ou création (POST) des questions du quiz."""
        quiz = self.get_object()
        if request.method == 'GET':
            qs = QuizQuestion.objects.filter(quiz=quiz).order_by('order')
            return Response(QuizQuestionSerializer(qs, many=True).data)
        data = {**request.data, 'quiz': quiz.id}
        ser = QuizQuestionSerializer(data=data)
        ser.is_valid(raise_exception=True)
        ser.save()
        return Response(ser.data, status=status.HTTP_201_CREATED)


class QuizQuestionViewSet(viewsets.ModelViewSet):
    """CRUD sur une question de quiz (retrieve, update, delete). List/create via quiz action."""
    serializer_class = QuizQuestionSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        school = getattr(user, 'school', None)
        if not school:
            return QuizQuestion.objects.none()
        base = Quiz.objects.filter(school_class__school=school)
        if getattr(user, 'is_admin', False):
            pass
        elif user.is_teacher:
            try:
                tp = user.teacher_profile
                base = base.filter(Q(teacher=tp) | Q(school_class__titulaire=tp))
            except Exception:
                return QuizQuestion.objects.none()
        else:
            return QuizQuestion.objects.none()
        return QuizQuestion.objects.filter(quiz__in=base).select_related('quiz')


class QuizAttemptViewSet(viewsets.ModelViewSet):
    serializer_class = QuizAttemptSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['quiz', 'student', 'is_passed']
    
    def get_queryset(self):
        queryset = QuizAttempt.objects.select_related('quiz', 'quiz__subject', 'student', 'student__user').all()
        school = getattr(self.request.user, 'school', None)
        if school:
            queryset = queryset.filter(student__user__school=school)
        # Students can only see their own attempts
        if self.request.user.is_student:
            queryset = queryset.filter(student__user=self.request.user)
        # Parents can see their children's attempts
        elif self.request.user.is_parent:
            queryset = queryset.filter(student__parent=self.request.user)
        return queryset
    
    @action(detail=False, methods=['post'])
    def start(self, request):
        """Start a quiz attempt. La limite de tentatives ne compte que les soumissions (pas les démarrages)."""
        quiz_id = request.data.get('quiz')
        student = request.user.student_profile

        quiz = Quiz.objects.get(id=quiz_id)

        # Seules les tentatives SOUMISES comptent pour la limite
        submitted_count = QuizAttempt.objects.filter(
            quiz=quiz, student=student, submitted_at__isnull=False
        ).count()

        if not quiz.allow_multiple_attempts and submitted_count > 0:
            return Response({'error': 'Plusieurs tentatives non autorisées'}, status=status.HTTP_400_BAD_REQUEST)

        if submitted_count >= quiz.max_attempts:
            return Response({'error': 'Nombre maximum de tentatives atteint'}, status=status.HTTP_400_BAD_REQUEST)

        # Si une tentative en cours (non soumise) existe, la reprendre au lieu d'en créer une nouvelle
        in_progress = QuizAttempt.objects.filter(
            quiz=quiz, student=student, submitted_at__isnull=True
        ).first()
        if in_progress:
            return Response(QuizAttemptSerializer(in_progress).data, status=status.HTTP_200_OK)

        attempt = QuizAttempt.objects.create(quiz=quiz, student=student)

        return Response(QuizAttemptSerializer(attempt).data, status=status.HTTP_201_CREATED)
    
    @action(detail=True, methods=['post'])
    def submit(self, request, pk=None):
        """Submit quiz answers and calculate score"""
        attempt = self.get_object()
        
        if getattr(attempt, 'is_completed', False) or attempt.submitted_at:
            return Response({'error': 'Tentative déjà soumise'}, status=status.HTTP_400_BAD_REQUEST)
        
        answers_data = request.data.get('answers', [])
        time_taken = request.data.get('time_taken_minutes', None)
        
        total_score = 0
        total_points = 0
        
        for answer_data in answers_data:
            question = QuizQuestion.objects.get(id=answer_data['question_id'])
            answer_text = answer_data.get('answer_text', '')
            if answer_text is None:
                answer_text = ''

            # Check if answer is correct (similarité pour TEXT/SHORT_ANSWER/ESSAY)
            is_correct = False
            points_earned = 0
            correct = (question.correct_answer or '').strip()
            ans = answer_text.strip()

            if question.question_type in ('SINGLE_CHOICE', 'MULTIPLE_CHOICE'):
                is_correct = ans.upper() == correct.upper()
                points_earned = float(question.points) if is_correct else 0
            elif question.question_type == 'TRUE_FALSE':
                is_correct = ans.lower() == correct.lower()
                points_earned = float(question.points) if is_correct else 0
            elif question.question_type in ('TEXT', 'SHORT_ANSWER', 'ESSAY'):
                # Similarité des mots/phrases au lieu de correspondance exacte
                if correct and ans:
                    ratio = SequenceMatcher(None, ans.lower(), correct.lower()).ratio()
                    # Seuil 0.65 = correct, entre 0.4 et 0.65 = points partiels
                    if ratio >= 0.65:
                        is_correct = True
                        points_earned = float(question.points)
                    elif ratio >= 0.4:
                        points_earned = round(float(question.points) * ratio, 2)
                else:
                    is_correct = not ans and not correct
                    points_earned = float(question.points) if is_correct else 0
            elif question.question_type == 'NUMBER':
                try:
                    is_correct = float(ans) == float(correct)
                    points_earned = float(question.points) if is_correct else 0
                except (ValueError, TypeError):
                    points_earned = 0
            else:
                is_correct = ans == correct
                points_earned = float(question.points) if is_correct else 0
            
            QuizAnswer.objects.create(
                attempt=attempt,
                question=question,
                answer_text=answer_text,
                is_correct=is_correct,
                points_earned=points_earned
            )
            
            total_score += points_earned
            total_points += question.points
        
        # Calculate percentage score
        percentage_score = (total_score / total_points * 100) if total_points > 0 else 0
        
        attempt.score = total_score
        attempt.submitted_at = timezone.now()
        if time_taken is not None and hasattr(attempt, 'time_taken_minutes'):
            attempt.time_taken_minutes = time_taken
        attempt.is_passed = attempt.quiz.passing_score is None or float(percentage_score) >= float(attempt.quiz.passing_score or 0)
        if hasattr(attempt, 'is_completed'):
            attempt.is_completed = True
        attempt.save()

        return Response(QuizAttemptSerializer(attempt).data)

    @action(detail=True, methods=['post'])
    def teacher_grade(self, request, pk=None):
        """Permet à l'enseignant de modifier les points et ajouter des commentaires."""
        attempt = self.get_object()
        if not request.user.is_teacher:
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied("Réservé aux enseignants.")

        answers_data = request.data.get('answers', [])
        total_score = 0
        total_points = 0

        for item in answers_data:
            answer_id = item.get('id')
            points = item.get('points_earned')
            feedback = item.get('teacher_feedback', '')

            if answer_id is None:
                continue
            try:
                answer = QuizAnswer.objects.get(id=answer_id, attempt=attempt)
            except QuizAnswer.DoesNotExist:
                continue

            if points is not None:
                try:
                    answer.points_earned = float(points)
                except (ValueError, TypeError):
                    pass
            if feedback is not None:
                answer.teacher_feedback = str(feedback).strip() or None
            answer.save()

        # Recalculer le score total de la tentative
        for ans in attempt.answers.all():
            total_score += float(ans.points_earned or 0)
        total_points = sum(float(q.points or 0) for q in attempt.quiz.questions.all())

        attempt.score = total_score
        percentage = (total_score / total_points * 100) if total_points > 0 else 0
        attempt.is_passed = attempt.quiz.passing_score is None or float(percentage) >= float(attempt.quiz.passing_score or 0)
        attempt.save()

        return Response(QuizAttemptSerializer(attempt).data)
