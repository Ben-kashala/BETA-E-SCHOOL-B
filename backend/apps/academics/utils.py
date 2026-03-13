"""
Utility functions for academics (PDF generation, class ranking, etc.)
"""
import os
from decimal import Decimal
from io import BytesIO
from django.conf import settings
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.db.models import Q
from reportlab.lib.pagesizes import letter, A4
from reportlab.pdfgen import canvas
from reportlab.lib.units import inch
from reportlab.lib import colors
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, Image
from reportlab.lib.styles import getSampleStyleSheet
from .models import ReportCard, Grade, GradeBulletin
from apps.accounts.models import Student
from apps.schools.models import SchoolClass, ClassSubject, StudentClassEnrollment


def get_class_ranking_map(school_class, academic_year):
    """
    Pour une classe et une année, retourne { student_id: {'rank': int, 'percentage': float} }.
    Utilisé pour enrichir l'historique des classes et la génération du bulletin PDF.
    """
    if not school_class or not (academic_year or '').strip():
        return {}
    ac_year = (academic_year or '').strip()
    class_subjects = ClassSubject.objects.filter(school_class=school_class).select_related('subject')
    max_per_subject = {cs.subject_id: (cs.period_max or 20) * 8 for cs in class_subjects}
    subject_ids = list(max_per_subject.keys())
    total_max = sum(max_per_subject.values()) or 1
    enrollment_ids = set(StudentClassEnrollment.objects.filter(
        school_class=school_class
    ).values_list('student_id', flat=True).distinct())
    bulletin_ids = set(GradeBulletin.objects.filter(
        school_class=school_class, academic_year=ac_year
    ).values_list('student_id', flat=True).distinct())
    student_ids = list(enrollment_ids | bulletin_ids)
    if not student_ids:
        return {}
    students = Student.objects.filter(id__in=student_ids).select_related('user')
    bulletins = GradeBulletin.objects.filter(
        student__in=students,
        academic_year=ac_year,
        subject_id__in=subject_ids,
    ).filter(Q(school_class=school_class) | Q(school_class__isnull=True)).select_related('student', 'subject')
    by_student = {}
    for b in bulletins:
        sid = b.student_id
        if sid not in by_student:
            by_student[sid] = {}
        by_student[sid][b.subject_id] = (b.total_general or Decimal('0'))
    rows = []
    for s in students:
        pts = sum(by_student.get(s.id, {}).values())
        pct = (float(pts) / total_max * 100) if total_max else 0
        name = (s.user.get_full_name() or s.user.username) if s.user else f'Élève #{s.id}'
        rows.append({'student_id': s.id, 'student_name': name, 'percentage': round(pct, 2)})
    rows.sort(key=lambda x: (-sum(by_student.get(x['student_id'], {}).values()), x['student_name']))
    for i, r in enumerate(rows, 1):
        r['rank'] = i
    return {r['student_id']: {'rank': r['rank'], 'percentage': r['percentage']} for r in rows}


