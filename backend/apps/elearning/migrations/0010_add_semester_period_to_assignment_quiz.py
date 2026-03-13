# Generated for bulletin sync: semester and period on Assignment and Quiz

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('elearning', '0009_alter_assignment_academic_year_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='assignment',
            name='semester',
            field=models.CharField(choices=[('S1', 'Premier semestre'), ('S2', 'Second semestre')], default='S1', max_length=2, verbose_name='Semestre (pour bulletin)'),
        ),
        migrations.AddField(
            model_name='assignment',
            name='period',
            field=models.PositiveSmallIntegerField(default=1, verbose_name='Période (1 à 4, pour bulletin)'),
        ),
        migrations.AddField(
            model_name='quiz',
            name='semester',
            field=models.CharField(choices=[('S1', 'Premier semestre'), ('S2', 'Second semestre')], default='S1', max_length=2, verbose_name='Semestre (pour bulletin)'),
        ),
        migrations.AddField(
            model_name='quiz',
            name='period',
            field=models.PositiveSmallIntegerField(default=1, verbose_name='Période (1 à 4, pour bulletin)'),
        ),
    ]
