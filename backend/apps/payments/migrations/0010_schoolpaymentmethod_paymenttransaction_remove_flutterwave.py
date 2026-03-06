# Migration: Mobile Money Airtel/Orange/M-Pesa — modèles SchoolPaymentMethod, PaymentTransaction, suppression Flutterwave

from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0001_initial'),
        ('schools', '0001_initial'),
        ('payments', '0009_mobile_money_default_flutterwave'),
    ]

    operations = [
        migrations.CreateModel(
            name='SchoolPaymentMethod',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('provider', models.CharField(choices=[('airtel', 'Airtel Money'), ('orange', 'Orange Money'), ('mpesa', 'M-Pesa')], max_length=20, verbose_name='Opérateur')),
                ('merchant_number', models.CharField(help_text='Ex: +243810000000', max_length=30, verbose_name='Numéro Mobile Money (réception)')),
                ('status', models.CharField(choices=[('active', 'Actif'), ('inactive', 'Inactif')], default='active', max_length=20, verbose_name='Statut')),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('school', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='payment_methods', to='schools.school', verbose_name='École')),
            ],
            options={
                'verbose_name': 'Moyen de paiement (école)',
                'verbose_name_plural': 'Moyens de paiement (écoles)',
                'ordering': ['school', 'provider'],
                'unique_together': {('school', 'provider')},
            },
        ),
        migrations.CreateModel(
            name='PaymentTransaction',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('provider', models.CharField(max_length=20, verbose_name='Opérateur (airtel, orange, mpesa)')),
                ('phone', models.CharField(max_length=30, verbose_name='Téléphone du payeur')),
                ('amount', models.DecimalField(decimal_places=2, max_digits=12, verbose_name='Montant')),
                ('reference', models.CharField(help_text='Format SCH{id}-STU{id}-INV{id} pour identifier école, élève, facture/paiement', max_length=100, unique=True, verbose_name='Référence')),
                ('status', models.CharField(choices=[('pending', 'En attente'), ('processing', 'En cours'), ('completed', 'Complété'), ('failed', 'Échoué'), ('cancelled', 'Annulé')], default='pending', max_length=20, verbose_name='Statut')),
                ('provider_transaction_id', models.CharField(blank=True, max_length=100, null=True, verbose_name='ID transaction opérateur')),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('payment', models.OneToOneField(blank=True, null=True, on_delete=django.db.models.deletion.CASCADE, related_name='mobile_money_transaction', to='payments.payment', verbose_name='Paiement lié')),
                ('school', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='payment_transactions', to='schools.school', verbose_name='École')),
                ('student', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='payment_transactions', to='accounts.student', verbose_name='Élève')),
            ],
            options={
                'verbose_name': 'Transaction Mobile Money',
                'verbose_name_plural': 'Transactions Mobile Money',
                'ordering': ['-created_at'],
            },
        ),
        migrations.RemoveField(
            model_name='schoolpaymentconfig',
            name='flutterwave_public_key',
        ),
        migrations.RemoveField(
            model_name='schoolpaymentconfig',
            name='flutterwave_secret_key',
        ),
        migrations.RemoveField(
            model_name='schoolpaymentconfig',
            name='mobile_money_provider',
        ),
    ]
