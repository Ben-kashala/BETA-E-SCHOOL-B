# Generated manually for payment gateways (Mobile Money)

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('payments', '0006_cashmovement_document'),
    ]

    operations = [
        migrations.AddField(
            model_name='payment',
            name='payer_phone',
            field=models.CharField(blank=True, max_length=20, null=True, verbose_name='Téléphone du payeur (Mobile Money)'),
        ),
    ]
