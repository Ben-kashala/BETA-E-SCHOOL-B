from django.db import migrations, models
from django.db.models import Q
from django.db.models.functions import Lower


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0008_platformsettings'),
    ]

    operations = [
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
