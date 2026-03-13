"""
E-learning models (courses, assignments, quizzes)
"""
from django.db import models
from apps.accounts.models import Teacher, Student
from apps.schools.models import SchoolClass, Subject


class Course(models.Model):
    """Model for online courses"""
    title = models.CharField(max_length=200, verbose_name="Titre")
    description = models.TextField(verbose_name="Description")
    subject = models.ForeignKey(Subject, on_delete=models.SET_NULL, null=True, blank=True, related_name='courses', verbose_name="Matière")
    school_class = models.ForeignKey(SchoolClass, on_delete=models.CASCADE, related_name='courses', verbose_name="Classe")
    teacher = models.ForeignKey(Teacher, on_delete=models.CASCADE, related_name='courses', verbose_name="Enseignant")
    academic_year = models.CharField(max_length=20, verbose_name="Année scolaire")
    
    # Content (optionnel ; peut être importé via fichier ou lien)
    content = models.TextField(verbose_name="Contenu", blank=True, default='')
    video_url = models.URLField(null=True, blank=True, verbose_name="URL vidéo")
    content_url = models.URLField(null=True, blank=True, verbose_name="Lien vers le contenu (import)")
    attachments = models.FileField(upload_to='courses/attachments/', null=True, blank=True, verbose_name="Pièces jointes")
    
    # Settings
    is_published = models.BooleanField(default=False, verbose_name="Publié")
    publish_date = models.DateTimeField(null=True, blank=True, verbose_name="Date de publication")
    
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        verbose_name = "Cours"
        verbose_name_plural = "Cours"
        ordering = ['-created_at']
    
    def __str__(self):
        return f"{self.title} - {self.school_class.name}"


SEMESTER_CHOICES = [('S1', 'Premier semestre'), ('S2', 'Second semestre')]


class Assignment(models.Model):
    """Model for assignments/homework"""
    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name='assignments', 
                              null=True, blank=True, verbose_name="Cours")
    title = models.CharField(max_length=200, verbose_name="Titre")
    description = models.TextField(verbose_name="Description")
    subject = models.ForeignKey(Subject, on_delete=models.CASCADE, related_name='assignments', verbose_name="Matière")
    school_class = models.ForeignKey(SchoolClass, on_delete=models.CASCADE, related_name='assignments', verbose_name="Classe")
    teacher = models.ForeignKey(Teacher, on_delete=models.CASCADE, related_name='assignments', verbose_name="Enseignant")
    academic_year = models.CharField(max_length=20, verbose_name="Année scolaire")
    semester = models.CharField(max_length=2, choices=SEMESTER_CHOICES, default='S1', verbose_name="Semestre (pour bulletin)")
    period = models.PositiveSmallIntegerField(default=1, verbose_name="Période (1 à 4, pour bulletin)")
    
    # Files
    assignment_file = models.FileField(upload_to='assignments/', null=True, blank=True, verbose_name="Fichier du devoir")
    
    # Dates
    assigned_date = models.DateTimeField(auto_now_add=True, verbose_name="Date d'attribution")
    due_date = models.DateTimeField(verbose_name="Date limite")
    
    # Grading
    total_points = models.DecimalField(max_digits=5, decimal_places=2, default=20, verbose_name="Points totaux")
    
    is_published = models.BooleanField(default=False, verbose_name="Publié")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        verbose_name = "Devoir"
        verbose_name_plural = "Devoirs"
        ordering = ['-due_date']
    
    def __str__(self):
        return f"{self.title} - {self.school_class.name}"


