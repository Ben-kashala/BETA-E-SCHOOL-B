"""
Utility functions for academics (PDF generation, class ranking, etc.)
"""
import os
import re
from datetime import date
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


def _d0(v):
    if v is None or v == "":
        return Decimal("0")
    try:
        return Decimal(str(v))
    except Exception:
        return Decimal("0")


def _fmt_footer_num(d):
    if d is None:
        return ""
    try:
        return str(Decimal(str(d)).quantize(Decimal("0.01")))
    except Exception:
        return ""


def _build_rdc_footer_column_series(
    student,
    resolved_class,
    academic_year,
    subject_ids,
    max_p_by_subject,
):
    """
    Séries MAXIMA / TOTAUX / POURCENTAGE / PLACE pour les 18 colonnes du tableau (S1, S2, T.G., repêchage),
    alignées sur le bulletin officiel RDC. Retourne (maxima, totaux, pct, place) — listes de 18 chaînes.
    """
    empty18 = [""] * 18
    if not resolved_class or not subject_ids:
        return empty18, empty18, empty18, empty18

    ac_year = (academic_year or "").strip()
    enrollment_ids = set(
        StudentClassEnrollment.objects.filter(school_class=resolved_class).values_list("student_id", flat=True).distinct()
    )
    bulletin_ids = set(
        GradeBulletin.objects.filter(school_class=resolved_class, academic_year=ac_year).values_list("student_id", flat=True).distinct()
    )
    student_ids = list(enrollment_ids | bulletin_ids)
    if not student_ids:
        return empty18, empty18, empty18, empty18

    bulletins = GradeBulletin.objects.filter(
        student_id__in=student_ids,
        academic_year=ac_year,
        subject_id__in=subject_ids,
    ).filter(Q(school_class=resolved_class) | Q(school_class__isnull=True))

    by_student = {}
    for b in bulletins:
        by_student.setdefault(b.student_id, {})[b.subject_id] = b

    students = Student.objects.filter(id__in=student_ids).select_related("user")
    name_map = {
        s.id: ((s.user.get_full_name() or "").strip() or s.user.username or f"#{s.id}")
        for s in students
        if s.user
    }
    for s in students:
        if s.id not in name_map:
            name_map[s.id] = f"#{s.id}"

    def sums_for(sid):
        """Totaux élève sur les 18 colonnes (indices 0..17), alignés sur make_data_row (S1/S2/T.G.)."""
        row = [Decimal("0")] * 18
        for subj_id in subject_ids:
            mp = int(max_p_by_subject.get(subj_id) or 20)
            max_exam = mp * 2
            tot_s1_max = 4 * mp
            tot_s2_max = 4 * mp
            tot_gen_max = 8 * mp
            row[0] += mp
            row[7] += mp
            g = by_student.get(sid, {}).get(subj_id)
            if g:
                row[1] += _d0(g.s1_p1)
                row[2] += _d0(g.s1_p2)
                row[3] += max_exam
                row[4] += _d0(g.s1_exam)
                row[5] += tot_s1_max
                row[6] += _d0(g.total_s1)
                row[8] += _d0(g.s2_p3)
                row[9] += _d0(g.s2_p4)
                row[10] += max_exam
                row[11] += _d0(g.s2_exam)
                row[12] += tot_s2_max
                row[13] += _d0(g.total_s2)
                row[14] += tot_gen_max
                row[15] += _d0(g.total_general)
                row[16] += _d0(g.reclamation_score)
        return row

    def maxima_row():
        m = [Decimal("0")] * 18
        for subj_id in subject_ids:
            mp = int(max_p_by_subject.get(subj_id) or 20)
            max_exam = mp * 2
            tot_s1_max = 4 * mp
            tot_s2_max = 4 * mp
            tot_gen_max = 8 * mp
            m[0] += mp
            m[1] += mp
            m[2] += mp
            m[3] += max_exam
            m[4] += max_exam
            m[5] += tot_s1_max
            m[6] += tot_s1_max
            m[7] += mp
            m[8] += mp
            m[9] += mp
            m[10] += max_exam
            m[11] += max_exam
            m[12] += tot_s2_max
            m[13] += tot_s2_max
            m[14] += tot_gen_max
            m[15] += tot_gen_max
        return m

    maxima = maxima_row()
    all_sums = {sid: sums_for(sid) for sid in student_ids}
    if student.id not in all_sums:
        all_sums[student.id] = sums_for(student.id)
        if student.id not in student_ids:
            student_ids.append(student.id)
            u = getattr(student, "user", None)
            name_map.setdefault(
                student.id,
                ((u.get_full_name() or "").strip() or getattr(u, "username", None) or f"#{student.id}") if u else f"#{student.id}",
            )
    tot = all_sums[student.id]

    # Colonnes « total max » seules (pas de % sur la cellule) ; col. MAX (0) = 100 % ; repêchage
    skip_pct_place = {0, 5, 12, 14, 16, 17}

    def pct_cell(i):
        if i in skip_pct_place:
            return ""
        if i == 6:
            denom, num = maxima[5], tot[6]
        elif i == 13:
            denom, num = maxima[12], tot[13]
        elif i == 15:
            denom, num = maxima[14], tot[15]
        else:
            denom, num = maxima[i], tot[i]
        if denom <= 0:
            return ""
        p = (num / denom) * Decimal("100")
        return f"{float(p):.2f} %"

    def rank_for_column(col_idx):
        """Classement sur la colonne `col_idx` (ex-aequo = même rang)."""
        skip_rank = {0, 3, 5, 7, 10, 12, 14, 16, 17}
        if col_idx in skip_rank:
            return "", ""
        totals = [(sid, all_sums[sid][col_idx]) for sid in student_ids]
        totals.sort(key=lambda x: (-x[1], name_map.get(x[0], "")))
        n = len(student_ids)
        current_rank = 1
        rank_lookup = {}
        for i, (sid, val) in enumerate(totals):
            if i > 0 and val != totals[i - 1][1]:
                current_rank = i + 1
            rank_lookup[sid] = current_rank
        rank = rank_lookup.get(student.id)
        if rank is None:
            return "", ""
        return str(rank), str(n)

    _footer_hatch_idx = {0, 3, 5, 7, 10, 12, 14, 16, 17}
    maxima_str = [_fmt_footer_num(maxima[i]) if i not in _footer_hatch_idx else "" for i in range(18)]
    tot_str = []
    for i in range(18):
        if i in _footer_hatch_idx:
            tot_str.append("")
        else:
            tot_str.append(_fmt_footer_num(tot[i]))
    pct_str = [pct_cell(i) for i in range(18)]
    place_str = []
    for i in range(18):
        r, n = rank_for_column(i)
        place_str.append(f"{r} / {n}" if r and n else "")

    return maxima_str, tot_str, pct_str, place_str


