# Generated manually for platform lock feature

from django.db import migrations, models


def create_platform_settings_singleton(apps, schema_editor):
    """Crée l'unique instance (id=1) des paramètres plateforme."""
    PlatformSettings = apps.get_model('accounts', 'PlatformSettings')
    PlatformSettings.objects.get_or_create(
        pk=1,
        defaults={'is_platform_locked': False}
    )


def noop(apps, schema_editor):
    pass


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0007_user_address_avenue_user_address_city_and_more'),
    ]

    operations = [
        migrations.CreateModel(
            name='PlatformSettings',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('is_platform_locked', models.BooleanField(default=False, help_text='Si coché, seul le superadmin peut se connecter (mobile, frontend, admin Django).', verbose_name='Plateforme verrouillée')),
                ('locked_message', models.CharField(blank=True, help_text="Optionnel. Ex : Maintenance en cours.", max_length=255, null=True, verbose_name='Message affiché aux utilisateurs bloqués')),
                ('updated_at', models.DateTimeField(auto_now=True, verbose_name='Dernière modification')),
            ],
            options={
                'verbose_name': 'Paramètres plateforme',
                'verbose_name_plural': 'Paramètres plateforme',
                'db_table': 'accounts_platform_settings',
            },
        ),
        migrations.RunPython(create_platform_settings_singleton, noop),
    ]
