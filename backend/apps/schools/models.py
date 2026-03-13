"""
School models for multi-tenant architecture
"""
from django.db import models
from django.core.validators import RegexValidator
from django.conf import settings


class School(models.Model):
    """Model representing a school (tenant)"""
    SCHOOL_TYPE_CHOICES = [
        ('MATERNELLE', 'Maternelle'),
        ('PRIMAIRE', 'Primaire'),
        ('HUMANITAIRE', 'Humanitaire'),
    ]
    name = models.CharField(max_length=200, verbose_name="Nom de l'école")
    code = models.CharField(
        max_length=20,
        unique=True,
        validators=[RegexValidator(regex=r'^[A-Z0-9]+$', message='Code doit contenir uniquement des majuscules et chiffres')],
        verbose_name="Code de l'école"
    )
    address = models.TextField(verbose_name="Adresse")
    # Localisation détaillée pour les bulletins officiels (RDC)
    province = models.CharField(max_length=100, null=True, blank=True, verbose_name="Province")
    commune = models.CharField(max_length=100, null=True, blank=True, verbose_name="Commune / Territoire")
    city = models.CharField(max_length=100, verbose_name="Ville")
    country = models.CharField(max_length=100, default="RDC", verbose_name="Pays")
    phone = models.CharField(max_length=20, verbose_name="Téléphone")
    email = models.EmailField(verbose_name="Email")
    logo = models.ImageField(upload_to='schools/logos/', null=True, blank=True, verbose_name="Logo")
    website = models.URLField(null=True, blank=True, verbose_name="Site web")
    
    # Configuration
    school_type = models.CharField(
        max_length=20,
        choices=SCHOOL_TYPE_CHOICES,
        default='PRIMAIRE',
        verbose_name="Type d'école",
        help_text="Détermine les classes disponibles : Maternelle (1ère-3ème), Primaire (1ère-6ème), Humanitaire (7ème-8ème, 1ère-4ème).",
    )
    academic_year = models.CharField(max_length=20, default="2024-2025", verbose_name="Année scolaire")
    currency = models.CharField(max_length=3, default="CDF", verbose_name="Devise")
    language = models.CharField(max_length=10, default="fr", verbose_name="Langue")

    # Promoteurs (propriétaires) de l'école
    promoters = models.ManyToManyField(
        settings.AUTH_USER_MODEL,
        related_name='promoted_schools',
        blank=True,
        limit_choices_to={'role': 'PROMOTER'},
        verbose_name="Promoteurs",
    )
    
    # Status
    is_active = models.BooleanField(default=True, verbose_name="Actif")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        verbose_name = "École"
        verbose_name_plural = "Écoles"
        ordering = ['name']
    
    def __str__(self):
        return self.name


class Section(models.Model):
    """Model representing a section (e.g., A, B, C) in a school"""
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='sections', verbose_name="École")
    name = models.CharField(max_length=50, verbose_name="Nom de la section")  # e.g., "A", "B", "C"
    description = models.TextField(null=True, blank=True, verbose_name="Description")
    is_active = models.BooleanField(default=True, verbose_name="Actif")
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        verbose_name = "Section"
        verbose_name_plural = "Sections"
        unique_together = ['school', 'name']
        ordering = ['name']
    
    def __str__(self):
        return f"{self.name} - {self.school.name}"


class SchoolClass(models.Model):
    """Model representing a class/grade in a school"""
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='classes', verbose_name="École")
    titulaire = models.ForeignKey(
        'accounts.Teacher',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='titular_classes',
        verbose_name="Enseignant titulaire"
    )
    name = models.CharField(max_length=100, verbose_name="Nom de la classe")
    next_class_name = models.CharField(
        max_length=100,
        null=True,
        blank=True,
        verbose_name="Classe suivante (promotion)",
        help_text="Ex. 4ème CG pour 3ème CG. Si ≥50% T.G., l'élève y passe. Vide si année terminale.",
    )
    is_terminal = models.BooleanField(
        default=False,
        verbose_name="Année terminale",
        help_text="Dernière année (ex. 6ème CG). Si ≥50% T.G., l'élève sort et rejoint les anciens élèves.",
    )
    level = models.CharField(max_length=50, verbose_name="Niveau")  # e.g., "Maternelle", "Primaire", "Secondaire"
    grade = models.CharField(max_length=20, verbose_name="Classe")  # e.g., "1ère", "2ème", "6ème"
    section = models.ForeignKey(Section, on_delete=models.SET_NULL, null=True, blank=True, related_name='classes', verbose_name="Section")
    capacity = models.IntegerField(default=40, verbose_name="Capacité")
    academic_year = models.CharField(max_length=20, verbose_name="Année scolaire")
    is_active = models.BooleanField(default=True, verbose_name="Actif")
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        verbose_name = "Classe"
        verbose_name_plural = "Classes"
        unique_together = ['school', 'name', 'academic_year']
        ordering = ['level', 'grade', 'section__name']
    
    def __str__(self):
        return f"{self.name} - {self.school.name}"


