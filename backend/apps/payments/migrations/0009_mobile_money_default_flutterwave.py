# Generated migration: Mobile Money par défaut = Flutterwave

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('payments', '0008_schoolpaymentconfig'),
    ]

    operations = [
        migrations.AlterField(
            model_name='schoolpaymentconfig',
            name='mobile_money_provider',
            field=models.CharField(
                choices=[('mock', 'Mock (démo)'), ('flutterwave', 'Flutterwave (Orange, M-Pesa, Airtel)')],
                default='flutterwave',
                max_length=20,
                verbose_name='Provider Mobile Money',
            ),
        ),
    ]