def _build_bulletin_header_with_logos(story, styles):
    """
    Ajoute l'en-tête RDC avec le drapeau à gauche et les armoiries à droite,
    comme sur le bulletin officiel.
    Les fichiers doivent être placés dans STATIC_ROOT/ bulletins / :
      - rdc_flag.png
      - rdc_arms.png
    """
    title_text = (
        "<b>REPUBLIQUE DEMOCRATIQUE DU CONGO<br/>"
        "MINISTERE DE L'ENSEIGNEMENT PRIMAIRE, SECONDAIRE ET PROFESSIONNEL</b>"
    )
    title = Paragraph(title_text, styles["Title"])

    static_root = getattr(settings, "STATIC_ROOT", None) or os.path.join(settings.BASE_DIR, "static")
    bulletins_dir = os.path.join(static_root, "bulletins")

    # On supporte plusieurs noms possibles pour limiter les manipulations manuelles.
    # Priorité : rdc_flag.png / rdc_arms.png, repli : Drapeau.png / Armoirie.png
    def _first_existing(*candidates):
        for name in candidates:
            path = os.path.join(bulletins_dir, name)
            if os.path.exists(path):
                return path
        return None

    left_path = _first_existing("rdc_flag.png", "Drapeau.png")
    right_path = _first_existing("rdc_arms.png", "Armoirie.png")

    def _img_or_spacer(path):
        if path and os.path.exists(path):
            return Image(path, width=1.4 * inch, height=0.9 * inch)
        return Spacer(1.4 * inch, 0.9 * inch)

    left_img = _img_or_spacer(left_path)
    right_img = _img_or_spacer(right_path)

    header_table = Table(
        [[left_img, title, right_img]],
        colWidths=[1.4 * inch, None, 1.4 * inch],
    )
    header_table.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("ALIGN", (0, 0), (0, 0), "LEFT"),
                ("ALIGN", (1, 0), (1, 0), "CENTER"),
                ("ALIGN", (2, 0), (2, 0), "RIGHT"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 0),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
            ]
        )
    )
    story.append(header_table)
    story.append(Spacer(1, 0.15 * inch))