def _parse_academic_year_span(academic_year_str):
    """Retourne (année_début, année_fin) depuis une chaîne du type « 2025-2026 » ou « 2025 - 2026 »."""
    if not academic_year_str or not str(academic_year_str).strip():
        return None
    m = re.search(r"(\d{4})\s*[-/]\s*(\d{4})", str(academic_year_str).strip())
    if not m:
        return None
    return int(m.group(1)), int(m.group(2))


def _bulletin_fait_date_str(academic_year_str):
    """
    Date après « le » sur le bulletin RDC : date du jour si l'année scolaire du bulletin
    est « en cours » (entre septembre de l'année de début et fin juillet de l'année de fin),
    sinon 02/07/<année de fin> (ex. 2025-2026 → 02/07/2026).
    """
    today = date.today()
    parsed = _parse_academic_year_span(academic_year_str)
    if not parsed:
        return today.strftime("%d/%m/%Y")
    start_year, end_year = parsed
    period_start = date(start_year, 9, 1)
    period_end = date(end_year, 7, 31)
    if period_start <= today <= period_end:
        return today.strftime("%d/%m/%Y")
    return f"02/07/{end_year}"


def generate_bulletin_rdc_pdf(report_card):
    """
    Génère le bulletin au format officiel RDC (une page), identique au modèle
    IGE/P.S./012 (1ère Année des Humanités Scientifiques).
    """
    from reportlab.lib.enums import TA_CENTER
    from reportlab.lib.styles import ParagraphStyle

    buffer = BytesIO()
    margin_pt = 0.08 * inch
    watermark_path = _bulletin_logo_path("Armoirie.png") or _bulletin_logo_path("rdc_arms.png")

    def _make_border_canvas(margin):
        class BorderCanvas(canvas.Canvas):
            def showPage(self):
                self.saveState()
                try:
                    w, h = self._pagesize
                    self.setFillColor(colors.HexColor("#eef6ff"))
                    self.rect(0, 0, w, h, stroke=0, fill=1)
                    if watermark_path and os.path.isfile(watermark_path):
                        try:
                            self.setFillAlpha(0.08)
                            size = 3.2 * inch
                            self.drawImage(
                                watermark_path,
                                (w - size) / 2,
                                (h - size) / 2 - 0.5 * inch,
                                width=size,
                                height=size,
                                preserveAspectRatio=True,
                            )
                        except Exception:
                            pass
                        self.setFillAlpha(1)
                    self.setStrokeColor(colors.black)
                    self.setLineWidth(1.2)
                    m = margin
                    self.rect(m, m, w - 2 * m, h - 2 * m)
                finally:
                    self.restoreState()
                super().showPage()
        return BorderCanvas

    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=margin_pt,
        rightMargin=margin_pt,
        topMargin=margin_pt,
        bottomMargin=margin_pt,
        canvasmaker=_make_border_canvas(margin_pt),
    )
    full_w = doc.width

    def _fit_widths(widths):
        total = sum(widths) or 1
        factor = full_w / total
        return [w * factor for w in widths]
    styles = getSampleStyleSheet()
    # En-tête : texte en blanc sur fond sombre (ou noir pour impression)
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
        fontSize=6.4,
        leading=6.6,
        spaceBefore=0,
        spaceAfter=0,
    )
    story = []

    student = report_card.student
    user = student.user
    school = getattr(user, "school", None)

    school_name = getattr(school, "name", "") if school else ""
    province = getattr(school, "province", "") if school else ""
    city = getattr(school, "city", "") if school else ""
    commune = getattr(school, "commune", "") if school else ""
    code_ecole = getattr(school, "code", "") if school else ""

    # ----- EN-TÊTE : Drapeau gauche, 3 lignes centrées, Armoiries droite -----
    logo_w, logo_h = 0.95 * inch, 0.64 * inch
    left_logo_path = (
        _bulletin_logo_path("Drapeau.png")
        or _bulletin_logo_path("drapeau_RDC.png")
        or _bulletin_logo_path("rdc_flag.png")
    )
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
        Paragraph("<b>MINISTERE DE L'EDUCATION NATIONALE</b>", style_title_sub),
        Paragraph("<b>ET NOUVELLE CITOYENNETE</b>", style_title_sub),
    ]
    header_table = Table(
        [[logo_left, title_block, logo_right]],
        colWidths=[logo_w, None, logo_w],
    )
    header_table.setStyle(TableStyle([
        ("ALIGN", (0, 0), (0, 0), "LEFT"),
        ("ALIGN", (1, 0), (1, 0), "CENTER"),
        ("ALIGN", (2, 0), (2, 0), "RIGHT"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING", (0, 0), (-1, -1), 2),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#dce8f5")),
        ("BOX", (0, 0), (-1, -1), 0.5, colors.black),
    ]))
    story.append(header_table)
    # Ligne horizontale fine noire sous l'en-tête (pleine largeur)
    line_table = Table([[""]], colWidths=[full_w])
    line_table.setStyle(TableStyle([
        ("LINEABOVE", (0, 0), (-1, -1), 1, colors.black),
        ("TOPPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
    ]))
    story.append(line_table)
    story.append(Spacer(1, 0))

    # ----- BLOC INFOS : structure visuelle identique au bulletin officiel -----
    full_name = user.get_full_name() or ""
    classe = student.school_class.name if student.school_class else "1ère ANNEE DES HUMANITES SCIENTIFIQUES"
    dob = getattr(user, "date_of_birth", None) or getattr(student, "date_of_birth", None)
    gender_raw = getattr(student, "gender", None) or None
    place_of_birth = getattr(student, "place_of_birth", None) or getattr(user, "place_of_birth", None) or ""
    if not dob or not place_of_birth or not gender_raw:
        try:
            from apps.enrollment.models import EnrollmentApplication

            app = (
                EnrollmentApplication.objects.filter(generated_student_id=student.student_id)
                .order_by("-created_at")
                .first()
            )
            if app:
                if not dob:
                    dob = getattr(app, "date_of_birth", None)
                if not place_of_birth:
                    place_of_birth = getattr(app, "place_of_birth", "") or ""
                if not gender_raw:
                    gender_raw = getattr(app, "gender", None) or None
        except Exception:
            # Le bulletin continue même si le module enrollment n'est pas disponible.
            pass
    g = (gender_raw or "").strip().upper() if gender_raw else ""
    if g == "M":
        sex_label = "M"
    elif g == "F":
        sex_label = "F"
    else:
        sex_label = ""
    dob_str = dob.strftime("%d/%m/%Y") if dob else "....../....../.........."
    n_perm = student.student_id or ""

    def _dots(value, total=42):
        """Texte seul si renseigné ; sinon ligne de points (placeholder) sur `total` caractères."""
        txt = (value or "").strip()
        if txt:
            return txt
        return "." * total

    id_cells = ["N° ID."] + [""] * 22
    id_label_w = 0.55 * inch
    id_cell_w = (full_w - id_label_w) / 22
    id_table = Table([id_cells], colWidths=[id_label_w] + [id_cell_w] * 22)
    id_table.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.25, colors.black),
        ("FONTSIZE", (0, 0), (-1, -1), 6.2),
        ("TOPPADDING", (0, 0), (-1, -1), 1),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
        ("FONTNAME", (0, 0), (0, 0), "Helvetica-Bold"),
    ]))
    story.append(id_table)

    province_table = Table(
        [["PROVINCE EDUCATIONNELLE :", _dots(province, 72)]],
        colWidths=[2.35 * inch, full_w - 2.35 * inch],
    )
    province_table.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.25, colors.black),
        ("FONTSIZE", (0, 0), (-1, -1), 6.8),
        ("FONTNAME", (0, 0), (0, 0), "Helvetica-Bold"),
        ("LEFTPADDING", (0, 0), (-1, -1), 2),
        ("TOPPADDING", (0, 0), (-1, -1), 1),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
    ]))
    story.append(province_table)

    left_label_w = 1.15 * inch
    left_value_w = 2.6 * inch
    right_label_w = 1.35 * inch
    right_value_w = full_w - (left_label_w + left_value_w + right_label_w)

    code_boxes_count = 9
    perm_boxes_count = 13
    code_boxes = Table([[""] * code_boxes_count], colWidths=[left_value_w / code_boxes_count] * code_boxes_count)
    code_boxes.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.25, colors.black),
        ("TOPPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))
    perm_boxes = Table([[""] * perm_boxes_count], colWidths=[right_value_w / perm_boxes_count] * perm_boxes_count)
    perm_boxes.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.25, colors.black),
        ("TOPPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))

    eleve_line = _dots(full_name, 30) + " SEXE : " + _dots(sex_label, 6)
    naissance_line = _dots(place_of_birth, 20) + " LE " + (dob_str or "")
    info_data = [
        ["VILLE :", _dots(city, 46), "ELEVE :", eleve_line],
        ["COMMUNE /TER (1) :", _dots(commune, 40), "NE (E) A :", naissance_line],
        ["ECOLE :", _dots(school_name, 42), "CLASSE :", _dots(classe, 30)],
        ["CODE :", code_boxes, "N° PERM.", perm_boxes],
    ]
    info_table = Table(
        info_data,
        colWidths=[left_label_w, left_value_w, right_label_w, right_value_w],
    )
    info_table.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.25, colors.black),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("FONTSIZE", (0, 0), (-1, -1), 6.1),
        ("FONTNAME", (0, 0), (0, -1), "Helvetica-Bold"),
        ("FONTNAME", (2, 0), (2, -1), "Helvetica-Bold"),
        ("LEFTPADDING", (0, 0), (-1, -1), 1.5),
        ("RIGHTPADDING", (0, 0), (-1, -1), 1.5),
        ("TOPPADDING", (0, 0), (-1, -1), 1),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
    ]))
    story.append(info_table)
    story.append(Spacer(1, 0))

    # ----- TITRE : BULLETIN DE LA ... ANNEE SCOLAIRE ... (encadré bordure noire fine) -----
    titre_bulletin = f"BULLETIN DE LA 1ère ANNEE DES HUMANITES SCIENTIFIQUES    ANNEE SCOLAIRE {report_card.academic_year or '2024 - 2025'}"
    style_titre = ParagraphStyle(
        "bulletin_titre",
        parent=styles["Normal"],
        alignment=TA_CENTER,
        fontSize=8,
        leading=8.6,
        fontName="Helvetica-Bold",
        spaceBefore=2,
        spaceAfter=2,
    )
    titre_para = Paragraph(f"<b>{titre_bulletin}</b>", style_titre)
    titre_wrapper = Table([[titre_para]], colWidths=[full_w])
    titre_wrapper.setStyle(TableStyle([
        ("BOX", (0, 0), (-1, -1), 0.5, colors.black),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("BACKGROUND", (0, 0), (-1, -1), colors.white),
    ]))
    story.append(titre_wrapper)
    story.append(Spacer(1, 0))

    # ----- TABLEAU DES NOTES (structure officielle : 19 colonnes, 3 niveaux d'en-têtes) -----
    # Colonnes réelles:
    # BRANCHES (1) |
    # S1 (7): MAX | 1ère P. | 2e P. | MAX.EXAM (2 colonnes) | TOTAL (2 colonnes) |
    # S2 (7): MAX | 3e P. | 4e P. | MAX.EXAM (2 colonnes) | TOTAL (2 colonnes) |
    # TOTAL GENERAL (2 colonnes) |
    # EXAMEN DE REPECHAGE (2 colonnes: %, Sign. Prof.)
    HEADER_DARK = colors.HexColor("#dce8f5")
    HEADER_LIGHT = colors.HexColor("#f3f7fd")
    SOUS_TOTAL_BG = None

    num_cols = 19
    header_row1 = [
        "BRANCHES",
        "PREMIER SEMESTRE", "", "", "", "", "", "",
        "SECOND SEMESTRE", "", "", "", "", "", "",
        "TOTAL\nGENERAL", "",
        "EXAMEN DE REPECHAGE", "",
    ]
    header_row2 = [
        "",
        "MAX.", "TRAV. JOURNAL.", "", "MAX. EXAM.", "", "TOTAL", "",
        "MAX.", "TRAV. JOURNAL.", "", "MAX. EXAM.", "", "TOTAL", "",
        "", "",
        "%", "Sign. Prof.",
    ]
    header_row3 = [
        "",
        "", "1ère P.", "2e P.", "MAX", "EXAM", "MAX", "TOT",
        "", "3e P.", "4e P.", "MAX", "EXAM", "MAX", "TOT",
        "", "", "", "",
    ]
    header_row1 = header_row1[:num_cols]
    header_row2 = header_row2[:num_cols]
    header_row3 = header_row3[:num_cols]

    grades = GradeBulletin.objects.filter(
        student=student,
        academic_year=report_card.academic_year,
    ).select_related("subject")
    resolved_class = student.school_class
    cs_by_subject_id = {}
    if resolved_class:
        for cs in ClassSubject.objects.filter(school_class=resolved_class).select_related("subject"):
            cs_by_subject_id[cs.subject_id] = cs

    def val(v):
        if v is None:
            return ""
        return str(Decimal(str(v)).quantize(Decimal("0.01")))

    # Données dynamiques : matières/domaines/sous-domaines/maxima provenant de la plateforme
    class_subjects = []
    if resolved_class:
        class_subjects = list(
            ClassSubject.objects.filter(school_class=resolved_class)
            .select_related("subject")
            .order_by("domain", "subject__name")
        )

    grades_by_subject_id = {g.subject_id: g for g in grades if g.subject_id}

    entries = []
    for cs in class_subjects:
        subject = getattr(cs, "subject", None)
        if not subject:
            continue
        domain = ((getattr(cs, "domain", None) or "AUTRES").strip() or "AUTRES").upper()
        sub_domain = (
            getattr(cs, "sub_domain", None)
            or getattr(cs, "subdomain", None)
            or getattr(cs, "subcategory", None)
            or None
        )
        if isinstance(sub_domain, str):
            sub_domain = sub_domain.strip() or None
        entries.append(
            {
                "subject_name": subject.name,
                "subject_id": subject.id,
                "max_p": int(getattr(cs, "period_max", None) or getattr(subject, "period_max", 20) or 20),
                "domain": domain,
                "sub_domain": sub_domain,
                "grade": grades_by_subject_id.get(subject.id),
            }
        )

    # Repli : bulletins existants sans ClassSubject (anciennes données) -> domaine AUTRES
    for g in grades:
        if g.subject_id in {e["subject_id"] for e in entries}:
            continue
        subj = g.subject
        if not subj:
            continue
        entries.append(
            {
                "subject_name": subj.name,
                "subject_id": subj.id,
                "max_p": int(getattr(subj, "period_max", 20) or 20),
                "domain": "AUTRES",
                "sub_domain": None,
                "grade": g,
            }
        )

    def make_data_row(label, max_p, g_ctx):
        """
        Colonnes S1 (1–7) : MAX | 1ère P | 2e P | MAX EXAM | note exam | TOTAL max S1 | TOTAL obtenu S1
        Colonnes S2 (8–14) : idem semestre 2.
        Col. 6 TOTAL max = 4×MAX (col1) ; col. 7 = s1_p1+s1_p2+s1_exam (total_s1).
        Col. 15–16 : TOTAL G max (8×MAX) | total général obtenu.
        """
        if g_ctx:
            g, cs = g_ctx
            max_p = max_p or (getattr(cs, "period_max", None) or 20)
            max_exam = max_p * 2
            tot_s1_max = 4 * max_p
            tot_s2_max = 4 * max_p
            tot_gen_max = 8 * max_p
            return [
                label,
                str(int(max_p)),
                val(g.s1_p1),
                val(g.s1_p2),
                str(int(max_exam)),
                val(g.s1_exam),
                str(int(tot_s1_max)),
                val(g.total_s1),
                str(int(max_p)),
                val(g.s2_p3),
                val(g.s2_p4),
                str(int(max_exam)),
                val(g.s2_exam),
                str(int(tot_s2_max)),
                val(g.total_s2),
                str(int(tot_gen_max)),
                val(g.total_general),
                val(g.reclamation_score) or "", "",
            ]
        if max_p is not None:
            max_exam = max_p * 2
            tot_s1_max = 4 * max_p
            tot_s2_max = 4 * max_p
            tot_gen_max = 8 * max_p
            return [
                label,
                str(int(max_p)), "", "", str(int(max_exam)), "", str(int(tot_s1_max)), "",
                str(int(max_p)), "", "", str(int(max_exam)), "", str(int(tot_s2_max)), "",
                str(int(tot_gen_max)), "", "", "",
            ]
        return [label] + [""] * (num_cols - 1)

    data_rows = [header_row1, header_row2, header_row3]

    # Ordre stable des domaines selon les données de classe
    domain_order = []
    domain_groups = {}
    for e in entries:
        d = e["domain"]
        if d not in domain_groups:
            domain_groups[d] = []
            domain_order.append(d)
        domain_groups[d].append(e)

    for domain in domain_order:
        domain_items = domain_groups[domain]
        data_rows.append([domain] + [""] * (num_cols - 1))

        # Sous-domaines dynamiques (si non fournis, toutes les matières du domaine vont dans un seul groupe)
        sub_order = []
        sub_groups = {}
        for e in domain_items:
            s = e["sub_domain"] or ""
            if s not in sub_groups:
                sub_groups[s] = []
                sub_order.append(s)
            sub_groups[s].append(e)

        for sub in sub_order:
            items = sub_groups[sub]
            if sub:
                data_rows.append([sub] + [""] * (num_cols - 1))

            subtotal_max = 0
            sum_s1_p1 = sum_s1_p2 = sum_s1_exam = sum_s2_p3 = sum_s2_p4 = sum_s2_exam = Decimal(0)
            sum_total_s1 = sum_total_s2 = sum_tg = Decimal(0)
            for e in items:
                subtotal_max += int(e["max_p"] or 0)
                g_ctx = (e["grade"], cs_by_subject_id.get(e["subject_id"])) if e["grade"] else None
                row = make_data_row(e["subject_name"], e["max_p"], g_ctx)
                row = row[:num_cols]
                while len(row) < num_cols:
                    row.append("")
                data_rows.append(row[:num_cols])
                g = e.get("grade")
                if g:
                    sum_s1_p1 += _d0(g.s1_p1)
                    sum_s1_p2 += _d0(g.s1_p2)
                    sum_s1_exam += _d0(g.s1_exam)
                    sum_s2_p3 += _d0(g.s2_p3)
                    sum_s2_p4 += _d0(g.s2_p4)
                    sum_s2_exam += _d0(g.s2_exam)
                    sum_total_s1 += _d0(g.total_s1)
                    sum_total_s2 += _d0(g.total_s2)
                    sum_tg += _d0(g.total_general)

            emax = subtotal_max * 2
            tsem = subtotal_max * 4
            tgen = subtotal_max * 8
            subtotal_row = [
                "Sous - Total",
                str(subtotal_max),
                val(sum_s1_p1),
                val(sum_s1_p2),
                str(emax),
                val(sum_s1_exam),
                str(tsem),
                val(sum_total_s1),
                str(subtotal_max),
                val(sum_s2_p3),
                val(sum_s2_p4),
                str(emax),
                val(sum_s2_exam),
                str(tsem),
                val(sum_total_s2),
                str(tgen),
                val(sum_tg),
                "", "",
            ]
            data_rows.append(subtotal_row[:num_cols])

    col_widths = _fit_widths([
        1.48 * inch,  # BRANCHES
        0.30 * inch, 0.33 * inch, 0.33 * inch, 0.31 * inch, 0.31 * inch, 0.31 * inch, 0.31 * inch,  # S1 (7)
        0.30 * inch, 0.33 * inch, 0.33 * inch, 0.31 * inch, 0.31 * inch, 0.31 * inch, 0.31 * inch,  # S2 (7)
        0.33 * inch, 0.33 * inch,  # TOTAL GENERAL (2)
        0.32 * inch, 0.38 * inch,  # REPECHAGE (2)
    ])
    row_heights = [0.2 * inch, 0.2 * inch, 0.16 * inch] + [None] * (len(data_rows) - 3)
    table = Table(data_rows, colWidths=col_widths[:num_cols], rowHeights=row_heights)
    tbl_style = [
        ("SPAN", (0, 0), (0, 2)),
        ("SPAN", (1, 0), (7, 0)),
        ("SPAN", (8, 0), (14, 0)),
        ("SPAN", (15, 0), (16, 1)),
        ("SPAN", (17, 0), (18, 0)),
        ("SPAN", (2, 1), (3, 1)),
        ("SPAN", (4, 1), (5, 1)),
        ("SPAN", (6, 1), (7, 1)),
        ("SPAN", (9, 1), (10, 1)),
        ("SPAN", (11, 1), (12, 1)),
        ("SPAN", (13, 1), (14, 1)),
        ("SPAN", (15, 2), (16, 2)),
        ("GRID", (0, 0), (-1, -1), 0.35, colors.black),
        ("LINEBEFORE", (17, 0), (17, -1), 1.0, colors.black),
        ("ALIGN", (0, 0), (0, -1), "LEFT"),
        ("ALIGN", (1, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("FONTNAME", (0, 0), (-1, 2), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 6.0),
        ("LEFTPADDING", (0, 0), (-1, -1), 1),
        ("RIGHTPADDING", (0, 0), (-1, -1), 1),
        ("TOPPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
        ("BACKGROUND", (0, 0), (-1, 2), colors.white),
        ("TEXTCOLOR", (0, 0), (-1, 2), colors.black),
    ]
    # Lignes "Sous - Total" en gras (sans fond noir sur l'examen de repêchage)
    for r in range(3, len(data_rows)):
        if len(data_rows[r]) and data_rows[r][0] == "Sous - Total":
            tbl_style.append(("FONTNAME", (0, r), (-1, r), "Helvetica-Bold"))
    # Lignes domaine / sous-domaine en bandeau bleu ; colonnes repêchage (17–18) en noir comme le modèle
    for r in range(3, len(data_rows)):
        cell0 = (data_rows[r][0] if data_rows[r] else "").strip()
        if cell0 and cell0 != "Sous - Total" and (
            cell0.startswith("DOMAINE") or cell0.startswith("Sous-domaine")
        ):
            # Domaine / Sous-domaine : fusion 0–16 pour le libellé ; 17–18 restent des cellules (fond noir repêchage)
            tbl_style.append(("SPAN", (0, r), (16, r)))
            tbl_style.append(("ALIGN", (0, r), (16, r), "CENTER"))
            tbl_style.append(("BACKGROUND", (0, r), (16, r), HEADER_DARK))
            tbl_style.append(("TEXTCOLOR", (0, r), (16, r), colors.black))
            tbl_style.append(("FONTNAME", (0, r), (-1, r), "Helvetica-Bold"))
            tbl_style.append(("LINEABOVE", (0, r), (-1, r), 0.8, colors.lightgrey))
            tbl_style.append(("BACKGROUND", (17, r), (18, r), colors.black))
            tbl_style.append(("TEXTCOLOR", (17, r), (18, r), colors.white))
    table.setStyle(TableStyle(tbl_style))
    story.append(table)
    story.append(Spacer(1, 0))

    # ----- SECTION RÉSUMÉ : même grille 19 col. que le tableau des notes ; encadré PASSE/DOUBLE fusionné
    # sur les 2 dernières colonnes (examen repêchage), lignes TOTAUX → SIGNATURE (6 lignes).
    max_p_by_subject = {e["subject_id"]: e["max_p"] for e in entries}
    if not max_p_by_subject:
        for g in grades:
            if g.subject_id and g.subject_id not in max_p_by_subject:
                max_p_by_subject[g.subject_id] = int(getattr(g.subject, "period_max", 20) or 20)
    subject_ids_footer = list(max_p_by_subject.keys())
    _, ttot, ppct, pplace = _build_rdc_footer_column_series(
        student, resolved_class, report_card.academic_year, subject_ids_footer, max_p_by_subject
    )
    appli = str(report_card.application) if report_card.application is not None else ""
    conduite = str(report_card.conduite) if report_card.conduite is not None else ""

    footer_col_widths = list(col_widths[:num_cols])

    # Fond gris noir-gris (sans traits) : colonnes réservées vides ; pas sur SIGNATURE ni zone PASSE/DOUBLE
    _fh_rows = {1, 2, 3, 4, 5}
    _fh_cols = {1, 4, 6, 8, 11, 13, 15}
    FOOTER_BLACK = colors.HexColor("#000000")
    _footer_row_heights = [12] * 6 + [14]

    def _footer_cell(col_idx, row_idx, text):
        if col_idx in _fh_cols and row_idx in _fh_rows:
            return ""
        return text or ""

    def _footer_16_cells(strings_18, row_idx):
        """Colonnes 1–16 du résumé (indices 0–15 des séries 18) ; repêchage = fusion séparée."""
        return [
            _footer_cell(i + 1, row_idx, strings_18[i] if i < len(strings_18) else "")
            for i in range(16)
        ]

    # Col. 15 hachurée vide : APPLICATION / CONDUITE sur la col. 16 (2e colonne T.G.)
    _app_16 = [""] * 16
    _app_16[15] = appli
    _con_16 = [""] * 16
    _con_16[15] = conduite

    decision_style = ParagraphStyle(
        "footer_decision_block",
        parent=style_small,
        fontSize=7,
        leading=8.5,
        leftIndent=0,
        spaceBefore=0,
        spaceAfter=0,
    )
    decision_text = (
        "- PASSE (1)<br/>"
        "- DOUBLE (1)<br/>"
        "LE..../....../20....<br/>"
        "Chef d'Etablissement<br/>"
        "Sceau de l'Ecole"
    )
    decision_para = Paragraph(decision_text, decision_style)

    # Ligne 0 : MAXIMA vide (pas de calculs) ; lignes 1–6 : 16 col. + fusion (17–18) sur 6 lignes (SPAN)
    footer_summary_data = [
        ["MAXIMA GENERAUX"] + [""] * 18,
        ["TOTAUX"] + _footer_16_cells(ttot, 1) + [decision_para, ""],
        ["POURCENTAGE"] + _footer_16_cells(ppct, 2) + ["", ""],
        ["PLACE / NBRE D'ELEVES"] + _footer_16_cells(pplace, 3) + ["", ""],
        ["APPLICATION"] + [_footer_cell(i + 1, 4, _app_16[i]) for i in range(16)] + ["", ""],
        ["CONDUITE"] + [_footer_cell(i + 1, 5, _con_16[i]) for i in range(16)] + ["", ""],
        ["SIGNATURE"] + [""] * 16 + ["", ""],
    ]
    footer_summary_table = Table(
        footer_summary_data,
        colWidths=footer_col_widths,
        rowHeights=_footer_row_heights,
    )
    footer_tbl_style = [
        ("GRID", (0, 0), (-1, -1), 0.25, colors.black),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("VALIGN", (17, 1), (18, 6), "TOP"),
        ("SPAN", (17, 1), (18, 6)),
        ("FONTSIZE", (0, 0), (-1, -1), 5.8),
        ("FONTNAME", (0, 0), (0, -1), "Helvetica-Bold"),
        ("LEFTPADDING", (0, 0), (0, -1), 2),
        ("RIGHTPADDING", (0, 0), (0, -1), 2),
        ("TOPPADDING", (0, 0), (0, -1), 2),
        ("BOTTOMPADDING", (0, 0), (0, -1), 2),
        ("LEFTPADDING", (1, 0), (-1, -1), 0),
        ("RIGHTPADDING", (1, 0), (-1, -1), 0),
        ("TOPPADDING", (1, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (1, 0), (-1, -1), 0),
        ("LEFTPADDING", (17, 1), (18, 6), 3),
        ("RIGHTPADDING", (17, 1), (18, 6), 3),
        ("TOPPADDING", (17, 1), (18, 6), 3),
        ("ALIGN", (1, 0), (-1, 3), "CENTER"),
        ("LINEBEFORE", (8, 0), (8, -1), 1.6, colors.black),
        ("LINEBEFORE", (15, 0), (15, -1), 1.6, colors.black),
        ("LINEBEFORE", (17, 0), (17, -1), 1.6, colors.black),
    ]
    for _r in _fh_rows:
        for _c in _fh_cols:
            footer_tbl_style.append(("BACKGROUND", (_c, _r), (_c, _r), FOOTER_BLACK))
    # Ligne MAXIMA GENERAUX : même zone repêchage noire que les lignes domaine du tableau des notes
    footer_tbl_style.append(("BACKGROUND", (17, 0), (18, 0), FOOTER_BLACK))
    footer_tbl_style.append(("TEXTCOLOR", (17, 0), (18, 0), colors.white))
    footer_summary_table.setStyle(TableStyle(footer_tbl_style))
    story.append(footer_summary_table)

    # ----- DÉCISIONS ET MENTIONS LÉGALES : bordure gauche/droite/bas (sans trait haut = suite du tableau ci-dessus)
    fait_date_str = _bulletin_fait_date_str(report_card.academic_year)
    school_city_fait = (city or "").strip()
    if not school_city_fait:
        school_city_fait = "……………………………………………………"
    fait_para = Paragraph(
        f"Fait à {school_city_fait}, le {fait_date_str}",
        ParagraphStyle("fait_center", parent=style_small, alignment=1),
    )
    sig_line = Table(
        [[
            Paragraph("Signature de l'élève", style_small),
            Paragraph("Sceau de l'Ecole", ParagraphStyle("seal_center", parent=style_small, alignment=1)),
            fait_para,
        ]],
        colWidths=_fit_widths([2.1 * inch, 1.9 * inch, 3.0 * inch]),
    )
    sig_line.setStyle(TableStyle([
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
        ("VALIGN", (0, 0), (-1, -1), "BOTTOM"),
    ]))
    chef_line = Table(
        [[
            Paragraph("", style_small),
            Paragraph("Chef d'Etablissement,", ParagraphStyle("chef_right", parent=style_small, alignment=2)),
        ]],
        colWidths=_fit_widths([4.9 * inch, 2.1 * inch]),
    )
    chef_line.setStyle(TableStyle([
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))
    interdiction_line = Table(
        [[
            Paragraph("<b><i>Interdiction formelle de reproduire ce bulletin sous peine des sanctions prévues par la loi.</i></b>", style_small),
            Paragraph("<b><i>IGE/P.S./012</i></b>", ParagraphStyle("ige_right", parent=style_small, alignment=2)),
        ]],
        colWidths=_fit_widths([5.85 * inch, 1.15 * inch]),
    )
    interdiction_line.setStyle(TableStyle([
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))
    legal_block_rows = [
        [Paragraph(
            "- L'élève ne pourra passer dans la classe supérieure s'il n'a subi avec succès un examen de repêchage en.......................................................................................(1)",
            style_small,
        )],
        [Paragraph("- L'élève passe dans la classe supérieure (1)", style_small)],
        [Paragraph("- L'élève double la classe (1)", style_small)],
        [Spacer(1, 1)],
        [sig_line],
        [Spacer(1, 0)],
        [Paragraph("(1) Biffer la mention inutile.", style_small)],
        [Paragraph("Note importante : Le bulletin est sans valeur s'il est raturé ou surchargé.", style_small)],
        [chef_line],
        [interdiction_line],
    ]
    legal_block_table = Table(legal_block_rows, colWidths=[full_w])
    legal_block_table.setStyle(TableStyle([
        ("LINEBEFORE", (0, 0), (0, -1), 0.25, colors.black),
        ("LINEAFTER", (0, 0), (0, -1), 0.25, colors.black),
        ("LINEBELOW", (0, -1), (0, -1), 0.25, colors.black),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ]))
    story.append(legal_block_table)

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
