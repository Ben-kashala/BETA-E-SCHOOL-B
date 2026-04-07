"""
Utilities for payment receipt generation
"""
import logging
from html import escape as html_escape
from io import BytesIO
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import cm
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
from reportlab.pdfgen import canvas as pdf_canvas
from django.core.files.base import ContentFile
from django.utils import timezone

logger = logging.getLogger(__name__)


def _rl_para(text):
    """Texte sûr pour ReportLab Paragraph (Helvetica / WinAnsi) + échappement XML."""
    if text is None:
        return ""
    s = str(text)
    # Caractères hors Latin-1 (noms, adresses) provoquent souvent une erreur à doc.build().
    s = s.encode("latin-1", errors="replace").decode("latin-1")
    return html_escape(s, quote=False)


def _cell_para(text, style, bold=False):
    """Cellule tableau : toujours un Paragraph (évite erreurs encodage chaînes brutes + accents)."""
    safe = _rl_para(text)
    inner = f"<b>{safe}</b>" if bold else safe
    return Paragraph(inner, style)


def _build_payment_receipt_pdf_fallback_canvas(receipt):
    """
    PDF minimal (Canvas, ASCII) si Platypus échoue — le parent obtient toujours un fichier valide.
    """
    payment = receipt.payment
    buf = BytesIO()
    c = pdf_canvas.Canvas(buf, pagesize=A4)
    w, h = A4

    def asc(s):
        if s is None:
            return ""
        return str(s).encode("ascii", errors="replace").decode("ascii")

    y = h - 48
    c.setFont("Helvetica-Bold", 14)
    c.drawString(40, y, "PAYMENT RECEIPT / RECU DE PAIEMENT")
    y -= 22
    c.setFont("Helvetica", 9)
    for label, value in (
        ("Receipt No", receipt.receipt_number),
        ("Payment ID", payment.payment_id),
        ("Amount", f"{payment.amount} {payment.currency or 'CDF'}"),
        ("Status", payment.status),
        ("Payer", asc(payment.user.get_full_name() if payment.user else "N/A")),
    ):
        y -= 14
        if y < 72:
            c.showPage()
            y = h - 48
            c.setFont("Helvetica", 9)
        line = f"{label}: {asc(value)}"
        c.drawString(40, y, line[:100])
    c.save()
    buf.seek(0)
    return buf.getvalue()


