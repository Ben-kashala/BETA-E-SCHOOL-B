"""
Payment models for school fees and content purchases.
Paiement Mobile Money : Airtel Money, Orange Money, M-Pesa (clés API globales, numéro marchand par école).
"""
from django.db import models
from apps.accounts.models import User, Student
from apps.schools.models import School


class SchoolPaymentConfig(models.Model):
    """
    Configuration globale paiement par école (multi-tenant).
    Active/désactive les paiements en ligne pour l'école.
    Les moyens de paiement (Airtel, Orange, M-Pesa) et numéros Mobile Money sont dans SchoolPaymentMethod.
    """
    school = models.OneToOneField(
        School,
        on_delete=models.CASCADE,
        related_name='payment_config',
        verbose_name='École',
        unique=True,
    )
    is_active = models.BooleanField(default=True, verbose_name='Actif')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Configuration paiement (école)'
        verbose_name_plural = 'Configurations paiement (écoles)'

    def __str__(self):
        return f"Paiement — {self.school.name}"


class SchoolPaymentMethod(models.Model):
    """
    Configuration des moyens de paiement Mobile Money par école.
    Chaque école configure son propre numéro pour recevoir les paiements (Airtel, Orange, M-Pesa).
    Les clés API des opérateurs sont globales (variables d'environnement).
    """
    PROVIDER_CHOICES = [
        ('airtel', 'Airtel Money'),
        ('orange', 'Orange Money'),
        ('mpesa', 'M-Pesa'),
    ]
    STATUS_CHOICES = [
        ('active', 'Actif'),
        ('inactive', 'Inactif'),
    ]
    school = models.ForeignKey(
        School,
        on_delete=models.CASCADE,
        related_name='payment_methods',
        verbose_name='École',
    )
    provider = models.CharField(
        max_length=20,
        choices=PROVIDER_CHOICES,
        verbose_name='Opérateur',
    )
    merchant_number = models.CharField(
        max_length=30,
        verbose_name='Numéro Mobile Money (réception)',
        help_text='Ex: +243810000000',
    )
    status = models.CharField(
        max_length=20,
        choices=STATUS_CHOICES,
        default='active',
        verbose_name='Statut',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Moyen de paiement (école)'
        verbose_name_plural = 'Moyens de paiement (écoles)'
        unique_together = ['school', 'provider']
        ordering = ['school', 'provider']

    def __str__(self):
        return f"{self.school.name} — {self.get_provider_display()} ({self.merchant_number})"


class PaymentTransaction(models.Model):
    """
    Transaction Mobile Money (Airtel, Orange, M-Pesa) pour traçabilité et callbacks.
    Liée à un Payment et mise à jour par les webhooks opérateurs.
    """
    STATUS_CHOICES = [
        ('pending', 'En attente'),
        ('processing', 'En cours'),
        ('completed', 'Complété'),
        ('failed', 'Échoué'),
        ('cancelled', 'Annulé'),
    ]
    school = models.ForeignKey(
        School,
        on_delete=models.CASCADE,
        related_name='payment_transactions',
        verbose_name='École',
    )
    student = models.ForeignKey(
        Student,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='payment_transactions',
        verbose_name='Élève',
    )
    provider = models.CharField(max_length=20, verbose_name='Opérateur (airtel, orange, mpesa)')
    phone = models.CharField(max_length=30, verbose_name='Téléphone du payeur')
    amount = models.DecimalField(max_digits=12, decimal_places=2, verbose_name='Montant')
    reference = models.CharField(
        max_length=100,
        unique=True,
        verbose_name='Référence',
        help_text='Format SCH{id}-STU{id}-INV{id} pour identifier école, élève, facture/paiement',
    )
    status = models.CharField(
        max_length=20,
        choices=STATUS_CHOICES,
        default='pending',
        verbose_name='Statut',
    )
    provider_transaction_id = models.CharField(
        max_length=100,
        blank=True,
        null=True,
        verbose_name='ID transaction opérateur',
    )
    payment = models.OneToOneField(
        'Payment',
        on_delete=models.CASCADE,
        related_name='mobile_money_transaction',
        null=True,
        blank=True,
        verbose_name='Paiement lié',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Transaction Mobile Money'
        verbose_name_plural = 'Transactions Mobile Money'
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.reference} — {self.provider} — {self.status}"


class FeeType(models.Model):
    """Model for different types of fees"""
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='fee_types', verbose_name="École")
    name = models.CharField(max_length=100, verbose_name="Nom")
    description = models.TextField(null=True, blank=True, verbose_name="Description")
    amount = models.DecimalField(max_digits=10, decimal_places=2, verbose_name="Montant")
    currency = models.CharField(max_length=3, default="CDF", verbose_name="Devise")
    is_active = models.BooleanField(default=True, verbose_name="Actif")
    
    class Meta:
        verbose_name = "Type de frais"
        verbose_name_plural = "Types de frais"
        unique_together = ['school', 'name']
        ordering = ['school', 'name']
    
    def __str__(self):
        return f"{self.name} - {self.school.name}"


