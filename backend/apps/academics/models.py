"""
Academic tracking models (grades, attendance, discipline)
Conforme au bulletin officiel RDC (semestres, 4 périodes, examens par semestre, MAXIMA par groupe).
"""
from decimal import Decimal
from django.db import models
from django.core.validators import MinValueValidator, MaxValueValidator
from apps.accounts.models import Student, Teacher, User
from apps.schools.models import SchoolClass, Subject


class AcademicYear(models.Model):
    """Model for academic year"""
    school = models.ForeignKey('schools.School', on_delete=models.CASCADE, related_name='academic_years', verbose_name="École")
    name = models.CharField(max_length=50, verbose_name="Nom")  # e.g., "2024-2025"
    start_date = models.DateField(verbose_name="Date de début")
    end_date = models.DateField(verbose_name="Date de fin")
    is_current = models.BooleanField(default=False, verbose_name="Année actuelle")
    
    class Meta:
        verbose_name = "Année scolaire"
        verbose_name_plural = "Années scolaires"
        unique_together = ['school', 'name']
    
    def __str__(self):
        return f"{self.name} - {self.school.name}"


class Grade(models.Model):
    """Model for student grades"""
    TERM_CHOICES = [
        ('T1', 'Trimestre 1'),
        ('T2', 'Trimestre 2'),
        ('T3', 'Trimestre 3'),
    ]
    
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='grades', verbose_name="Élève")
    subject = models.ForeignKey(Subject, on_delete=models.CASCADE, related_name='grades', verbose_name="Matière")
    teacher = models.ForeignKey(Teacher, on_delete=models.SET_NULL, null=True, related_name='given_grades', verbose_name="Enseignant")
    academic_year = models.CharField(max_length=20, verbose_name="Année scolaire")
    term = models.CharField(max_length=2, choices=TERM_CHOICES, verbose_name="Trimestre")
    
    # Grades
    continuous_assessment = models.DecimalField(
        max_digits=5, decimal_places=2, 
        validators=[MinValueValidator(0), MaxValueValidator(20)],
        verbose_name="Contrôle continu"
    )
    exam_score = models.DecimalField(
        max_digits=5, decimal_places=2,
        validators=[MinValueValidator(0), MaxValueValidator(20)],
        null=True, blank=True,
        verbose_name="Note d'examen"
    )
    total_score = models.DecimalField(
        max_digits=5, decimal_places=2,
        validators=[MinValueValidator(0), MaxValueValidator(20)],
        verbose_name="Note totale"
    )
    
    # Metadata
    notes = models.TextField(null=True, blank=True, verbose_name="Remarques")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        verbose_name = "Note"
        verbose_name_plural = "Notes"
        unique_together = ['student', 'subject', 'academic_year', 'term']
        ordering = ['-created_at']
    
    def __str__(self):
        return f"{self.student.user.get_full_name()} - {self.subject.name} - {self.term}"
    
    def save(self, *args, **kwargs):
        # Calculate total score
        try:
            if self.exam_score is not None and self.exam_score != '':
                cc = Decimal(str(self.continuous_assessment))
                exam = Decimal(str(self.exam_score))
                self.total_score = (cc * Decimal('0.4')) + (exam * Decimal('0.6'))
            else:
                self.total_score = Decimal(str(self.continuous_assessment))
        except Exception as e:
            import logging
            logger = logging.getLogger(__name__)
            logger.error(f"Erreur lors du calcul de total_score: {str(e)}")
            self.total_score = self.continuous_assessment
        super().save(*args, **kwargs)