def _build_payment_receipt_pdf_reportlab(receipt):
    payment = receipt.payment

    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        rightMargin=2 * cm,
        leftMargin=2 * cm,
        topMargin=2 * cm,
        bottomMargin=2 * cm,
    )

    styles = getSampleStyleSheet()
    title_style = ParagraphStyle(
        "CustomTitle",
        parent=styles["Heading1"],
        fontSize=18,
        textColor=colors.HexColor("#1e40af"),
        spaceAfter=30,
        alignment=1,
    )

    heading_style = ParagraphStyle(
        "CustomHeading",
        parent=styles["Heading2"],
        fontSize=14,
        textColor=colors.HexColor("#1e40af"),
        spaceAfter=12,
    )

    normal_style = ParagraphStyle(
        "receipt_normal",
        parent=styles["Normal"],
        fontSize=11,
    )

    story = []

    story.append(Paragraph(_rl_para("REÇU DE PAIEMENT"), title_style))
    story.append(Spacer(1, 0.5 * cm))

    if payment.school:
        school = payment.school
        school_info = [
            [_cell_para(school.name, normal_style, bold=True)],
            [_cell_para(school.address or "", normal_style)],
            [_cell_para(f"Tél: {school.phone or 'N/A'}", normal_style)],
        ]
        school_table = Table(school_info, colWidths=[16 * cm])
        school_table.setStyle(
            TableStyle(
                [
                    ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                    ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ]
            )
        )
        story.append(school_table)
        story.append(Spacer(1, 0.5 * cm))

    story.append(Spacer(1, 0.3 * cm))

    gen_ts = (
        receipt.generated_at.strftime("%d/%m/%Y %H:%M")
        if receipt.generated_at
        else timezone.now().strftime("%d/%m/%Y %H:%M")
    )
    receipt_data = [
        [_cell_para("Numéro de reçu:", normal_style, bold=True), _cell_para(receipt.receipt_number, normal_style)],
        [_cell_para("Date:", normal_style, bold=True), _cell_para(gen_ts, normal_style)],
    ]

    receipt_table = Table(receipt_data, colWidths=[6 * cm, 10 * cm])
    receipt_table.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ]
        )
    )
    story.append(receipt_table)
    story.append(Spacer(1, 0.5 * cm))

    story.append(
        Paragraph(f"<b>{_rl_para('DÉTAILS DU PAIEMENT')}</b>", heading_style)
    )

    pay_name = payment.user.get_full_name() if payment.user else "N/A"
    payment_data = [
        [_cell_para("ID de paiement:", normal_style, bold=True), _cell_para(payment.payment_id, normal_style)],
        [_cell_para("Payeur:", normal_style, bold=True), _cell_para(pay_name, normal_style)],
    ]

    if payment.student:
        stu = payment.student
        su = stu.user.get_full_name() if stu.user else ""
        sid = getattr(stu, "student_id", "") or ""
        payment_data.append(
            [_cell_para("Élève:", normal_style, bold=True), _cell_para(f"{su} ({sid})", normal_style)]
        )

    payment_method_display = dict(payment.PAYMENT_METHODS).get(
        payment.payment_method, payment.payment_method
    )
    status_display = dict(payment.STATUS_CHOICES).get(payment.status, payment.status)

    payment_data.extend(
        [
            [_cell_para("Montant:", normal_style, bold=True), _cell_para(f"{payment.amount} {payment.currency or 'CDF'}", normal_style)],
            [_cell_para("Méthode de paiement:", normal_style, bold=True), _cell_para(str(payment_method_display), normal_style)],
            [_cell_para("Statut:", normal_style, bold=True), _cell_para(str(status_display), normal_style)],
        ]
    )

    if payment.payment_date:
        payment_data.append(
            [
                _cell_para("Date de paiement:", normal_style, bold=True),
                _cell_para(payment.payment_date.strftime("%d/%m/%Y %H:%M"), normal_style),
            ]
        )

    if payment.reference_number:
        payment_data.append(
            [_cell_para("Référence:", normal_style, bold=True), _cell_para(payment.reference_number, normal_style)]
        )

    if payment.description:
        payment_data.append(
            [_cell_para("Description:", normal_style, bold=True), _cell_para(payment.description, normal_style)]
        )

    payment_table = Table(payment_data, colWidths=[6 * cm, 10 * cm])
    payment_table.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    story.append(payment_table)
    story.append(Spacer(1, 1 * cm))

    signature_data = [
        [_cell_para("", normal_style), _cell_para("", normal_style)],
        [
            _cell_para("Signature du payeur", normal_style),
            _cell_para("Signature de l'école", normal_style),
        ],
    ]
    signature_table = Table(signature_data, colWidths=[8 * cm, 8 * cm])
    signature_table.setStyle(
        TableStyle(
            [
                ("FONTSIZE", (0, 0), (-1, -1), 10),
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("TOPPADDING", (0, 0), (-1, -1), 30),
            ]
        )
    )
    story.append(signature_table)

    doc.build(story)
    buffer.seek(0)
    return buffer.getvalue()


def build_payment_receipt_pdf_bytes(receipt):
    """
    Construit le PDF en mémoire (bytes). Utilisé pour le téléchargement même si
    l'enregistrement sur le disque échoue (ex. filesystem éphémère Railway).
    """
    try:
        return _build_payment_receipt_pdf_reportlab(receipt)
    except Exception:
        logger.exception("Génération reçu ReportLab échouée, repli Canvas minimal")
        return _build_payment_receipt_pdf_fallback_canvas(receipt)


def save_payment_receipt_pdf_file(receipt, pdf_bytes):
    """Enregistre les octets PDF sur le stockage par défaut."""
    filename = f"receipt_{receipt.receipt_number}.pdf"
    receipt.pdf_file.save(filename, ContentFile(pdf_bytes), save=False)
    receipt.save()


def generate_payment_receipt_pdf(receipt):
    """
    Génère un PDF de reçu de paiement et l'enregistre sur le modèle.
    """
    pdf_bytes = build_payment_receipt_pdf_bytes(receipt)
    save_payment_receipt_pdf_file(receipt, pdf_bytes)
    return receipt.pdf_file


