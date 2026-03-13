"""
Enrollment and re-enrollment models
"""
from django.db import models
from apps.accounts.models import User, Student
from apps.schools.models import School, SchoolClass


class EnrollmentApplication(models.Model):
    """Model for student enrollment applications"""
    STATUS_CHOICES = [
        ('PENDING', 'En attente'),
        ('APPROVED', 'Approuvée'),
        ('REJECTED', 'Rejetée'),
        ('COMPLETED', 'Complétée'),
    ]
    
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='enrollments', verbose_name="École")
    academic_year = models.CharField(max_length=20, verbose_name="Année scolaire")
    
    # Student information (ordre : Prénom, Nom, Postnom)
    first_name = models.CharField(max_length=100, verbose_name="Prénom")
    last_name = models.CharField(max_length=100, verbose_name="Nom")
    middle_name = models.CharField(max_length=100, null=True, blank=True, verbose_name="Postnom")
    date_of_birth = models.DateField(verbose_name="Date de naissance")
    gender = models.CharField(max_length=10, choices=[('M', 'Masculin'), ('F', 'Féminin')], verbose_name="Genre")
    place_of_birth = models.CharField(max_length=200, verbose_name="Lieu de naissance")
    
    # Contact
    phone = models.CharField(max_length=20, null=True, blank=True, verbose_name="Téléphone")
    email = models.EmailField(null=True, blank=True, verbose_name="Email")
    # Adresse structurée de l'élève
    address_number = models.CharField(max_length=20, null=True, blank=True, verbose_name="Numéro")
    address_avenue = models.CharField(max_length=100, null=True, blank=True, verbose_name="Avenue")
    address_quarter = models.CharField(max_length=100, null=True, blank=True, verbose_name="Quartier")
    address_commune = models.CharField(max_length=100, null=True, blank=True, verbose_name="Commune")
    address_city = models.CharField(max_length=100, null=True, blank=True, verbose_name="Ville")
    address_province = models.CharField(max_length=100, null=True, blank=True, verbose_name="Province")
    address_country = models.CharField(max_length=100, null=True, blank=True, verbose_name="Pays")
    # Ancien champ adresse libre
    address = models.TextField(verbose_name="Adresse")
    
    # Academic
    requested_class = models.ForeignKey(SchoolClass, on_delete=models.SET_NULL, null=True, 
                                       related_name='enrollment_applications', verbose_name="Classe demandée")
    previous_school = models.CharField(max_length=200, null=True, blank=True, verbose_name="École précédente")
    
    # Parent/Guardian information
    parent_name = models.CharField(max_length=200, verbose_name="Nom du parent/tuteur")
    mother_name = models.CharField(max_length=200, null=True, blank=True, verbose_name="Nom de la mère")
    parent_phone = models.CharField(max_length=20, verbose_name="Téléphone du parent")
    parent_email = models.EmailField(null=True, blank=True, verbose_name="Email du parent")
    parent_profession = models.CharField(max_length=100, null=True, blank=True, verbose_name="Profession du parent")
    # Adresse structurée du parent
    parent_address_number = models.CharField(max_length=20, null=True, blank=True, verbose_name="Numéro (parent)")
    parent_address_avenue = models.CharField(max_length=100, null=True, blank=True, verbose_name="Avenue (parent)")
    parent_address_quarter = models.CharField(max_length=100, null=True, blank=True, verbose_name="Quartier (parent)")
    parent_address_commune = models.CharField(max_length=100, null=True, blank=True, verbose_name="Commune (parent)")
    parent_address_city = models.CharField(max_length=100, null=True, blank=True, verbose_name="Ville (parent)")
    parent_address_province = models.CharField(max_length=100, null=True, blank=True, verbose_name="Province (parent)")
    parent_address_country = models.CharField(max_length=100, null=True, blank=True, verbose_name="Pays (parent)")
    # Ancien champ adresse libre du parent
    parent_address = models.TextField(null=True, blank=True, verbose_name="Adresse du parent")
    
    # Documents
    birth_certificate = models.FileField(upload_to='enrollments/birth_certificates/', null=True, blank=True, verbose_name="Acte de naissance")
    previous_school_certificate = models.FileField(upload_to='enrollments/certificates/', null=True, blank=True, verbose_name="Certificat de l'école précédente")
    photo = models.ImageField(upload_to='enrollments/photos/', null=True, blank=True, verbose_name="Photo")
    medical_certificate = models.FileField(upload_to='enrollments/medical/', null=True, blank=True, verbose_name="Certificat médical")
    identity_document = models.FileField(upload_to='enrollments/identity/', null=True, blank=True, verbose_name="Pièce d'identité")
    
    # Generated student ID
    generated_student_id = models.CharField(max_length=50, null=True, blank=True, verbose_name="Matricule généré")
    
    # Status
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='PENDING', verbose_name="Statut")
    notes = models.TextField(null=True, blank=True, verbose_name="Notes")
    
    # Tracking
    submitted_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, 
                                    related_name='submitted_enrollments', verbose_name="Soumis par")
    reviewed_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, 
                                   related_name='reviewed_enrollments', verbose_name="Révisé par")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        verbose_name = "Demande d'inscription"
        verbose_name_plural = "Demandes d'inscription"
        ordering = ['-created_at']
    
    def __str__(self):
        parts = [self.first_name, self.last_name]
        if self.middle_name:
            parts.append(self.middle_name)
        full = " ".join(filter(None, parts)).strip()
        return f"{full} - {self.school.name}"


class ReEnrollment(models.Model):
    """Model for student re-enrollment"""
    STATUS_CHOICES = [
        ('PENDING', 'En attente'),
        ('COMPLETED', 'Complétée'),
        ('OVERDUE', 'En retard'),
    ]
    
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='reenrollments', verbose_name="Élève")
    academic_year = models.CharField(max_length=20, verbose_name="Année scolaire")
    school_class = models.ForeignKey(SchoolClass, on_delete=models.SET_NULL, null=True, 
                                    related_name='reenrollments', verbose_name="Classe")
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='PENDING', verbose_name="Statut")
    
    # Payment info
    total_fees = models.DecimalField(max_digits=10, decimal_places=2, verbose_name="Frais totaux")
    paid_amount = models.DecimalField(max_digits=10, decimal_places=2, default=0, verbose_name="Montant payé")
    is_paid = models.BooleanField(default=False, verbose_name="Payé")
    
    # Dates
    enrollment_date = models.DateField(verbose_name="Date d'inscription")
    due_date = models.DateField(null=True, blank=True, verbose_name="Date d'échéance")
    completed_at = models.DateTimeField(null=True, blank=True, verbose_name="Complété le")
    
    notes = models.TextField(null=True, blank=True, verbose_name="Notes")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        verbose_name = "Réinscription"
        verbose_name_plural = "Réinscriptions"
        unique_together = ['student', 'academic_year']
        ordering = ['-created_at']
    
    def __str__(self):
        return f"{self.student.user.get_full_name()} - {self.academic_year}"