class GradeBulletin(models.Model):
    """
    Notes conforme au bulletin RDC: 2 semestres, 4 périodes (Travaux journaliers), 2 examens.
    Premier semestre: 1ère P., 2ème P., EXAM. → TOT. S1
    Second semestre: 3ème P., 4ème P., EXAM. → TOT. S2
    T.G. = TOT. S1 + TOT. S2. Examen de repêchage optionnel.

    school_class : classe dans laquelle la note a été obtenue. Une promue en 5ème (année 2026-2027)
    ne doit pas afficher les notes de 4ème (2025-2026) : on filtre par school_class + academic_year.
    """
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='grade_bulletins', verbose_name="Élève")
    subject = models.ForeignKey(Subject, on_delete=models.CASCADE, related_name='grade_bulletins', verbose_name="Matière")
    school_class = models.ForeignKey(
        SchoolClass, on_delete=models.CASCADE, null=True, blank=True,
        related_name='grade_bulletins', verbose_name="Classe (contexte de la note)"
    )
    teacher = models.ForeignKey(Teacher, on_delete=models.SET_NULL, null=True, blank=True, related_name='given_grade_bulletins', verbose_name="Enseignant")
    academic_year = models.CharField(max_length=20, verbose_name="Année scolaire")
    
    # Premier semestre: 1ère P., 2ème P., EXAM.
    s1_p1 = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True, validators=[MinValueValidator(0)], verbose_name="S1 - 1ère P. (Trav. journaliers)")
    s1_p2 = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True, validators=[MinValueValidator(0)], verbose_name="S1 - 2ème P.")
    s1_exam = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True, validators=[MinValueValidator(0)], verbose_name="S1 - Examen")
    total_s1 = models.DecimalField(max_digits=6, decimal_places=2, null=True, blank=True, verbose_name="Total S1")
    
    # Second semestre: 3ème P., 4ème P., EXAM.
    s2_p3 = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True, validators=[MinValueValidator(0)], verbose_name="S2 - 3ème P.")
    s2_p4 = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True, validators=[MinValueValidator(0)], verbose_name="S2 - 4ème P.")
    s2_exam = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True, validators=[MinValueValidator(0)], verbose_name="S2 - Examen")
    total_s2 = models.DecimalField(max_digits=6, decimal_places=2, null=True, blank=True, verbose_name="Total S2")
    
    total_general = models.DecimalField(max_digits=7, decimal_places=2, null=True, blank=True, verbose_name="T.G. (Total général)")
    
    # Examen de repêchage
    reclamation_score = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True, verbose_name="% Repêchage")
    reclamation_passed = models.BooleanField(null=True, blank=True, verbose_name="Réussi au repêchage")
    
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        verbose_name = "Note (bulletin RDC)"
        verbose_name_plural = "Notes (bulletin RDC)"
        unique_together = ['student', 'subject', 'academic_year']
        ordering = ['student', 'subject']
    
    def __str__(self):
        return f"{self.student.user.get_full_name()} - {self.subject.name} - {self.academic_year}"
    
    def save(self, *args, **kwargs):
        def d(v):
            return Decimal(str(v)) if v is not None and v != '' else Decimal('0')
        self.total_s1 = d(self.s1_p1) + d(self.s1_p2) + d(self.s1_exam)
        self.total_s2 = d(self.s2_p3) + d(self.s2_p4) + d(self.s2_exam)
        self.total_general = (self.total_s1 or Decimal('0')) + (self.total_s2 or Decimal('0'))
        super().save(*args, **kwargs)


class EvaluationGrade(models.Model):
    """
    Détail des évaluations (devoirs, interrogations, examens) par élève/matière/période.
    Sert de base pour calculer des moyennes et alimenter GradeBulletin.
    """
    EVAL_TYPES = [
        ('HOMEWORK', 'Devoir'),
        ('QUIZ', 'Interrogation'),
        ('EXAM', 'Examen'),
    ]
    SEMESTER_CHOICES = [
        ('S1', 'Premier semestre'),
        ('S2', 'Second semestre'),
    ]

    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='evaluation_grades', verbose_name="Élève")
    subject = models.ForeignKey(Subject, on_delete=models.CASCADE, related_name='evaluation_grades', verbose_name="Matière")
    school_class = models.ForeignKey(SchoolClass, on_delete=models.CASCADE, related_name='evaluation_grades', verbose_name="Classe")
    academic_year = models.CharField(max_length=20, verbose_name="Année scolaire")
    semester = models.CharField(max_length=2, choices=SEMESTER_CHOICES, verbose_name="Semestre")
    # Période 1 à 4 (Travaux journaliers / interrogations) ou période examen
    period = models.PositiveSmallIntegerField(verbose_name="Période (1 à 4)")
    eval_type = models.CharField(max_length=10, choices=EVAL_TYPES, verbose_name="Type d'évaluation")

    score = models.DecimalField(max_digits=6, decimal_places=2, validators=[MinValueValidator(0)], verbose_name="Note obtenue")
    max_score = models.DecimalField(max_digits=6, decimal_places=2, validators=[MinValueValidator(0)], verbose_name="Note sur")

    # Lien facultatif avec une activité en ligne (devoir/quiz de la plateforme)
    source = models.CharField(max_length=20, default='MANUAL', verbose_name="Source")
    source_id = models.CharField(max_length=64, null=True, blank=True, verbose_name="ID source")

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Évaluation détaillée"
        verbose_name_plural = "Évaluations détaillées"
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.student} - {self.subject} - {self.semester} P{self.period} {self.eval_type}"


