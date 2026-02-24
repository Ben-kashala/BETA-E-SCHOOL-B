"""
Création de notifications in-app pour informer les utilisateurs des actions nécessitant un suivi.
"""
from apps.communication.models import Notification
from apps.accounts.models import User


def notify_user(school, user, notification_type, title, message, related_object_type=None, related_object_id=None):
    """Crée une notification pour un utilisateur."""
    if not user or not school:
        return None
    return Notification.objects.create(
        school=school,
        user=user,
        notification_type=notification_type,
        title=title,
        message=message,
        related_object_type=related_object_type or '',
        related_object_id=related_object_id,
    )


def notify_users(school, users, notification_type, title, message, related_object_type=None, related_object_id=None):
    """Crée une notification pour chaque utilisateur (évite les doublons, ignore les None)."""
    created = []
    seen = set()
    for user in users:
        if not user or user.id in seen:
            continue
        seen.add(user.id)
        if user.school_id != school.id:
            continue
        n = notify_user(school, user, notification_type, title, message, related_object_type, related_object_id)
        if n:
            created.append(n)
    return created


def notify_payment_made(payment):
    """
    Appelé quand un parent effectue un paiement : notifier admin(s) et comptable(s) de l'école
    pour suivi.
    """
    school = payment.school
    if not school:
        return []
    # Éviter de notifier si c'est l'admin/comptable qui enregistre le paiement (au nom du parent)
    payee = payment.user
    if not payee or payee.role != 'PARENT':
        # Paiement enregistré par l'école, pas besoin de notifier pour "suivi"
        return []
    admins = list(User.objects.filter(school=school, role='ADMIN', is_active=True))
    accountants = list(User.objects.filter(school=school, role='ACCOUNTANT', is_active=True))
    recipients = admins + [u for u in accountants if u not in admins]
    title = "Nouveau paiement effectué"
    message = f"Un parent a effectué un paiement de {payment.amount} {payment.currency} (réf. {payment.payment_id}). Veuillez en assurer le suivi."
    return notify_users(
        school,
        recipients,
        'PAYMENT',
        title,
        message,
        related_object_type='payment',
        related_object_id=payment.id,
    )


def notify_discipline_record_created(record):
    """
    Appelé quand une fiche de discipline est remplie (chargé de discipline / enseignant / admin) :
    notifier l'élève, le parent et l'admin école pour suivi.
    """
    school = record.student.user.school if record.student and record.student.user else None
    if not school:
        return []
    recipients = []
    # Élève (compte utilisateur de l'élève)
    if record.student and record.student.user:
        recipients.append(record.student.user)
    # Parent
    if record.student and record.student.parent:
        recipients.append(record.student.parent)
    # Admin(s) de l'école
    admins = list(User.objects.filter(school=school, role='ADMIN', is_active=True))
    for a in admins:
        if a not in recipients:
            recipients.append(a)
    student_name = record.student.user.get_full_name() if record.student and record.student.user else "Élève"
    title = "Nouvelle fiche de discipline"
    message = f"Une fiche de discipline a été enregistrée pour {student_name} ({record.get_type_display()}, {record.get_severity_display()}). Consultez les détails pour le suivi."
    return notify_users(
        school,
        recipients,
        'DISCIPLINE',
        title,
        message,
        related_object_type='discipline_record',
        related_object_id=record.id,
    )
