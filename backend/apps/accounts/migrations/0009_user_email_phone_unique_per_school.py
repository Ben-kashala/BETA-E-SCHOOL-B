from django.db import migrations, models
from django.db.models import Q
from django.db.models.functions import Lower


def _build_deduplicated_email(base_email, user_pk):
    email = (base_email or '').strip()
    if '@' not in email:
        return ''

    local_part, domain = email.split('@', 1)
    suffix = f'+dup{user_pk}'
    max_local_length = max(1, 254 - len(domain) - 1 - len(suffix))
    local_part = local_part[:max_local_length]
    return f'{local_part}{suffix}@{domain}'


def deduplicate_user_contacts(apps, schema_editor):
    User = apps.get_model('accounts', 'User')

    # Normalise d'abord les valeurs avec espaces parasites.
    for user in User.objects.exclude(email__isnull=True):
        cleaned_email = (user.email or '').strip()
        cleaned_phone = (user.phone or '').strip() if user.phone is not None else user.phone
        updates = []
        if cleaned_email != user.email:
            user.email = cleaned_email
            updates.append('email')
        if cleaned_phone != user.phone:
            user.phone = cleaned_phone
            updates.append('phone')
        if updates:
            user.save(update_fields=updates)

    # Dédoublonne les emails insensibles à la casse par école.
    seen_emails = set()
    for user in User.objects.exclude(email__isnull=True).exclude(email='').order_by('school_id', 'created_at', 'id'):
        key = (user.school_id, user.email.lower())
        if key in seen_emails:
            user.email = _build_deduplicated_email(user.email, user.pk)
            user.save(update_fields=['email'])
        else:
            seen_emails.add(key)

    # Dédoublonne les téléphones exacts par école.
    # On vide les occurrences supplémentaires pour éviter d'inventer de faux numéros.
    seen_phones = set()
    for user in User.objects.exclude(phone__isnull=True).exclude(phone='').order_by('school_id', 'created_at', 'id'):
        key = (user.school_id, user.phone)
        if key in seen_phones:
            user.phone = ''
            user.save(update_fields=['phone'])
        else:
            seen_phones.add(key)


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0008_platformsettings'),
    ]

    operations = [
        migrations.RunPython(deduplicate_user_contacts, migrations.RunPython.noop),
        migrations.AddConstraint(
            model_name='user',
            constraint=models.UniqueConstraint(
                Lower('email'),
                'school',
                condition=Q(email__isnull=False) & ~Q(email=''),
                name='uniq_user_email_per_school_ci',
            ),
        ),
        migrations.AddConstraint(
            model_name='user',
            constraint=models.UniqueConstraint(
                'phone',
                'school',
                condition=Q(phone__isnull=False) & ~Q(phone=''),
                name='uniq_user_phone_per_school',
            ),
        ),
    ]