def generate_bulletin_grade_pdf(student, school_class, academic_year):
    """
    Génère le bulletin PDF (notes RDC) pour un élève, une classe et une année.
    Retourne un BytesIO (à envoyer en téléchargement, non enregistré).
    """
    ac_year = (academic_year or "").strip()
    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4)
    styles = getSampleStyleSheet()
    story = []

    # En-tête officiel avec logos
    school = getattr(student.user, "school", None)
    school_name = getattr(school, "name", None) or "-"
    _build_bulletin_header_with_logos(story, styles)

    resolved_class = school_class or getattr(student, "school_class", None)
    class_name = resolved_class.name if resolved_class else "N/A"
    header = f"<b>BULLETIN DE LA {class_name}</b> &nbsp;&nbsp; <b>ANNÉE SCOLAIRE :</b> {ac_year}"
    story.append(Paragraph(header, styles["Heading3"]))
    story.append(Spacer(1, 0.1 * inch))

    info = f"""
    <b>École:</b> {school_name}<br/>
    <b>Élève:</b> {student.user.get_full_name() if student.user else 'N/A'} &nbsp;&nbsp;
    <b>Matricule:</b> {getattr(student, 'student_id', '') or '-'} &nbsp;&nbsp;
    <b>Classe:</b> {class_name}
    """
    story.append(Paragraph(info, styles["Normal"]))
    story.append(Spacer(1, 0.25 * inch))

    # Tableau des notes (GradeBulletin pour cette classe et année)
    grades_qs = GradeBulletin.objects.filter(
        student=student,
        academic_year=ac_year,
    ).filter(Q(school_class=resolved_class) | Q(school_class__isnull=True)).select_related("subject")

    headers = [
        'BRANCHES',
        '1ère P.', '2ème P.', 'EXAM.', 'TOT. S1',
        '3ème P.', '4ème P.', 'EXAM.', 'TOT. S2',
        'T.G.', 'Repêch. %'
    ]
    headers = headers
    data = [headers]

    # Regroupement par domaine à partir de ClassSubject pour cette classe
    class_subjects = []
    if resolved_class:
        class_subjects = list(
            ClassSubject.objects.filter(school_class=resolved_class).select_related("subject")
        )
    cs_by_subject_id = {cs.subject_id: cs for cs in class_subjects}

    domains = {}
    for g in grades_qs:
        subj = g.subject
        if not subj:
            continue
        cs = cs_by_subject_id.get(subj.id)
        domain_label = (getattr(cs, "domain", None) or "AUTRES").upper()
        domains.setdefault(domain_label, []).append((g, cs))

    def _grade_value(grade_obj, field, default="-"):
        v = getattr(grade_obj, field, None)
        if v is not None and v != "":
            try:
                return str(Decimal(str(v)).quantize(Decimal("0.01")))
            except Exception:
                return default
        return default

    # Tri des matières dans chaque domaine par note de base (period_max) décroissante
    for dom, items in domains.items():
        items.sort(
            key=lambda tpl: getattr(tpl[1], "period_max", getattr(tpl[0].subject, "period_max", 20)),
            reverse=True,
        )

    def _domain_weight(items):
        total = 0
        for _, cs in items:
            base = getattr(cs, "period_max", None)
            if base is None and cs and hasattr(cs, "subject"):
                base = getattr(cs.subject, "period_max", 20)
            if base is None:
                base = 20
            total += int(base)
        return total

    sorted_domains = sorted(domains.items(), key=lambda kv: _domain_weight(kv[1]), reverse=True)

    if sorted_domains:
        for dom, items in sorted_domains:
            # Ligne de domaine
            data.append([dom] + [""] * (len(headers) - 1))
            for g, cs in items:
                data.append(
                    [
                        g.subject.name if g.subject else "-",
                        _grade_value(g, "s1_p1"),
                        _grade_value(g, "s1_p2"),
                        _grade_value(g, "s1_exam"),
                        _grade_value(g, "total_s1"),
                        _grade_value(g, "s2_p3"),
                        _grade_value(g, "s2_p4"),
                        _grade_value(g, "s2_exam"),
                        _grade_value(g, "total_s2"),
                        _grade_value(g, "total_general"),
                        _grade_value(g, "reclamation_score"),
                    ]
                )
    else:
        # Repli : comportement d'origine, simple liste de matières
        for g in grades_qs.order_by("subject__name"):
            data.append(
                [
                    g.subject.name if g.subject else "-",
                    _grade_value(g, "s1_p1"),
                    _grade_value(g, "s1_p2"),
                    _grade_value(g, "s1_exam"),
                    _grade_value(g, "total_s1"),
                    _grade_value(g, "s2_p3"),
                    _grade_value(g, "s2_p4"),
                    _grade_value(g, "s2_exam"),
                    _grade_value(g, "total_s2"),
                    _grade_value(g, "total_general"),
                    _grade_value(g, "reclamation_score"),
                ]
            )

    if len(data) > 1:
        col_widths = [1.4 * inch] + [0.5 * inch] * 10
        table = Table(data, colWidths=col_widths)
        table.setStyle(
            TableStyle(
                [
                    ("BACKGROUND", (0, 0), (-1, 0), colors.grey),
                    ("TEXTCOLOR", (0, 0), (-1, 0), colors.whitesmoke),
                    ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                    ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                    ("FONTSIZE", (0, 0), (-1, -1), 8),
                    ("GRID", (0, 0), (-1, -1), 0.5, colors.black),
                ]
            )
        )
        story.append(table)
    else:
        story.append(
            Paragraph(
                "<i>Aucune note (bulletin RDC) enregistrée pour cette classe et année.</i>",
                styles["Normal"],
            )
        )

    story.append(Spacer(1, 0.2*inch))
    # Place et Pourcentage (depuis le classement)
    ranking = get_class_ranking_map(school_class, ac_year).get(student.id, {})
    rank = ranking.get('rank')
    pct = ranking.get('percentage')
    place = f"{rank}" if rank is not None else '-'
    pct_str = f"{pct} %" if pct is not None else '-'
    story.append(Paragraph(
        f"<b>Place:</b> {place} &nbsp;&nbsp; <b>Pourcentage:</b> {pct_str}",
        styles['Normal']
    ))

    doc.build(story)
    buffer.seek(0)
    return buffer


