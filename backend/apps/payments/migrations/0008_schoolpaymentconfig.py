# Generated manually - Configuration moyens de paiement par école (multi-tenant)

from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('schools', '0001_initial'),
        ('payments', '0007_add_payer_phone'),
    ]

    operations = [
        migrations.CreateModel(
            name='SchoolPaymentConfig',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('is_active', models.BooleanField(default=True, verbose_name='Actif')),
                ('flutterwave_public_key', models.CharField(blank=True, max_length=255, verbose_name='Clé publique Flutterwave')),
                ('flutterwave_secret_key', models.CharField(blank=True, max_length=255, verbose_name='Clé secrète Flutterwave')),
                ('mobile_money_provider', models.CharField(choices=[('mock', 'Mock (démo)'), ('flutterwave', 'Flutterwave (Orange, M-Pesa, Airtel)')], default='mock', max_length=20, verbose_name='Provider Mobile Money')),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('school', models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name='payment_config', to='schools.school', verbose_name='École')),
            ],
            options={
                'verbose_name': 'Configuration paiement (école)',
                'verbose_name_plural': 'Configurations paiement (écoles)',
            },
        ),
    ]
