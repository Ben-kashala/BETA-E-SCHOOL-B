"""
Création de notifications in-app pour informer les utilisateurs des actions nécessitant un suivi.
"""
from apps.communication.models import Notification
from apps.accounts.models import User, Student


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


def notify_message_received(message):
    """Appelé quand un message est envoyé : notifier le destinataire."""
    school = getattr(message.sender, 'school', None) or getattr(message.recipient, 'school', None)
    if not school or not message.recipient:
        return []
    sender_name = message.sender.get_full_name() if message.sender else 'Un utilisateur'
    title = "Nouveau message"
    msg_text = f"{sender_name} vous a envoyé un message : « {message.subject} »."
    return notify_users(
        school,
        [message.recipient],
        'MESSAGE',
        title,
        msg_text,
        related_object_type='message',
        related_object_id=message.id,
    )


def notify_announcement_published(announcement):
    """Appelé quand une annonce est publiée : notifier le public cible."""
    school = announcement.school
    if not school or not getattr(announcement, 'send_notification', True):
        return []
    target = announcement.target_audience or 'ALL'
    if target == 'ALL':
        users = list(User.objects.filter(school=school, is_active=True))
    elif target == 'STUDENTS':
        users = list(User.objects.filter(role='STUDENT', school=school, is_active=True))
    elif target == 'PARENTS':
        users = list(User.objects.filter(role='PARENT', school=school, is_active=True))
    elif target == 'TEACHERS':
        users = list(User.objects.filter(role='TEACHER', school=school, is_active=True))
    elif target == 'ADMINS':
        users = list(User.objects.filter(role='ADMIN', school=school, is_active=True))
    else:
        users = list(User.objects.filter(school=school, is_active=True))
    title = "Nouvelle annonce"
    message = f"{announcement.title}. {announcement.message[:150]}{'…' if len(announcement.message) > 150 else ''}"
    return notify_users(
        school,
        users,
        'ANNOUNCEMENT',
        title,
        message,
        related_object_type='announcement',
        related_object_id=announcement.id,
    )


def notify_meeting_created(meeting):
    """Appelé quand une réunion est créée : notifier enseignant, parent, élève et participants."""
    school = meeting.school
    if not school:
        return []
    recipients = []
    if meeting.teacher and meeting.teacher.user:
        recipients.append(meeting.teacher.user)
    if meeting.parent and meeting.parent.user:
        recipients.append(meeting.parent.user)
    if meeting.student and meeting.student.user:
        recipients.append(meeting.student.user)
    for p in meeting.participants.all():
        if p.user and p.user not in recipients:
            recipients.append(p.user)
    if not recipients:
        return []
    from django.utils import timezone
    date_str = meeting.meeting_date.strftime('%d/%m/%Y à %H:%M') if meeting.meeting_date else ''
    title = "Nouvelle réunion planifiée"
    message = f"Réunion « {meeting.title} » le {date_str}. Consultez les détails pour le lien visio."
    return notify_users(
        school,
        recipients,
        'MEETING',
        title,
        message,
        related_object_type='meeting',
        related_object_id=meeting.id,
    )


def _students_and_parents_for_class(school_class):
    """Retourne la liste des User (élèves + parents) concernés par une classe."""
    if not school_class or not school_class.school:
        return []
    students = Student.objects.filter(
        school_class=school_class,
        user__school_id=school_class.school_id,
        user__is_active=True,
    ).select_related('user')
    users = []
    seen = set()
    for s in students:
        if s.user_id and s.user_id not in seen:
            users.append(s.user)
            seen.add(s.user_id)
        if s.parent_id and s.parent_id not in seen:
            users.append(s.parent)
            seen.add(s.parent_id)
    return users


def notify_assignment_published(assignment):
    """Appelé quand un devoir est publié : notifier les élèves (et parents) de la classe."""
    school = getattr(assignment.school_class, 'school', None) if assignment.school_class else None
    if not school:
        return []
    recipients = _students_and_parents_for_class(assignment.school_class)
    if not recipients:
        return []
    title = "Nouveau devoir"
    due = assignment.due_date.strftime('%d/%m/%Y') if assignment.due_date else ''
    message = f"Devoir « {assignment.title} » à rendre pour le {due}. Consultez la section Devoirs."
    return notify_users(
        school,
        recipients,
        'ASSIGNMENT',
        title,
        message,
        related_object_type='assignment',
        related_object_id=assignment.id,
    )


def notify_quiz_published(quiz):
    """Appelé quand une interrogation/examen est publiée : notifier les élèves (et parents) de la classe."""
    school = getattr(quiz.school_class, 'school', None) if quiz.school_class else None
    if not school:
        return []
    recipients = _students_and_parents_for_class(quiz.school_class)
    if not recipients:
        return []
    title = "Nouvelle interrogation / Examen"
    message = f"« {quiz.title} » est disponible. Consultez la section Examens / Quiz."
    return notify_users(
        school,
        recipients,
        'QUIZ',
        title,
        message,
        related_object_type='quiz',
        related_object_id=quiz.id,
    )
