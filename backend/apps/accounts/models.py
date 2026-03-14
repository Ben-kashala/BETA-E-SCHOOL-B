"""
User and authentication models
"""
from django.contrib.auth.models import AbstractUser
from django.db import models
from apps.schools.models import School
from .constants import SUPERADMIN_USERNAME


class User(AbstractUser):
    """
    Custom User model with role-based access control
    """
    ROLE_CHOICES = [
        ('ADMIN', 'Administrateur école'),
        ('TEACHER', 'Enseignant'),
        ('PARENT', 'Parent'),
        ('STUDENT', 'Élève'),
        ('ACCOUNTANT', 'Comptable'),
        ('DISCIPLINE_OFFICER', 'Chargé de discipline'),
        ('PROMOTER', 'Promoteur'),
    ]
    
    # Basic info (first_name, last_name hérités d'AbstractUser; postnom pour élève)
    middle_name = models.CharField(max_length=100, null=True, blank=True, verbose_name="Postnom")
    phone = models.CharField(max_length=20, null=True, blank=True, verbose_name="Téléphone")
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='users', null=True, blank=True, verbose_name="École")
    role = models.CharField(max_length=20, choices=ROLE_CHOICES, verbose_name="Rôle")
    profile_picture = models.ImageField(upload_to='profiles/', null=True, blank=True, verbose_name="Photo de profil")
    
    # Adresse structurée (Numéro, Avenue, Quartier, Commune, Ville, Province, Pays)
    address_number = models.CharField(max_length=20, null=True, blank=True, verbose_name="Numéro")
    address_avenue = models.CharField(max_length=100, null=True, blank=True, verbose_name="Avenue")
    address_quarter = models.CharField(max_length=100, null=True, blank=True, verbose_name="Quartier")
    address_commune = models.CharField(max_length=100, null=True, blank=True, verbose_name="Commune")
    address_city = models.CharField(max_length=100, null=True, blank=True, verbose_name="Ville")
    address_province = models.CharField(max_length=100, null=True, blank=True, verbose_name="Province")
    address_country = models.CharField(max_length=100, null=True, blank=True, verbose_name="Pays")
    # Ancien champ adresse libre (conservé pour compatibilité)
    address = models.TextField(null=True, blank=True, verbose_name="Adresse (libre)")
    date_of_birth = models.DateField(null=True, blank=True, verbose_name="Date de naissance")
    
    # Status
    is_verified = models.BooleanField(default=False, verbose_name="Vérifié")
    is_active = models.BooleanField(default=True, verbose_name="Actif")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    USERNAME_FIELD = 'username'
    REQUIRED_FIELDS = ['email', 'role']
    
    class Meta:
        verbose_name = "Utilisateur"
        verbose_name_plural = "Utilisateurs"
        ordering = ['-created_at']
    
    def __str__(self):
        return f"{self.username} ({self.get_role_display()})"

    def get_full_name(self):
        """Nom complet : first_name + last_name + middle_name (postnom)."""
        parts = [self.first_name, self.last_name]
        if self.middle_name:
            parts.append(self.middle_name)
        return " ".join(filter(None, parts)).strip() or self.username
    
    @property
    def is_admin(self):
        return self.role == 'ADMIN'
    
    @property
    def is_teacher(self):
        return self.role == 'TEACHER'
    
    @property
    def is_parent(self):
        return self.role == 'PARENT'
    
    @property
    def is_student(self):
        return self.role == 'STUDENT'

    @property
    def is_accountant(self):
        return self.role == 'ACCOUNTANT'

    @property
    def is_discipline_officer(self):
        return self.role == 'DISCIPLINE_OFFICER'

    @property
    def is_promoter(self):
        return self.role == 'PROMOTER'

    @property
    def is_protected_superadmin(self):
        """True uniquement pour le superadmin propriétaire du système (Alidorsabue)."""
        return self.username == SUPERADMIN_USERNAME and self.is_superuser

    @property
    def is_platform_admin(self):
        """Admin plateforme : rôle ADMIN sans école rattachée. Peut créer écoles et admins d'école."""
        return self.role == 'ADMIN' and self.school_id is None