class Subject(models.Model):
    """Model representing a subject/course"""
    # Note de base : 10 à 100 par pas de 10 (période). Examen = 2×, TOT sem = 4×, T.G. = 8×
    PERIOD_MAX_CHOICES = [(i, str(i)) for i in range(10, 101, 10)]
    
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='subjects', verbose_name="École")
    name = models.CharField(max_length=100, verbose_name="Nom de la matière")
    code = models.CharField(max_length=20, verbose_name="Code")
    description = models.TextField(null=True, blank=True, verbose_name="Description")
    # Bulletin RDC: maximum par période (Travaux journaliers 1ère P, 2ème P, etc.). Examen = 2×, TOT sem = 4×, T.G. = 8×
    period_max = models.PositiveSmallIntegerField(
        choices=PERIOD_MAX_CHOICES,
        default=20,
        verbose_name="Maximum par période (points)"
    )
    is_active = models.BooleanField(default=True, verbose_name="Actif")
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        verbose_name = "Matière"
        verbose_name_plural = "Matières"
        unique_together = ['school', 'code']
        ordering = ['name']
    
    def __str__(self):
        return f"{self.name} - {self.school.name}"
    
    @property
    def exam_max(self):
        return self.period_max * 2
    
    @property
    def total_semester_max(self):
        return self.period_max * 4
    
    @property
    def total_general_max(self):
        return self.period_max * 8


class StudentClassEnrollment(models.Model):
    """
    Parcours élève-classe : garde l'historique. Un élève reste lié à l'ancienne classe
    (status=promoted/graduated) et a un nouveau parcours dans la nouvelle classe (active).
    """
    STATUS_CHOICES = [
        ('active', 'Actif'),
        ('promoted', 'Promu'),
        ('graduated', 'Diplômé / sorti'),
        ('withdrawn', 'Désinscrit'),
        ('echec', 'Échec'),  # <50% en fin d'année : reprend la même classe l'année suivante
    ]
    student = models.ForeignKey(
        'accounts.Student', on_delete=models.CASCADE, related_name='class_enrollments'
    )
    school_class = models.ForeignKey(
        SchoolClass, on_delete=models.CASCADE, related_name='student_enrollments'
    )
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='active')
    enrolled_at = models.DateTimeField(auto_now_add=True)
    left_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        verbose_name = 'Inscription en classe'
        verbose_name_plural = 'Inscriptions en classe'
        unique_together = ['student', 'school_class']
        ordering = ['-enrolled_at']

    def __str__(self):
        return f"{self.student} — {self.school_class} ({self.get_status_display()})"


class ClassSubject(models.Model):
    """
    Assignation des matières aux classes avec la note de base (period_max) par matière.
    Note de base de 10 à 100 par pas de 10. Examen = 2×, TOT sem = 4×, T.G. = 8×.
    L'enseignant assigné (teacher) peut saisir les notes de cette matière dans cette classe.
    Le planning horaire pourra s'appuyer sur cette attribution.
    """
    PERIOD_MAX_CHOICES = [(i, str(i)) for i in range(10, 101, 10)]

    school_class = models.ForeignKey(
        SchoolClass, on_delete=models.CASCADE, related_name='class_subjects', verbose_name="Classe"
    )
    subject = models.ForeignKey(
        Subject, on_delete=models.CASCADE, related_name='class_subjects', verbose_name="Matière"
    )
    # Enseignant assigné : saisit les notes de cette matière dans cette classe (et planning horaire)
    teacher = models.ForeignKey(
        'accounts.Teacher',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='class_subject_assignments',
        verbose_name="Enseignant assigné",
    )
    # Note de base = maximum par période (Trav. journaliers). Examen = 2×, TOT sem = 4×, T.G. = 8×
    period_max = models.PositiveSmallIntegerField(
        choices=PERIOD_MAX_CHOICES,
        verbose_name="Note de base (max/période)"
    )
    # Domaine pour le bulletin officiel RDC (Sciences, Langues, Arts, etc.)
    domain = models.CharField(
        max_length=100,
        null=True,
        blank=True,
        verbose_name="Domaine (bulletin RDC)",
        help_text="Ex. DOMAINE DES SCIENCES, DOMAINE DES LANGUES, DOMAINE DES ARTS…"
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "Matière par classe"
        verbose_name_plural = "Matières par classe"
        unique_together = ['school_class', 'subject']
        ordering = ['school_class', 'subject__name']

    def __str__(self):
        return f"{self.school_class.name} — {self.subject.name} (base: {self.period_max})"