class Attendance(models.Model):
    """Model for student attendance"""
    STATUS_CHOICES = [
        ('PRESENT', 'Présent'),
        ('ABSENT', 'Absent'),
        ('LATE', 'En retard'),
        ('EXCUSED', 'Excusé'),
    ]
    
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='attendances', verbose_name="Élève")
    school_class = models.ForeignKey(SchoolClass, on_delete=models.CASCADE, related_name='attendances', verbose_name="Classe")
    date = models.DateField(verbose_name="Date")
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, verbose_name="Statut")
    subject = models.ForeignKey(Subject, on_delete=models.SET_NULL, null=True, blank=True, 
                               related_name='attendances', verbose_name="Matière")
    teacher = models.ForeignKey(Teacher, on_delete=models.SET_NULL, null=True, 
                              related_name='recorded_attendances', verbose_name="Enseignant")
    notes = models.TextField(null=True, blank=True, verbose_name="Remarques")
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        verbose_name = "Présence"
        verbose_name_plural = "Présences"
        # Une présence par élève par classe par jour (calendrier). subject=null pour présence quotidienne.
        unique_together = [['student', 'school_class', 'date']]
        ordering = ['-date']
    
    def __str__(self):
        return f"{self.student.user.get_full_name()} - {self.date} - {self.get_status_display()}"


class DisciplineRecord(models.Model):
    """Model for discipline/behavior records"""
    TYPE_CHOICES = [
        ('POSITIVE', 'Comportement positif'),
        ('NEGATIVE', 'Comportement négatif'),
    ]
    SEVERITY_CHOICES = [
        ('LOW', 'Faible'),
        ('MEDIUM', 'Moyen'),
        ('HIGH', 'Élevé'),
    ]
    STATUS_CHOICES = [
        ('OPEN', 'Ouvert'),
        ('RESOLVED', 'Résolu'),
        ('CLOSED', 'Fermé'),
    ]
    
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='discipline_records', verbose_name="Élève")
    school_class = models.ForeignKey(SchoolClass, on_delete=models.CASCADE, related_name='discipline_records', verbose_name="Classe")
    type = models.CharField(max_length=10, choices=TYPE_CHOICES, verbose_name="Type")
    severity = models.CharField(max_length=10, choices=SEVERITY_CHOICES, verbose_name="Sévérité")
    description = models.TextField(verbose_name="Description")
    action_taken = models.TextField(null=True, blank=True, verbose_name="Action prise")
    recorded_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, 
                                    related_name='recorded_disciplines', verbose_name="Enregistré par")
    date = models.DateField(verbose_name="Date")
    
    # Statut et résolution
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default='OPEN', verbose_name="Statut")
    resolution_notes = models.TextField(null=True, blank=True, verbose_name="Notes de résolution")
    resolved_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True,
                                   related_name='resolved_disciplines', verbose_name="Résolu par")
    resolved_at = models.DateTimeField(null=True, blank=True, verbose_name="Date de résolution")
    closed_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True,
                                 related_name='closed_disciplines', verbose_name="Fermé par")
    closed_at = models.DateTimeField(null=True, blank=True, verbose_name="Date de fermeture")
    
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        verbose_name = "Fiche de discipline"
        verbose_name_plural = "Fiches de discipline"
        ordering = ['-date']
    
    def __str__(self):
        return f"{self.student.user.get_full_name()} - {self.get_type_display()} - {self.date}"


