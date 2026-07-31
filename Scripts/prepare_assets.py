from pathlib import Path

from PIL import Image


ASSET_DIR = Path(__file__).resolve().parents[1] / "Assets"
CANVAS_SIZE = (512, 384)
SUBJECT_LIMIT = (500, 372)


def prepare(name: str) -> None:
    source_path = ASSET_DIR / f"{name}.png"
    image = Image.open(source_path).convert("RGBA")
    alpha = image.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        raise RuntimeError(f"{source_path} has no visible pixels")

    subject = image.crop(bounds)
    scale = min(
        SUBJECT_LIMIT[0] / subject.width,
        SUBJECT_LIMIT[1] / subject.height,
    )
    size = (
        max(1, round(subject.width * scale)),
        max(1, round(subject.height * scale)),
    )
    nearest = getattr(getattr(Image, "Resampling", Image), "NEAREST")
    subject = subject.resize(size, nearest)

    canvas = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    origin = (
        (CANVAS_SIZE[0] - subject.width) // 2,
        CANVAS_SIZE[1] - subject.height,
    )
    canvas.alpha_composite(subject, origin)
    canvas.save(ASSET_DIR / f"{name}-prepared.png")


for asset_name in (
    "cat-playing-deck-v2",
    "cat-sleeping-deck-v2",
    "cat-switching-deck-v2",
):
    prepare(asset_name)
