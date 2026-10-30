"""Regenerate deterministic PDF source/crop fixtures (reportlab + pypdf)."""
from io import BytesIO
import json
from pathlib import Path

from reportlab.pdfgen.canvas import Canvas
from pypdf import PdfReader, PdfWriter
from pypdf.generic import RectangleObject

OUT = Path(__file__).resolve().parents[1] / "test/fixtures/annotations"
COLORS = [(1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 0)]


def create(name, pages):
    buffer = BytesIO()
    canvas = Canvas(buffer, pagesize=(700, 700), invariant=1)
    expected = []
    for media, crop, rotation in pages:
        left, bottom = max(media[0], crop[0]), max(media[1], crop[1])
        right, top = min(media[2], crop[2]), min(media[3], crop[3])
        width, height = right - left, top - bottom
        for (dx, dy), rgb in zip([(0, 1), (1, 1), (0, 0), (1, 0)], COLORS):
            canvas.setFillColorRGB(*rgb)
            canvas.rect(left + dx * width / 2, bottom + dy * height / 2,
                        width / 2, height / 2, fill=1, stroke=0)
        canvas.setStrokeColorRGB(1, 1, 1)
        canvas.setLineWidth(2)
        canvas.line(left + width / 2, bottom, left + width / 2, top)
        canvas.line(left, bottom + height / 2, right, bottom + height / 2)
        canvas.setFillColorRGB(0, 0, 0)
        canvas.setFont("Helvetica", 10)
        canvas.drawString(left + 8, top - 18, f"PDF source: rotate {rotation}")
        canvas.showPage()
        expected.append({"mediaBox": media, "cropBox": crop,
                         "effectiveBox": [left, bottom, right, top],
                         "rotation": rotation,
                         "widthPoints": height if rotation % 180 else width,
                         "heightPoints": width if rotation % 180 else height,
                         "topLeftRgb": COLORS[{0: 0, 90: 2, 180: 3, 270: 1}[rotation]]})
    canvas.save()
    reader = PdfReader(buffer)
    writer = PdfWriter()
    for page, (media, crop, rotation) in zip(reader.pages, pages):
        page.mediabox = RectangleObject(media)
        page.cropbox = RectangleObject(crop)
        page.rotate(rotation)
        writer.add_page(page)
    OUT.mkdir(parents=True, exist_ok=True)
    writer.write(OUT / f"{name}.pdf")
    (OUT / f"{name}.json").write_text(json.dumps(expected, indent=2) + "\n")


if __name__ == "__main__":
    create("pdf-crop-rotate", [([-40, -20, 380, 540], [40, 80, 280, 400], r)
                               for r in [0, 90, 180, 270]])
    create("pdf-mixed-boxes", [([0, 0, 360, 480], [-50, 20, 300, 520], 90),
                               ([0, 0, 640, 360], [40, -30, 600, 300], 270)])
