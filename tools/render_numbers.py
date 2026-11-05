#!/usr/bin/env python3
"""Pré-rend les nombres du cadran en Telma : une paire de planches PNG par résolution d'écran.

    pip install pillow
    python3 tools/render_numbers.py <chemin/vers/Telma-Bold.otf> myGarminWatchFace

La police n'est pas dans le repo : à télécharger sur https://www.fontshare.com/fonts/telma.
Sa licence (ITF FFL) autorise d'en tirer des images, pas de la convertir ni de la redistribuer ;
c'est pour ça que le cadran utilise ces images et non une police bitmap (.fnt).

Chaque planche compte SHEET_COLS colonnes. Les chiffres sont blancs, centrés dans leur case,
et teintés à l'affichage par drawBitmap2 (:tintColor). Les heures sont déjà inclinées selon leur
position sur le cercle, avec la même règle que le texte des mois (ringText dans la vue).
"""

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SHEET_COLS = 6  # à garder identique à SHEET_COLS dans myGarminWatchFaceView.mc
RESOLUTIONS = (416, 454, 466)
SHEETS = {
    # fichier : (dernier nombre, taille de police en fraction du rayon d'écran, suit le cercle ?)
    "hours.png": (12, 0.1375, True),
    "days.png": (31, 0.118, False),
}
OVERSAMPLE = 8      # rendu sur-échantillonné puis réduit : contours nets, sans hinting
ALPHA_GAMMA = 0.80  # < 1 renforce les déliés de Telma, trop fins à cette taille sinon


def ring_rotation(hour: int) -> int:
    """Rotation horaire d'un chiffre d'heure, en degrés : tête vers l'extérieur, sauf en bas
    du cadran où elle est retournée pour rester lisible, comme dans ringText."""
    angle = hour * 30 % 360
    return angle - 180 if 90 < angle < 270 else angle


def cell_size(length: float) -> int:
    """Taille de case impaire en pixels finaux : son pixel central tombe sur le point visé (voir
    drawNumber dans la vue), avec au moins un pixel de marge de chaque côté."""
    return math.ceil(length / 2) * 2 + 3


def render_sheet(font_path: Path, em: float, last: int, follow_ring: bool) -> Image.Image:
    font = ImageFont.truetype(str(font_path), round(em * OVERSAMPLE))
    numbers = [str(n) for n in range(1, last + 1)]
    boxes = [font.getbbox(text, anchor="ls") for text in numbers]

    # Cases assez grandes pour le nombre le plus encombrant, quelle que soit son inclinaison
    width = max(b[2] - b[0] for b in boxes) / OVERSAMPLE
    height = max(b[3] - b[1] for b in boxes) / OVERSAMPLE
    if follow_ring:
        width = height = math.hypot(width, height)
    cell_w, cell_h = cell_size(width), cell_size(height)
    rows = (last + SHEET_COLS - 1) // SHEET_COLS

    mask = Image.new("L", (SHEET_COLS * cell_w * OVERSAMPLE, rows * cell_h * OVERSAMPLE), 0)
    for i, (text, box) in enumerate(zip(numbers, boxes)):
        # Le centre de la boîte englobante tombe au centre de la case, seul point fixe de la rotation
        cell = Image.new("L", (cell_w * OVERSAMPLE, cell_h * OVERSAMPLE), 0)
        origin = (cell.width / 2 - (box[0] + box[2]) / 2, cell.height / 2 - (box[1] + box[3]) / 2)
        ImageDraw.Draw(cell).text(origin, text, font=font, fill=255, anchor="ls")
        if follow_ring:
            cell = cell.rotate(-ring_rotation(i + 1), resample=Image.Resampling.BICUBIC)
        mask.paste(cell, (i % SHEET_COLS * cell.width, i // SHEET_COLS * cell.height))

    mask = mask.resize((SHEET_COLS * cell_w, rows * cell_h), Image.Resampling.BOX)
    mask = mask.point(lambda a: round(255 * (a / 255) ** ALPHA_GAMMA))
    sheet = Image.new("RGBA", mask.size, (255, 255, 255, 0))
    sheet.putalpha(mask)
    return sheet


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    font_path, project = Path(sys.argv[1]), Path(sys.argv[2])
    for size in RESOLUTIONS:
        out_dir = project / f"resources-round-{size}x{size}" / "drawables"
        out_dir.mkdir(parents=True, exist_ok=True)
        for name, (last, ratio, follow_ring) in SHEETS.items():
            sheet = render_sheet(font_path, ratio * size / 2, last, follow_ring)
            sheet.save(out_dir / name, optimize=True)
            print(out_dir / name, sheet.size)


if __name__ == "__main__":
    main()
