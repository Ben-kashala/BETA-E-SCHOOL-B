"""
Synchronisation des notes en ligne (devoirs, quiz) vers EvaluationGrade.
Les évaluations passées en ligne sont récupérées automatiquement et alimentent le bulletin.
"""
from decimal import Decimal

from .models import EvaluationGrade


def sync_assignment_submission_to_evaluation(submission):
    """
    Crée ou met à jour une EvaluationGrade à partir d'une soumission de devoir notée.
    À appeler après sauvegarde de AssignmentSubmission (status GRADED, score renseigné).
    """
    if not submission or not submission.assignment or not submission.student:
        return None
    assignment = submission.assignment
    if submission.score is None:
        return None
    score = Decimal(str(submission.score))
    max_score = assignment.total_points or 20
    max_score = Decimal(str(max_score)) if max_score else Decimal('20')
    semester = getattr(assignment, 'semester', 'S1') or 'S1'
    period = getattr(assignment, 'period', 1) or 1
    period = min(4, max(1, int(period)))
    eval_grade, created = EvaluationGrade.objects.update_or_create(
        source='ASSIGNMENT',
        source_id=str(submission.id),
        defaults={
            'student_id': submission.student_id,
            'subject_id': assignment.subject_id,
            'school_class_id': assignment.school_class_id,
            'academic_year': (assignment.academic_year or '').strip(),
            'semester': semester,
            'period': period,
            'eval_type': 'HOMEWORK',
            'title': (assignment.title or '')[:255],
            'score': score,
            'max_score': max_score,
        },
    )
    return eval_grade


def sync_quiz_attempt_to_evaluation(attempt):
    """
    Crée ou met à jour une EvaluationGrade à partir d'une tentative de quiz soumise (avec note).
    À appeler après sauvegarde de QuizAttempt (submitted_at et score renseignés).
    """
    if not attempt or not attempt.quiz or not attempt.student:
        return None
    quiz = attempt.quiz
    if attempt.score is None:
        return None
    score = Decimal(str(attempt.score))
    max_score = quiz.total_points or 20
    max_score = Decimal(str(max_score)) if max_score else Decimal('20')
    semester = getattr(quiz, 'semester', 'S1') or 'S1'
    period = getattr(quiz, 'period', 1) or 1
    period = min(4, max(1, int(period)))
    eval_grade, created = EvaluationGrade.objects.update_or_create(
        source='QUIZ',
        source_id=str(attempt.id),
        defaults={
            'student_id': attempt.student_id,
            'subject_id': quiz.subject_id,
            'school_class_id': quiz.school_class_id,
            'academic_year': (quiz.academic_year or '').strip(),
            'semester': semester,
            'period': period,
            'eval_type': 'QUIZ',
            'title': (quiz.title or '')[:255],
            'score': score,
            'max_score': max_score,
        },
    )
    return eval_grade