class AssignmentQuestion(models.Model):
    """Question d'un devoir : choix unique, choix multiple, texte ou nombre."""
    QUESTION_TYPE_CHOICES = [
        ('SINGLE_CHOICE', 'Choix unique'),
        ('MULTIPLE_CHOICE', 'Choix multiple'),
        ('TEXT', 'Texte'),
        ('NUMBER', 'Nombre'),
    ]
    assignment = models.ForeignKey(
        Assignment, on_delete=models.CASCADE, related_name='questions', verbose_name="Devoir"
    )
    question_text = models.TextField(verbose_name="Question")
    question_type = models.CharField(
        max_length=20, choices=QUESTION_TYPE_CHOICES, verbose_name="Type"
    )
    points = models.DecimalField(
        max_digits=5, decimal_places=2, default=1, verbose_name="Points"
    )
    order = models.IntegerField(default=0, verbose_name="Ordre")
    # Pour choix unique / multiple : options (JSON ou champs séparés)
    option_a = models.CharField(max_length=500, null=True, blank=True, verbose_name="Option A")
    option_b = models.CharField(max_length=500, null=True, blank=True, verbose_name="Option B")
    option_c = models.CharField(max_length=500, null=True, blank=True, verbose_name="Option C")
    option_d = models.CharField(max_length=500, null=True, blank=True, verbose_name="Option D")
    # Réponse correcte : pour SINGLE_CHOICE "A","B","C","D" ; MULTIPLE_CHOICE "A,B,C" ; TEXT/NUMBER valeur attendue
    correct_answer = models.CharField(
        max_length=500, null=True, blank=True, verbose_name="Réponse correcte"
    )

    class Meta:
        verbose_name = "Question de devoir"
        verbose_name_plural = "Questions de devoir"
        ordering = ['order']

    def __str__(self):
        return f"{self.assignment.title} - Q{self.order}"


class AssignmentSubmission(models.Model):
    """Model for student assignment submissions"""
    STATUS_CHOICES = [
        ('SUBMITTED', 'Soumis'),
        ('GRADED', 'Noté'),
        ('LATE', 'En retard'),
    ]
    
    assignment = models.ForeignKey(Assignment, on_delete=models.CASCADE, related_name='submissions', verbose_name="Devoir")
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='submissions', verbose_name="Élève")
    
    # Submission
    submission_file = models.FileField(upload_to='submissions/', null=True, blank=True, verbose_name="Fichier de soumission")
    submission_text = models.TextField(null=True, blank=True, verbose_name="Texte de soumission")
    submitted_at = models.DateTimeField(auto_now_add=True, verbose_name="Soumis le")
    
    # Grading
    score = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True, verbose_name="Note")
    feedback = models.TextField(null=True, blank=True, verbose_name="Commentaires")
    answer_grades = models.JSONField(default=dict, blank=True, verbose_name="Notes par question")
    graded_by = models.ForeignKey(Teacher, on_delete=models.SET_NULL, null=True, 
                                 related_name='graded_submissions', verbose_name="Noté par")
    graded_at = models.DateTimeField(null=True, blank=True, verbose_name="Noté le")
    
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='SUBMITTED', verbose_name="Statut")
    
    # Une seule soumission par défaut ; l'enseignant peut autoriser une nouvelle soumission
    allow_resubmit = models.BooleanField(default=False, verbose_name="Autoriser une nouvelle soumission")
    
    class Meta:
        verbose_name = "Soumission de devoir"
        verbose_name_plural = "Soumissions de devoirs"
        unique_together = ['assignment', 'student']
        ordering = ['-submitted_at']
    
    def __str__(self):
        return f"{self.student.user.get_full_name()} - {self.assignment.title}"


class Quiz(models.Model):
    """Model for quizzes"""
    title = models.CharField(max_length=200, verbose_name="Titre")
    description = models.TextField(null=True, blank=True, verbose_name="Description")
    subject = models.ForeignKey(Subject, on_delete=models.CASCADE, related_name='quizzes', verbose_name="Matière")
    school_class = models.ForeignKey(SchoolClass, on_delete=models.CASCADE, related_name='quizzes', verbose_name="Classe")
    teacher = models.ForeignKey(Teacher, on_delete=models.CASCADE, related_name='quizzes', verbose_name="Enseignant")
    academic_year = models.CharField(max_length=20, verbose_name="Année scolaire")
    semester = models.CharField(max_length=2, choices=SEMESTER_CHOICES, default='S1', verbose_name="Semestre (pour bulletin)")
    period = models.PositiveSmallIntegerField(default=1, verbose_name="Période (1 à 4, pour bulletin)")
    
    # Settings
    total_points = models.DecimalField(max_digits=5, decimal_places=2, default=20, verbose_name="Points totaux")
    time_limit = models.IntegerField(null=True, blank=True, verbose_name="Limite de temps (minutes)")
    passing_score = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True, verbose_name="Note de passage")
    allow_multiple_attempts = models.BooleanField(default=False, verbose_name="Autoriser plusieurs tentatives")
    max_attempts = models.IntegerField(default=1, verbose_name="Nombre maximum de tentatives")
    shuffle_questions = models.BooleanField(default=False, verbose_name="Mélanger les questions")
    show_results_immediately = models.BooleanField(default=True, verbose_name="Afficher les résultats immédiatement")
    
    # Dates
    start_date = models.DateTimeField(verbose_name="Date de début")
    end_date = models.DateTimeField(verbose_name="Date de fin")
    
    is_published = models.BooleanField(default=False, verbose_name="Publié")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        verbose_name = "Quiz"
        verbose_name_plural = "Quiz"
        ordering = ['-created_at']
    
    def __str__(self):
        return f"{self.title} - {self.school_class.name}"