class Payment(models.Model):
    """Model for payments"""
    PAYMENT_METHODS = [
        ('CASH', 'Espèces'),
        ('MOBILE_MONEY', 'Mobile Money'),
        ('MOBILE_MONEY_MPESA', 'M-Pesa'),
        ('MOBILE_MONEY_ORANGE', 'Orange Money'),
        ('MOBILE_MONEY_AIRTEL', 'Airtel Money'),
        ('BANK_TRANSFER', 'Virement bancaire'),
        ('CARD', 'Carte bancaire'),
        ('ONLINE', 'Paiement en ligne'),
    ]
    
    STATUS_CHOICES = [
        ('PENDING', 'En attente'),
        ('PROCESSING', 'En traitement'),
        ('COMPLETED', 'Complété'),
        ('FAILED', 'Échoué'),
        ('CANCELLED', 'Annulé'),
        ('REFUNDED', 'Remboursé'),
    ]
    
    # Payment info
    payment_id = models.CharField(max_length=100, unique=True, verbose_name="ID de paiement")
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='payments', verbose_name="Utilisateur")
    student = models.ForeignKey(Student, on_delete=models.SET_NULL, null=True, blank=True, 
                               related_name='payments', verbose_name="Élève")
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='payments', verbose_name="École")
    
    # Amount
    amount = models.DecimalField(max_digits=10, decimal_places=2, verbose_name="Montant")
    currency = models.CharField(max_length=3, default="CDF", verbose_name="Devise")
    
    # Payment details
    payment_method = models.CharField(max_length=20, choices=PAYMENT_METHODS, verbose_name="Méthode de paiement")
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='PENDING', verbose_name="Statut")
    
    # Reference
    reference_number = models.CharField(max_length=100, null=True, blank=True, verbose_name="Numéro de référence")
    transaction_id = models.CharField(max_length=100, null=True, blank=True, verbose_name="ID de transaction")
    payer_phone = models.CharField(max_length=20, null=True, blank=True, verbose_name="Téléphone du payeur (Mobile Money)")
    
    # Metadata
    description = models.TextField(null=True, blank=True, verbose_name="Description")
    notes = models.TextField(null=True, blank=True, verbose_name="Notes")
    
    # Dates
    payment_date = models.DateTimeField(null=True, blank=True, verbose_name="Date de paiement")
    due_date = models.DateField(null=True, blank=True, verbose_name="Date d'échéance")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        verbose_name = "Paiement"
        verbose_name_plural = "Paiements"
        ordering = ['-created_at']
    
    def __str__(self):
        return f"{self.payment_id} - {self.user.get_full_name()} - {self.amount} {self.currency}"


class FeePayment(models.Model):
    """Model linking payments to specific fees"""
    payment = models.ForeignKey(Payment, on_delete=models.CASCADE, related_name='fee_payments', verbose_name="Paiement")
    fee_type = models.ForeignKey(FeeType, on_delete=models.CASCADE, related_name='payments', verbose_name="Type de frais")
    amount = models.DecimalField(max_digits=10, decimal_places=2, verbose_name="Montant")
    academic_year = models.CharField(max_length=20, verbose_name="Année scolaire")
    term = models.CharField(max_length=2, null=True, blank=True, verbose_name="Trimestre")
    
    class Meta:
        verbose_name = "Paiement de frais"
        verbose_name_plural = "Paiements de frais"
    
    def __str__(self):
        return f"{self.fee_type.name} - {self.payment.payment_id}"


class PaymentPlan(models.Model):
    """Model for payment plans/installments"""
    payment = models.ForeignKey(Payment, on_delete=models.CASCADE, related_name='installments', verbose_name="Paiement")
    installment_number = models.IntegerField(verbose_name="Numéro d'échéance")
    amount = models.DecimalField(max_digits=10, decimal_places=2, verbose_name="Montant")
    due_date = models.DateField(verbose_name="Date d'échéance")
    is_paid = models.BooleanField(default=False, verbose_name="Payé")
    paid_date = models.DateTimeField(null=True, blank=True, verbose_name="Date de paiement")
    
    class Meta:
        verbose_name = "Plan de paiement"
        verbose_name_plural = "Plans de paiement"
        unique_together = ['payment', 'installment_number']
        ordering = ['installment_number']
    
    def __str__(self):
        return f"{self.payment.payment_id} - Échéance {self.installment_number}"