def generate_bulletin_rdc_pdf(report_card):
    """
    Génère le bulletin au format officiel RDC: 2 semestres, 4 périodes (Trav. journaliers),
    2 examens, TOT. S1/S2, T.G., repêchage; APPLICATION, CONDUITE, Place, Décision.
    """
    from decimal import Decimal
    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4)
    styles = getSampleStyleSheet()
    story = []

    student = report_card.student
    school = getattr(student.user, "school", None)
    school_name = getattr(school, "name", None) or "-"
    province = getattr(school, "province", None) or "-"
    city = getattr(school, "city", None) or "-"
    commune = getattr(school, "commune", None) or "-"
    code_ecole = getattr(school, "code", None) or "-"

    # En-tête officiel RDC avec logos
    _build_bulletin_header_with_logos(story, styles)

    # Ligne "BULLETIN DE LA ... ANNÉE SCOLAIRE ..."
    classe_name = student.school_class.name if student.school_class else "CLASSE"
    header_text = f"BULLETIN DE LA {classe_name} &nbsp;&nbsp; ANNÉE SCOLAIRE : {report_card.academic_year}"
    story.append(Paragraph(f"<b>{header_text}</b>", styles["Heading3"]))
    story.append(Spacer(1, 0.1 * inch))

    # Informations école
    school_block = f"""
    <b>PROVINCE :</b> {province} &nbsp;&nbsp;
    <b>VILLE :</b> {city} &nbsp;&nbsp;
    <b>COMMUNE / TER. :</b> {commune}<br/>
    <b>ECOLE :</b> {school_name} &nbsp;&nbsp;
    <b>CODE :</b> {code_ecole}
    """
    story.append(Paragraph(school_block, styles["Normal"]))
    story.append(Spacer(1, 0.1 * inch))

    # Identité élève : Élève, Sexe, Né(e) à, le, Classe, N° perm.
    user = student.user
    full_name = user.get_full_name()
    sex = getattr(student, "gender", None)
    if not sex and hasattr(user, "gender"):
        sex = getattr(user, "gender")
    if sex == "M":
        sex_label = "M"
    elif sex == "F":
        sex_label = "F"
    else:
        sex_label = "-"
    place_of_birth = getattr(student, "place_of_birth", None) or "-"
    dob = getattr(user, "date_of_birth", None)
    dob_str = dob.strftime("%d/%m/%Y") if dob else "-"

    student_block = f"""
    <b>ELEVE :</b> {full_name} &nbsp;&nbsp;
    <b>SEXE :</b> {sex_label} &nbsp;&nbsp;
    <b>NE(E) A :</b> {place_of_birth} &nbsp;&nbsp;
    <b>LE :</b> {dob_str}<br/>
    <b>CLASSE :</b> {classe_name} &nbsp;&nbsp;
    <b>N° PERM. :</b> {student.student_id}
    """
    story.append(Paragraph(student_block, styles["Normal"]))
    story.append(Spacer(1, 0.25 * inch))

    # Tableau des notes (GradeBulletin) regroupé par domaine et trié par note de base
    grades_qs = GradeBulletin.objects.filter(
        student=student,
        academic_year=report_card.academic_year,
    ).select_related("subject", "school_class")

    # Classe utilisée pour retrouver les domaines/note de base
    resolved_class = student.school_class
    class_subjects = []
    if resolved_class:
        class_subjects = list(
            ClassSubject.objects.filter(school_class=resolved_class).select_related("subject")
        )
    cs_by_subject_id = {cs.subject_id: cs for cs in class_subjects}

    headers = [
        'BRANCHES',
        '1ère P.', '2ème P.', 'EXAM.', 'TOT. S1',
        '3ème P.', '4ème P.', 'EXAM.', 'TOT. S2',
        'T.G.', 'Repêch. %'
    ]
    data = [headers]

    def _grade_value(g, field, default="-"):
        v = getattr(g, field, None)
        if v is not None and v != "":
            try:
                return str(Decimal(str(v)).quantize(Decimal("0.01")))
            except Exception:
                return default
        return default

    # Regroupement par domaine
    domains = {}
    for g in grades_qs:
        subj = g.subject
        if not subj:
            continue
        cs = cs_by_subject_id.get(subj.id)
        domain_label = (getattr(cs, "domain", None) or "AUTRES").upper()
        domains.setdefault(domain_label, []).append((g, cs))

    # Tri des matières dans chaque domaine par note de base décroissante
    for dom, items in domains.items():
        items.sort(
            key=lambda tpl: getattr(tpl[1], "period_max", getattr(tpl[0].subject, "period_max", 20)),
            reverse=True,
        )

    def _domain_weight(items):
        total = 0
        for _, cs in items:
            base = getattr(cs, "period_max", None)
            if base is None and cs and hasattr(cs, "subject"):
                base = getattr(cs.subject, "period_max", 20)
            if base is None:
                base = 20
            total += int(base)
        return total

    sorted_domains = sorted(domains.items(), key=lambda kv: _domain_weight(kv[1]), reverse=True)

    if sorted_domains:
        for dom, items in sorted_domains:
            data.append([dom] + [""] * (len(headers) - 1))
            for g, cs in items:
                data.append(
                    [
                        g.subject.name if g.subject else "-",
                        _grade_value(g, "s1_p1"),
                        _grade_value(g, "s1_p2"),
                        _grade_value(g, "s1_exam"),
                        _grade_value(g, "total_s1"),
                        _grade_value(g, "s2_p3"),
                        _grade_value(g, "s2_p4"),
                        _grade_value(g, "s2_exam"),
                        _grade_value(g, "total_s2"),
                        _grade_value(g, "total_general"),
                        _grade_value(g, "reclamation_score"),
                    ]
                )
    else:
        # Repli : tableau simple ordonné par matière
        for g in grades_qs.order_by("subject__name"):
            data.append(
                [
                    g.subject.name if g.subject else "-",
                    _grade_value(g, "s1_p1"),
                    _grade_value(g, "s1_p2"),
                    _grade_value(g, "s1_exam"),
                    _grade_value(g, "total_s1"),
                    _grade_value(g, "s2_p3"),
                    _grade_value(g, "s2_p4"),
                    _grade_value(g, "s2_exam"),
                    _grade_value(g, "total_s2"),
                    _grade_value(g, "total_general"),
                    _grade_value(g, "reclamation_score"),
                ]
            )

    if len(data) > 1:
        col_widths = [1.4 * inch] + [0.5 * inch] * 10
        table = Table(data, colWidths=col_widths)
        table.setStyle(
            TableStyle(
                [
                    ("BACKGROUND", (0, 0), (-1, 0), colors.grey),
                    ("TEXTCOLOR", (0, 0), (-1, 0), colors.whitesmoke),
                    ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                    ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                    ("FONTSIZE", (0, 0), (-1, -1), 8),
                    ("GRID", (0, 0), (-1, -1), 0.5, colors.black),
                ]
            )
        )
        story.append(table)
    else:
        story.append(
            Paragraph("<i>Aucune note (bulletin RDC) enregistrée.</i>", styles["Normal"])
        )

    story.append(Spacer(1, 0.2*inch))
    # APPLICATION, CONDUITE, Place
    app = report_card.application if report_card.application is not None else '-'
    cond = report_card.conduite if report_card.conduite is not None else '-'
    place = f"{report_card.rank or '-'} / {report_card.total_students or '-'}"
    story.append(Paragraph(
        f"<b>Application:</b> {app} &nbsp;&nbsp; <b>Conduite:</b> {cond} &nbsp;&nbsp; "
        f"<b>Place / Nombre d'élèves:</b> {place}",
        styles['Normal']
    ))
    if report_card.decision:
        story.append(Paragraph(f"<b>Décision:</b> {report_card.get_decision_display()}", styles['Normal']))
    if report_card.reclamation_subject:
        story.append(Paragraph(
            f"<b>Repêchage:</b> {report_card.reclamation_subject.name} — "
            f"Réussi: {'Oui' if report_card.reclamation_passed else 'Non'}",
            styles['Normal']
        ))
    story.append(Spacer(1, 0.15*inch))
    if report_card.teacher_comment:
        story.append(Paragraph(f"<b>Commentaire du titulaire:</b> {report_card.teacher_comment}", styles['Normal']))
    if report_card.principal_comment:
        story.append(Paragraph(f"<b>Chef d'établissement:</b> {report_card.principal_comment}", styles['Normal']))

    doc.build(story)
    buffer.seek(0)
    filename = f"academics/report_cards/bulletin_rdc_{report_card.id}.pdf"
    file_content = ContentFile(buffer.read())
    return default_storage.save(filename, file_content)