class DisciplineRequest(models.Model):
    """Model for parent requests regarding discipline records"""
    REQUEST_TYPE_CHOICES = [
        ('APOLOGY', 'Demande d\'excuse'),
        ('PUNISHMENT_LIFT', 'Demande de levée de punition'),
        ('APPEAL', 'Recours'),
        ('DISCUSSION', 'Discussion'),
    ]
    STATUS_CHOICES = [
        ('PENDING', 'En attente'),
        ('APPROVED', 'Approuvée'),
        ('REJECTED', 'Rejetée'),
    ]
    
    discipline_record = models.ForeignKey(
        DisciplineRecord, 
        on_delete=models.CASCADE, 
        related_name='requests', 
        verbose_name="Fiche de discipline"
    )
    parent = models.ForeignKey(
        'accounts.Parent', 
        on_delete=models.CASCADE, 
        related_name='discipline_requests', 
        verbose_name="Parent"
    )
    request_type = models.CharField(
        max_length=20, 
        choices=REQUEST_TYPE_CHOICES, 
        verbose_name="Type de demande"
    )
    message = models.TextField(verbose_name="Message/Justification")
    
    # Statut et réponse
    status = models.CharField(
        max_length=10, 
        choices=STATUS_CHOICES, 
        default='PENDING', 
        verbose_name="Statut"
    )
    response = models.TextField(null=True, blank=True, verbose_name="Réponse de l'école")
    responded_by = models.ForeignKey(
        User, 
        on_delete=models.SET_NULL, 
        null=True, 
        blank=True,
        related_name='responded_discipline_requests', 
        verbose_name="Répondu par"
    )
    responded_at = models.DateTimeField(null=True, blank=True, verbose_name="Date de réponse")
    
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        verbose_name = "Demande de discipline"
        verbose_name_plural = "Demandes de discipline"
        ordering = ['-created_at']
    
    def __str__(self):
        return f"{self.parent.user.get_full_name()} - {self.get_request_type_display()} - {self.discipline_record}"


class ReportCard(models.Model):
    """Bulletin scolaire conforme au modèle RDC (APPLICATION, CONDUITE, décision, repêchage)."""
    BULLETIN_TERM_CHOICES = [('T1', 'Trimestre 1'), ('T2', 'Trimestre 2'), ('T3', 'Trimestre 3'), ('AN', 'Annuel (bulletin RDC)')]
    DECISION_CHOICES = [('PASSE', 'Passé'), ('DOUBLE', 'Double'), ('REPECHAGE', 'Avec repêchage')]
    
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='report_cards', verbose_name="Élève")
    academic_year = models.CharField(max_length=20, verbose_name="Année scolaire")
    term = models.CharField(max_length=2, choices=BULLETIN_TERM_CHOICES, verbose_name="Période", default='AN')
    
    # Summary
    total_subjects = models.IntegerField(default=0, verbose_name="Nombre de matières")
    average_score = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True, verbose_name="Moyenne générale")
    rank = models.IntegerField(null=True, blank=True, verbose_name="Place")
    total_students = models.IntegerField(null=True, blank=True, verbose_name="Nombre d'élèves")
    
    # Bulletin RDC: APPLICATION, CONDUITE
    application = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True, validators=[MinValueValidator(0), MaxValueValidator(20)], verbose_name="Application")
    conduite = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True, validators=[MinValueValidator(0), MaxValueValidator(20)], verbose_name="Conduite")
    
    # Décision: PASSE, DOUBLE, REPECHAGE
    decision = models.CharField(max_length=20, choices=DECISION_CHOICES, null=True, blank=True, verbose_name="Décision")
    reclamation_subject = models.ForeignKey(Subject, on_delete=models.SET_NULL, null=True, blank=True, related_name='+', verbose_name="Matière de repêchage")
    reclamation_passed = models.BooleanField(null=True, blank=True, verbose_name="Réussi au repêchage")
    
    # Comments
    teacher_comment = models.TextField(null=True, blank=True, verbose_name="Commentaire de l'enseignant")
    principal_comment = models.TextField(null=True, blank=True, verbose_name="Commentaire du directeur")
    
    # Status
    is_published = models.BooleanField(default=False, verbose_name="Publié")
    published_at = models.DateTimeField(null=True, blank=True, verbose_name="Publié le")
    
    # PDF file
    pdf_file = models.FileField(upload_to='academics/report_cards/', null=True, blank=True, verbose_name="Fichier PDF")
    
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        verbose_name = "Bulletin"
        verbose_name_plural = "Bulletins"
        unique_together = ['student', 'academic_year', 'term']
        ordering = ['-academic_year', '-term']
    
    def __str__(self):
        return f"{self.student.user.get_full_name()} - {self.academic_year} - {self.term}"