def generate_cash_movement_voucher_pdf(movement):
    """
    Génère un PDF de bon d'entrée/sortie pour un mouvement de caisse
    """
    import logging
    logger = logging.getLogger(__name__)
    logger.info(f"Génération bon pour mouvement {movement.id} (type: {movement.movement_type}, source: {movement.source})")
    
    # Créer le buffer pour le PDF
    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, 
                           rightMargin=2*cm, leftMargin=2*cm,
                           topMargin=2*cm, bottomMargin=2*cm)
    
    # Styles
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle(
        'CustomTitle',
        parent=styles['Heading1'],
        fontSize=18,
        textColor=colors.HexColor('#059669' if movement.movement_type == 'IN' else '#dc2626'),
        spaceAfter=30,
        alignment=1,  # Center
    )
    
    heading_style = ParagraphStyle(
        'CustomHeading',
        parent=styles['Heading2'],
        fontSize=14,
        textColor=colors.HexColor('#1e40af'),
        spaceAfter=12,
    )
    
    normal_style = styles['Normal']
    normal_style.fontSize = 11
    
    # Contenu du PDF
    story = []
    
    # Titre selon le type
    voucher_type = "BON D'ENTRÉE" if movement.movement_type == 'IN' else "BON DE SORTIE"
    story.append(Paragraph(voucher_type, title_style))
    story.append(Spacer(1, 0.5*cm))
    
    # Informations de l'école
    if movement.school:
        school_info = [
            [Paragraph(f"<b>{movement.school.name}</b>", normal_style)],
            [Paragraph(f"{movement.school.address or ''}", normal_style)],
            [Paragraph(f"Tél: {movement.school.phone or 'N/A'}", normal_style)],
        ]
        school_table = Table(school_info, colWidths=[16*cm])
        school_table.setStyle(TableStyle([
            ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
            ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ]))
        story.append(school_table)
        story.append(Spacer(1, 0.5*cm))
    
    # Ligne de séparation
    story.append(Spacer(1, 0.3*cm))
    
    # Informations du bon
    voucher_number = f"BON-{movement.id:06d}"
    from .models import CashMovement, Payment
    source_display = dict(CashMovement.SOURCE_CHOICES).get(movement.source, movement.source)
    payment_method_display = movement.payment_method or 'N/A'
    if movement.payment_method:
        payment_methods = dict(Payment.PAYMENT_METHODS)
        payment_method_display = payment_methods.get(movement.payment_method, movement.payment_method)
    
    voucher_data = [
        ['Numéro du bon:', voucher_number],
        ['Date:', movement.created_at.strftime('%d/%m/%Y %H:%M') if movement.created_at else timezone.now().strftime('%d/%m/%Y %H:%M')],
        ['Type:', movement.get_movement_type_display()],
        ['Origine:', source_display],
    ]
    
    voucher_table = Table(voucher_data, colWidths=[6*cm, 10*cm])
    voucher_table.setStyle(TableStyle([
        ('FONTNAME', (0, 0), (0, -1), 'Helvetica-Bold'),
        ('FONTNAME', (1, 0), (1, -1), 'Helvetica'),
        ('FONTSIZE', (0, 0), (-1, -1), 11),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
    ]))
    story.append(voucher_table)
    story.append(Spacer(1, 0.5*cm))
    
    # Détails du mouvement
    story.append(Paragraph("<b>DÉTAILS DU MOUVEMENT</b>", heading_style))
    
    movement_data = [
        ['Montant:', f"{movement.amount} {movement.currency}"],
        ['Type de paiement:', payment_method_display],
    ]
    
    if movement.description:
        movement_data.append(['Description:', movement.description])
    
    if movement.reference_type and movement.reference_id:
        movement_data.append(['Référence:', f"{movement.reference_type} #{movement.reference_id}"])
    
    if movement.created_by:
        movement_data.append(['Créé par:', movement.created_by.get_full_name()])
    
    movement_table = Table(movement_data, colWidths=[6*cm, 10*cm])
    movement_table.setStyle(TableStyle([
        ('FONTNAME', (0, 0), (0, -1), 'Helvetica-Bold'),
        ('FONTNAME', (1, 0), (1, -1), 'Helvetica'),
        ('FONTSIZE', (0, 0), (-1, -1), 11),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
    ]))
    story.append(movement_table)
    story.append(Spacer(1, 1*cm))
    
    # Signature
    signature_data = [
        ['', ''],
        ['Signature du responsable', 'Signature du comptable'],
    ]
    signature_table = Table(signature_data, colWidths=[8*cm, 8*cm])
    signature_table.setStyle(TableStyle([
        ('FONTSIZE', (0, 0), (-1, -1), 10),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('TOPPADDING', (0, 0), (-1, -1), 30),
    ]))
    story.append(signature_table)
    
    # Construire le PDF
    doc.build(story)
    
    # Sauvegarder le PDF dans le modèle
    buffer.seek(0)
    filename = f'bon_{movement.movement_type.lower()}_{movement.id}.pdf'
    logger.info(f"Sauvegarde du document '{filename}' pour mouvement {movement.id}")
    movement.document.save(filename, ContentFile(buffer.read()), save=True)
    logger.info(f"Document sauvegardé avec succès: {movement.document.name if movement.document else 'None'}")
    
    return movement.document