class Teacher(models.Model):
    """Extended profile for teachers"""
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='teacher_profile', verbose_name="Utilisateur")
    employee_id = models.CharField(max_length=50, unique=True, verbose_name="Matricule")
    specialization = models.CharField(max_length=200, null=True, blank=True, verbose_name="Spécialisation")
    hire_date = models.DateField(verbose_name="Date d'embauche")
    salary = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True, verbose_name="Salaire")
    
    class Meta:
        verbose_name = "Enseignant"
        verbose_name_plural = "Enseignants"
    
    def __str__(self):
        return f"{self.user.get_full_name()} - {self.employee_id}"


class Parent(models.Model):
    """Extended profile for parents"""
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='parent_profile', verbose_name="Utilisateur")
    profession = models.CharField(max_length=100, null=True, blank=True, verbose_name="Profession")
    emergency_contact = models.CharField(max_length=20, null=True, blank=True, verbose_name="Contact d'urgence")
    
    class Meta:
        verbose_name = "Parent"
        verbose_name_plural = "Parents"
    
    def __str__(self):
        return f"{self.user.get_full_name()}"


class Student(models.Model):
    """Extended profile for students"""
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='student_profile', verbose_name="Utilisateur")
    student_id = models.CharField(max_length=50, verbose_name="Matricule élève")
    parent = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True, 
                              related_name='children', limit_choices_to={'role': 'PARENT'}, verbose_name="Parent")
    school_class = models.ForeignKey('schools.SchoolClass', on_delete=models.SET_NULL, 
                                     null=True, blank=True, related_name='students', verbose_name="Classe")
    enrollment_date = models.DateField(verbose_name="Date d'inscription")
    academic_year = models.CharField(max_length=20, verbose_name="Année scolaire")
    
    # Anciens élèves (sortie en année terminale ou autre)
    is_former_student = models.BooleanField(default=False, verbose_name="Ancien élève")
    graduation_year = models.CharField(max_length=20, null=True, blank=True, verbose_name="Année de sortie")
    
    # Medical info
    blood_group = models.CharField(max_length=5, null=True, blank=True, verbose_name="Groupe sanguin")
    allergies = models.TextField(null=True, blank=True, verbose_name="Allergies")
    # Identité pour le bulletin officiel (complète les données de User / EnrollmentApplication)
    gender = models.CharField(
        max_length=10,
        choices=[('M', 'Masculin'), ('F', 'Féminin')],
        null=True,
        blank=True,
        verbose_name="Genre"
    )
    place_of_birth = models.CharField(
        max_length=200,
        null=True,
        blank=True,
        verbose_name="Lieu de naissance"
    )
    
    class Meta:
        verbose_name = "Élève"
        verbose_name_plural = "Élèves"
        # Note: unique_together with user__school is handled at application level
    
    def __str__(self):
        return f"{self.user.get_full_name()} - {self.student_id}"


class PlatformSettings(models.Model):
    """
    Paramètres globaux de la plateforme (singleton, id=1).
    Le superadmin peut bloquer l'accès : lorsque is_platform_locked=True,
    seul le superadmin peut se connecter (API, admin Django, mobile, frontend).
    """
    is_platform_locked = models.BooleanField(
        default=False,
        verbose_name="Plateforme verrouillée",
        help_text="Si coché, seul le superadmin peut se connecter (mobile, frontend, admin Django)."
    )
    locked_message = models.CharField(
        max_length=255,
        null=True,
        blank=True,
        verbose_name="Message affiché aux utilisateurs bloqués",
        help_text="Optionnel. Ex : Maintenance en cours."
    )
    updated_at = models.DateTimeField(auto_now=True, verbose_name="Dernière modification")

    class Meta:
        verbose_name = "Paramètres plateforme"
        verbose_name_plural = "Paramètres plateforme"
        db_table = "accounts_platform_settings"

    def __str__(self):
        return "Verrouillée" if self.is_platform_locked else "Ouverte"

    @classmethod
    def get_singleton(cls):
        """Retourne l'unique instance (créée si besoin)."""
        obj, _ = cls.objects.get_or_create(
            pk=1,
            defaults={"is_platform_locked": False}
        )
        return obj