def generate_report_card_pdf(report_card):
    """Generate PDF report card"""
    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4)
    styles = getSampleStyleSheet()
    story = []
    
    # Title
    title = Paragraph(f"<b>BULLETIN SCOLAIRE</b>", styles['Title'])
    story.append(title)
    story.append(Spacer(1, 0.2*inch))
    
    # Student info
    student = report_card.student
    student_info = f"""
    <b>Élève:</b> {student.user.get_full_name()}<br/>
    <b>Matricule:</b> {student.student_id}<br/>
    <b>Classe:</b> {student.school_class.name if student.school_class else 'N/A'}<br/>
    <b>Année scolaire:</b> {report_card.academic_year}<br/>
    <b>Trimestre:</b> {report_card.get_term_display()}<br/>
    """
    story.append(Paragraph(student_info, styles['Normal']))
    story.append(Spacer(1, 0.3*inch))
    
    # Grades table
    grades = Grade.objects.filter(
        student=student,
        academic_year=report_card.academic_year,
        term=report_card.term
    )
    
    if grades.exists():
        data = [['Matière', 'Contrôle continu', 'Examen', 'Total', 'Appréciation']]
        
        for grade in grades:
            appreciation = get_appreciation(grade.total_score)
            data.append([
                grade.subject.name,
                str(grade.continuous_assessment),
                str(grade.exam_score) if grade.exam_score else '-',
                str(grade.total_score),
                appreciation
            ])
        
        # Summary row
        data.append([
            '<b>TOTAL</b>',
            '',
            '',
            f'<b>{report_card.average_score}/20</b>',
            get_appreciation(report_card.average_score)
        ])
        
        table = Table(data, colWidths=[2*inch, 1*inch, 1*inch, 1*inch, 1.5*inch])
        table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), colors.grey),
            ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
            ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
            ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
            ('FONTSIZE', (0, 0), (-1, 0), 12),
            ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
            ('BACKGROUND', (0, 1), (-1, -2), colors.beige),
            ('GRID', (0, 0), (-1, -1), 1, colors.black),
            ('FONTSIZE', (0, 1), (-1, -1), 10),
        ]))
        
        story.append(table)
        story.append(Spacer(1, 0.3*inch))
    
    # Comments
    if report_card.teacher_comment:
        story.append(Paragraph("<b>Commentaire de l'enseignant:</b>", styles['Heading3']))
        story.append(Paragraph(report_card.teacher_comment, styles['Normal']))
        story.append(Spacer(1, 0.2*inch))
    
    if report_card.principal_comment:
        story.append(Paragraph("<b>Commentaire du directeur:</b>", styles['Heading3']))
        story.append(Paragraph(report_card.principal_comment, styles['Normal']))
    
    # Rank
    if report_card.rank:
        story.append(Spacer(1, 0.2*inch))
        rank_text = f"<b>Rang:</b> {report_card.rank}/{report_card.total_students}"
        story.append(Paragraph(rank_text, styles['Normal']))
    
    doc.build(story)
    buffer.seek(0)
    
    filename = f"academics/report_cards/report_{report_card.id}.pdf"
    file_content = ContentFile(buffer.read())
    saved_file = default_storage.save(filename, file_content)
    
    return saved_file


def get_appreciation(score):
    """Get appreciation based on score"""
    if score >= 16:
        return "Excellent"
    elif score >= 14:
        return "Très bien"
    elif score >= 12:
        return "Bien"
    elif score >= 10:
        return "Assez bien"
    elif score >= 8:
        return "Passable"
    else:
        return "Insuffisant"