class PaymentReceipt(models.Model):
    """Model for payment receipts"""
    payment = models.OneToOneField(Payment, on_delete=models.CASCADE, related_name='receipt', verbose_name="Paiement")
    receipt_number = models.CharField(max_length=100, unique=True, verbose_name="Numéro de reçu")
    pdf_file = models.FileField(upload_to='receipts/', null=True, blank=True, verbose_name="Fichier PDF")
    generated_at = models.DateTimeField(auto_now_add=True, verbose_name="Généré le")
    
    class Meta:
        verbose_name = "Reçu de paiement"
        verbose_name_plural = "Reçus de paiement"
    
    def __str__(self):
        return f"Reçu {self.receipt_number} - {self.payment.payment_id}"


class SchoolExpense(models.Model):
    """Dépenses de l'école - gérées par le comptable"""
    CATEGORY_CHOICES = [
        ('SALARIES', 'Salaires'),
        ('MAINTENANCE', 'Entretien / Maintenance'),
        ('MATERIEL', 'Matériel pédagogique'),
        ('UTILITIES', 'Eau / Électricité / Internet'),
        ('EVENTS', 'Activités / Événements'),
        ('OTHER', 'Autre'),
    ]
    PAYMENT_METHOD_CHOICES = [
        ('CASH', 'Espèces'),
        ('MOBILE_MONEY', 'Mobile Money'),
        ('MOBILE_MONEY_MPESA', 'M-Pesa'),
        ('MOBILE_MONEY_ORANGE', 'Orange Money'),
        ('MOBILE_MONEY_AIRTEL', 'Airtel Money'),
        ('BANK_TRANSFER', 'Virement bancaire'),
        ('CARD', 'Carte bancaire'),
        ('ONLINE', 'Paiement en ligne'),
    ]
    STATUS_CHOICES = [
        ('PENDING', 'En attente'),
        ('APPROVED', 'Approuvée'),
        ('PAID', 'Payée'),
        ('REJECTED', 'Rejetée'),
    ]
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='expenses', verbose_name="École")
    recorded_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, related_name='recorded_expenses', verbose_name="Enregistré par")
    category = models.CharField(max_length=20, choices=CATEGORY_CHOICES, default='OTHER', verbose_name="Catégorie")
    title = models.CharField(max_length=200, verbose_name="Libellé")
    description = models.TextField(null=True, blank=True, verbose_name="Description")
    amount = models.DecimalField(max_digits=12, decimal_places=2, verbose_name="Montant")
    currency = models.CharField(max_length=3, default="CDF", verbose_name="Devise")
    payment_method = models.CharField(max_length=30, choices=PAYMENT_METHOD_CHOICES, default='CASH', verbose_name="Type de paiement")
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='PENDING', verbose_name="Statut")
    expense_date = models.DateField(null=True, blank=True, verbose_name="Date de la dépense")
    due_date = models.DateField(null=True, blank=True, verbose_name="Date d'échéance")
    reference = models.CharField(max_length=100, null=True, blank=True, verbose_name="Référence")
    deduct_from_fee_type = models.ForeignKey(
        FeeType, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='expenses_deducted', verbose_name="Imputé au type de frais"
    )
    document = models.FileField(upload_to='expenses/documents/', null=True, blank=True, verbose_name="Document")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Dépense"
        verbose_name_plural = "Dépenses"
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.title} - {self.amount} {self.currency}"


class CashMovement(models.Model):
    """Mouvements de caisse (entrées et sorties) - déductibles des dépenses et paiements"""
    TYPE_CHOICES = [
        ('IN', 'Entrée'),
        ('OUT', 'Sortie'),
    ]
    SOURCE_CHOICES = [
        ('PAYMENT', 'Paiement parent'),
        ('EXPENSE', 'Dépense'),
        ('ADJUSTMENT', 'Ajustement'),
        ('OTHER', 'Autre'),
    ]
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='cash_movements', verbose_name="École")
    movement_type = models.CharField(max_length=5, choices=TYPE_CHOICES, verbose_name="Type")
    amount = models.DecimalField(max_digits=12, decimal_places=2, verbose_name="Montant")
    currency = models.CharField(max_length=3, default="CDF", verbose_name="Devise")
    payment_method = models.CharField(max_length=30, null=True, blank=True, verbose_name="Type de paiement")
    source = models.CharField(max_length=20, choices=SOURCE_CHOICES, default='OTHER', verbose_name="Origine")
    description = models.CharField(max_length=255, null=True, blank=True, verbose_name="Description")
    reference_type = models.CharField(max_length=20, null=True, blank=True, verbose_name="Réf. type")
    reference_id = models.PositiveIntegerField(null=True, blank=True, verbose_name="Réf. ID")
    document = models.FileField(upload_to='caisse/bons/', null=True, blank=True, verbose_name="Bon d'entrée/sortie")
    created_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, related_name='cash_movements', verbose_name="Créé par")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "Mouvement de caisse"
        verbose_name_plural = "Mouvements de caisse"
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.get_movement_type_display()} {self.amount} {self.currency} - {self.description or self.source}"
