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


def _build_bulletin_header_with_logos(story, styles, logo_width=1.15 * inch, logo_height=0.75 * inch, spacer_after=0.06 * inch):
    """
    Ajoute l'en-tête RDC avec le drapeau à gauche et les armoiries à droite,
    comme sur le bulletin officiel (format compact une page).
    """
    from reportlab.lib.styles import ParagraphStyle
    small_title = ParagraphStyle(
        name="BulletinTitle",
        parent=styles["Title"],
        fontSize=9,
        leading=11,
        spaceAfter=0,
    )
    title_text = (
        "<b>REPUBLIQUE DEMOCRATIQUE DU CONGO<br/>"
        "MINISTERE DE L'ENSEIGNEMENT PRIMAIRE, SECONDAIRE ET PROFESSIONNEL</b>"
    )
    title = Paragraph(title_text, small_title)

    static_root = getattr(settings, "STATIC_ROOT", None) or os.path.join(settings.BASE_DIR, "static")
    bulletins_dir = os.path.join(static_root, "bulletins")

    def _first_existing(*candidates):
        for name in candidates:
            path = os.path.join(bulletins_dir, name)
            if os.path.exists(path):
                return path
        return None

    left_path = _first_existing("rdc_flag.png", "Drapeau.png")
    right_path = _first_existing("rdc_arms.png", "Armoirie.png")

    def _img_or_spacer(path, w, h):
        if path and os.path.exists(path):
            return Image(path, width=w, height=h)
        return Spacer(w, h)

    left_img = _img_or_spacer(left_path, logo_width, logo_height)
    right_img = _img_or_spacer(right_path, logo_width, logo_height)

    header_table = Table(
        [[left_img, title, right_img]],
        colWidths=[logo_width, None, logo_width],
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
    story.append(Spacer(1, spacer_after))


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

    if len(data) <= 1:
        # Aucun domaine / matière : on garde le modèle brouillon avec quelques lignes vides
        for _ in range(6):
            data.append([""] * len(headers))

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


def _bulletin_logo_path(filename):
    """Retourne le chemin absolu du logo si trouvé (static/bulletins ou STATIC_ROOT/bulletins)."""
    base = getattr(settings, "BASE_DIR", None)
    if base:
        p = os.path.join(str(base), "static", "bulletins", filename)
        if os.path.isfile(p):
            return p
    static_root = getattr(settings, "STATIC_ROOT", None)
    if static_root:
        p = os.path.join(str(static_root), "bulletins", filename)
        if os.path.isfile(p):
            return p
    # Repli : depuis backend (parent de config), static/bulletins
    this_dir = os.path.dirname(os.path.abspath(__file__))
    for _ in range(3):
        parent = os.path.dirname(this_dir)
        p = os.path.join(parent, "static", "bulletins", filename)
        if os.path.isfile(p):
            return p
        this_dir = parent
    return None


def generate_bulletin_rdc_pdf(report_card):
    """
    Génère le bulletin au format officiel RDC (une page).
    """
    from reportlab.lib.enums import TA_CENTER
    from reportlab.lib.styles import ParagraphStyle

    buffer = BytesIO()
    margin_pt = 0.4 * inch

    def draw_border(canvas, doc):
        """Encadrement : bordure noire épaisse autour du bulletin."""
        canvas.saveState()
        canvas.setStrokeColor(colors.black)
        canvas.setLineWidth(1.5)
        w, h = doc.pagesize
        m = margin_pt
        canvas.rect(m, m, w - 2 * m, h - 2 * m)
        canvas.restoreState()

    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=margin_pt,
        rightMargin=margin_pt,
        topMargin=margin_pt,
        bottomMargin=margin_pt,
        onFirstPage=draw_border,
        onLaterPage=draw_border,
    )
    styles = getSampleStyleSheet()
    style_title_main = ParagraphStyle(
        "title_main",
        parent=styles["Normal"],
        alignment=TA_CENTER,
        fontSize=10,
        leading=11,
        fontName="Helvetica-Bold",
        textColor=colors.black,
        spaceBefore=0,
        spaceAfter=1,
    )
    style_title_sub = ParagraphStyle(
        "title_sub",
        parent=styles["Normal"],
        alignment=TA_CENTER,
        fontSize=8,
        leading=9,
        fontName="Helvetica-Bold",
        textColor=colors.black,
        spaceBefore=0,
        spaceAfter=0,
    )
    style_small = ParagraphStyle(
        "small",
        parent=styles["Normal"],
        fontSize=7,
    )
    story = []

    student = report_card.student
    user = student.user
    school = getattr(user, "school", None)

    school_name = getattr(school, "name", "-") if school else "-"
    province = getattr(school, "province", "-") if school else "-"
    city = getattr(school, "city", "-") if school else "-"
    commune = getattr(school, "commune", "-") if school else "-"
    code_ecole = getattr(school, "code", "-") if school else "-"

    # HEADER : drapeau coin gauche, titre centré, armoiries coin droit (comme 2ème capture)
    logo_w, logo_h = 1.15 * inch, 0.85 * inch
    left_logo_path = _bulletin_logo_path("Drapeau.png") or _bulletin_logo_path("rdc_flag.png")
    right_logo_path = _bulletin_logo_path("Armoirie.png") or _bulletin_logo_path("rdc_arms.png")

    def _logo_or_spacer(path):
        if path:
            try:
                return Image(path, width=logo_w, height=logo_h)
            except Exception:
                pass
        return Spacer(logo_w, logo_h)

    logo_left = _logo_or_spacer(left_logo_path)
    logo_right = _logo_or_spacer(right_logo_path)

    title_block = [
        Paragraph("<b>REPUBLIQUE DEMOCRATIQUE DU CONGO</b>", style_title_main),
        Paragraph("<b>MINISTERE DE L'ENSEIGNEMENT PRIMAIRE, SECONDAIRE ET PROFESSIONNEL</b>", style_title_sub),
    ]

    header_table = Table(
        [[logo_left, title_block, logo_right]],
        colWidths=[logo_w, None, logo_w],
    )
    light_blue = colors.HexColor("#dce8f5")
    header_table.setStyle(TableStyle([
        ("ALIGN", (0, 0), (0, 0), "LEFT"),
        ("ALIGN", (1, 0), (1, 0), "CENTER"),
        ("ALIGN", (2, 0), (2, 0), "RIGHT"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ("BACKGROUND", (0, 0), (-1, -1), light_blue),
    ]))
    story.append(header_table)

    # Ligne de séparation épaisse sous l'en-tête
    sep = Table([[""]], colWidths=[7 * inch])
    sep.setStyle(TableStyle([
        ("LINEABOVE", (0, 0), (-1, -1), 2, colors.black),
        ("TOPPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]))
    story.append(sep)
    story.append(Spacer(1, 4))

    # INFOS ELEVE
    full_name = user.get_full_name()
    classe = student.school_class.name if student.school_class else "-"
    dob = getattr(user, "date_of_birth", None)
    dob_str = dob.strftime("%d/%m/%Y") if dob else "-"
    sex_label = "M" if getattr(student, "gender", None) == "M" else "F" if getattr(student, "gender", None) == "F" else "-"
    place_of_birth = getattr(student, "place_of_birth", None) or "-"

    info_data = [
        ["N° ID.", "", "", "", "", ""],
        ["PROVINCE EDUCATIONNELLE :", province, "", "", "", ""],
        ["VILLE :", city, "ELEVE :", full_name, "SEXE :", sex_label],
        ["COMMUNE /TER :", commune, "NE(E) A :", place_of_birth, "LE :", dob_str],
        ["ECOLE :", school_name, "CLASSE :", classe, "", ""],
        ["CODE :", code_ecole, "N° PERM. :", student.student_id or "-", "", ""],
    ]
    info_table = Table(
        info_data,
        colWidths=[1.2 * inch, 2.8 * inch, 0.9 * inch, 2.0 * inch, 0.6 * inch, 1.1 * inch],
    )
    info_table.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.25, colors.black),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("FONTSIZE", (0, 0), (-1, -1), 8),
    ]))
    story.append(info_table)
    story.append(Spacer(1, 6))
    story.append(
        Paragraph(
            f"<b>BULLETIN DE LA {classe} &nbsp;&nbsp;&nbsp; ANNÉE SCOLAIRE : {report_card.academic_year}</b>",
            styles["Normal"],
        )
    )
    story.append(Spacer(1, 6))

    # TABLEAU NOTES
    header = [
        [
            "BRANCHES",
            "PREMIER SEMESTRE", "", "", "",
            "SECOND SEMESTRE", "", "", "",
            "TOTAL GENERAL",
            "EXAMEN DE REPECHAGE",
        ],
        [
            "",
            "MAX.", "TRAVAUX JOURNAL.", "MAX. EXAM.", "TOTAL",
            "MAX.", "TRAVAUX JOURNAL.", "MAX. EXAM.", "TOTAL",
            "",
            "%",
        ],
        [
            "",
            "1ère P.", "2ème P.", "EXAM.", "TOT. S1",
            "3ème P.", "4ème P.", "EXAM.", "TOT. S2",
            "T.G.",
            "Sign. Prof.",
        ],
    ]
    data = list(header)

    grades = GradeBulletin.objects.filter(
        student=student,
        academic_year=report_card.academic_year,
    ).select_related("subject")

    # Domaine depuis ClassSubject (pas sur Subject)
    resolved_class = student.school_class
    cs_by_subject_id = {}
    if resolved_class:
        for cs in ClassSubject.objects.filter(school_class=resolved_class).select_related("subject"):
            cs_by_subject_id[cs.subject_id] = cs

    domains = {}
    for g in grades:
        if not g.subject:
            continue
        cs = cs_by_subject_id.get(g.subject_id)
        domain = (getattr(cs, "domain", None) or "AUTRES").strip().upper() or "AUTRES"
        domains.setdefault(domain, []).append(g)

    def val(v):
        if v is None:
            return "-"
        return str(Decimal(str(v)).quantize(Decimal("0.01")))

    for domain, items in domains.items():
        data.append([domain] + [""] * 10)
        for g in items:
            data.append([
                g.subject.name,
                val(g.s1_p1),
                val(g.s1_p2),
                val(g.s1_exam),
                val(g.total_s1),
                val(g.s2_p3),
                val(g.s2_p4),
                val(g.s2_exam),
                val(g.total_s2),
                val(g.total_general),
                val(g.reclamation_score),
            ])

    table = Table(
        data,
        colWidths=[
            2.0 * inch,
            0.55 * inch, 0.55 * inch, 0.55 * inch, 0.55 * inch,
            0.55 * inch, 0.55 * inch, 0.55 * inch, 0.55 * inch,
            0.65 * inch,
            0.65 * inch,
        ],
    )
    table.setStyle(TableStyle([
        ("SPAN", (0, 0), (0, 2)),
        ("SPAN", (1, 0), (4, 0)),
        ("SPAN", (5, 0), (8, 0)),
        ("SPAN", (9, 0), (9, 1)),
        ("GRID", (0, 0), (-1, -1), 0.25, colors.black),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("FONTNAME", (0, 0), (-1, 2), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 7),
        ("BACKGROUND", (0, 0), (-1, 2), colors.lightgrey),
    ]))
    story.append(table)
    story.append(Spacer(1, 6))

    # FOOTER TABLE
    pct = ""
    if report_card.average_score is not None:
        pct = f"{float(report_card.average_score) * 5:.2f} %"
    place = f"{report_card.rank or ''}/{report_card.total_students or ''}"

    footer = [
        ["MAXIMA GENERAUX"] + [""] * 11,
        ["TOTAUX"] + [""] * 11,
        ["POURCENTAGE", pct] + [""] * 10,
        ["PLACE / NBRE D'ELEVES", place] + [""] * 10,
        ["APPLICATION", report_card.application or ""] + [""] * 10,
        ["CONDUITE", report_card.conduite or ""] + [""] * 10,
        ["SIGNATURE"] + [""] * 11,
    ]
    footer_table = Table(
        footer,
        colWidths=[1.6 * inch] + [0.35 * inch] * 11,
    )
    footer_table.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.25, colors.black),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("FONTSIZE", (0, 0), (-1, -1), 7),
    ]))
    story.append(footer_table)
    story.append(Spacer(1, 6))

    # DECISIONS
    story.append(Paragraph(
        "- L'élève ne pourra passer dans la classe supérieure s'il n'a subi avec succès un examen de repêchage (1)",
        style_small,
    ))
    story.append(Paragraph("- L'élève passe dans la classe supérieure (1)", style_small))
    story.append(Paragraph("- L'élève double la classe (1)", style_small))
    story.append(Spacer(1, 10))

    sig_table = Table([
        ["Signature de l'élève", "Sceau de l'Ecole", f"Fait à {city}, le ....../....../20....", "Chef d'Etablissement"],
    ], colWidths=[2 * inch, 2 * inch, 3 * inch, 2 * inch])
    sig_table.setStyle(TableStyle([
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("FONTSIZE", (0, 0), (-1, -1), 7),
    ]))
    story.append(sig_table)
    story.append(Spacer(1, 4))
    story.append(Paragraph("(1) Biffer la mention inutile.", style_small))
    story.append(Paragraph("Note importante : Le bulletin est sans valeur s'il est raturé ou surchargé.", style_small))
    story.append(Paragraph(
        "Interdiction formelle de reproduire ce bulletin sous peine des sanctions prévues par la loi.",
        style_small,
    ))

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