class QuizQuestion(models.Model):
    """Model for quiz questions (choix unique, choix multiple, texte, nombre)."""
    QUESTION_TYPES = [
        ('SINGLE_CHOICE', 'Choix unique'),
        ('MULTIPLE_CHOICE', 'Choix multiple'),
        ('TEXT', 'Texte'),
        ('NUMBER', 'Nombre'),
        ('TRUE_FALSE', 'Vrai/Faux'),
        ('SHORT_ANSWER', 'Réponse courte'),
        ('ESSAY', 'Dissertation'),
    ]
    
    quiz = models.ForeignKey(Quiz, on_delete=models.CASCADE, related_name='questions', verbose_name="Quiz")
    question_text = models.TextField(verbose_name="Question")
    question_type = models.CharField(max_length=20, choices=QUESTION_TYPES, verbose_name="Type de question")
    points = models.DecimalField(max_digits=5, decimal_places=2, default=1, verbose_name="Points")
    order = models.IntegerField(default=0, verbose_name="Ordre")
    
    # For multiple choice
    option_a = models.CharField(max_length=500, null=True, blank=True, verbose_name="Option A")
    option_b = models.CharField(max_length=500, null=True, blank=True, verbose_name="Option B")
    option_c = models.CharField(max_length=500, null=True, blank=True, verbose_name="Option C")
    option_d = models.CharField(max_length=500, null=True, blank=True, verbose_name="Option D")
    correct_answer = models.CharField(max_length=500, null=True, blank=True, verbose_name="Bonne réponse")  # A, B, C, D, True, False, ou texte libre (TEXT/SHORT_ANSWER/ESSAY)
    
    class Meta:
        verbose_name = "Question de quiz"
        verbose_name_plural = "Questions de quiz"
        ordering = ['order']
    
    def __str__(self):
        return f"{self.quiz.title} - Question {self.order}"


class QuizAttempt(models.Model):
    """Model for student quiz attempts"""
    quiz = models.ForeignKey(Quiz, on_delete=models.CASCADE, related_name='attempts', verbose_name="Quiz")
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='quiz_attempts', verbose_name="Élève")
    
    started_at = models.DateTimeField(auto_now_add=True, verbose_name="Commencé le")
    submitted_at = models.DateTimeField(null=True, blank=True, verbose_name="Soumis le")
    score = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True, verbose_name="Note")
    is_passed = models.BooleanField(default=False, verbose_name="Réussi")
    
    class Meta:
        verbose_name = "Tentative de quiz"
        verbose_name_plural = "Tentatives de quiz"
        ordering = ['-started_at']
    
    def __str__(self):
        return f"{self.student.user.get_full_name()} - {self.quiz.title}"


class QuizAnswer(models.Model):
    """Model for individual quiz answers"""
    attempt = models.ForeignKey(QuizAttempt, on_delete=models.CASCADE, related_name='answers', verbose_name="Tentative")
    question = models.ForeignKey(QuizQuestion, on_delete=models.CASCADE, related_name='answers', verbose_name="Question")
    answer_text = models.TextField(verbose_name="Réponse")
    is_correct = models.BooleanField(default=False, verbose_name="Correct")
    points_earned = models.DecimalField(max_digits=5, decimal_places=2, default=0, verbose_name="Points obtenus")
    teacher_feedback = models.TextField(null=True, blank=True, verbose_name="Commentaire de l'enseignant")
    
    class Meta:
        verbose_name = "Réponse de quiz"
        verbose_name_plural = "Réponses de quiz"
        unique_together = ['attempt', 'question']
    
    def __str__(self):
        return f"{self.attempt.student.user.get_full_name()} - {self.question.question_text[:50]}"
