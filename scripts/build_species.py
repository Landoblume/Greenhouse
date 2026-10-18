"""Regenerate Greenhouse/Resources/species.json.

    python3 scripts/build_species.py

Two inputs, merged by Latin name:
- scripts/houseplants.json: researched houseplants (species and popular
  cultivars), each with the page its zone range came from and whether that
  was actually checked. These win when a name appears in both.
- ROWS below: herbs, edibles and garden plants, drafted from general
  horticulture references and NOT checked entry by entry.

Columns in ROWS: latin, common names, USDA zone min, zone max, light, water
every N days (a starting point; each plant's schedule is editable), frost
tolerance. Fix a row (here or in the JSON) when you find it's off, rerun, and
commit the result.

IDs are slugs of the Latin name, and saved plants point at them, so renaming
an entry's Latin name orphans its plants' care data.
"""

import json
import re
from pathlib import Path

SOURCE = "Per entry; entries without a source were drafted from general horticulture references"
HOUSEPLANTS = Path(__file__).with_name("houseplants.json")

BI = "Bright, indirect"
MI = "Medium, indirect"
LI = "Low to bright, indirect"
SUN = "Full sun"
PART = "Part sun to part shade"
SHADE = "Shade to part shade"

ROWS = [
    # Houseplants (tropical / succulent)
    ("Aloe vera", ["Aloe vera", "Aloe", "Medicinal aloe"], 10, 12, "Bright, direct or indirect", 21, "tender"),
    ("Epipremnum aureum", ["Pothos", "Golden pothos", "Devil's ivy"], 10, 12, LI, 7, "tender"),
    ("Dracaena trifasciata", ["Snake plant", "Mother-in-law's tongue", "Sansevieria"], 10, 12, LI, 21, "tender"),
    ("Zamioculcas zamiifolia", ["ZZ plant", "Zanzibar gem"], 10, 12, LI, 21, "tender"),
    ("Monstera deliciosa", ["Monstera", "Swiss cheese plant"], 10, 12, BI, 7, "tender"),
    ("Philodendron hederaceum", ["Heartleaf philodendron", "Philodendron"], 10, 12, MI, 7, "tender"),
    ("Spathiphyllum wallisii", ["Peace lily"], 11, 12, "Low to medium, indirect", 7, "tender"),
    ("Chlorophytum comosum", ["Spider plant"], 9, 11, BI, 7, "tender"),
    ("Ficus lyrata", ["Fiddle-leaf fig"], 10, 12, BI, 7, "tender"),
    ("Ficus elastica", ["Rubber plant", "Rubber tree"], 10, 12, BI, 10, "tender"),
    ("Ficus benjamina", ["Weeping fig"], 10, 12, BI, 7, "tender"),
    ("Dracaena marginata", ["Dragon tree", "Madagascar dragon tree"], 10, 12, MI, 10, "tender"),
    ("Dracaena fragrans", ["Corn plant"], 10, 12, MI, 10, "tender"),
    ("Aglaonema commutatum", ["Chinese evergreen"], 10, 12, "Low to medium, indirect", 7, "tender"),
    ("Goeppertia orbifolia", ["Calathea orbifolia", "Calathea"], 11, 12, MI, 5, "tender"),
    ("Maranta leuconeura", ["Prayer plant"], 11, 12, MI, 5, "tender"),
    ("Hoya carnosa", ["Wax plant", "Hoya"], 10, 12, BI, 10, "tender"),
    ("Peperomia obtusifolia", ["Baby rubber plant", "Peperomia"], 10, 12, MI, 10, "tender"),
    ("Pilea peperomioides", ["Chinese money plant", "Pancake plant"], 10, 11, BI, 7, "tender"),
    ("Strelitzia reginae", ["Bird of paradise"], 10, 12, "Bright, some direct sun", 7, "tender"),
    ("Crassula ovata", ["Jade plant"], 10, 12, "Bright, some direct sun", 14, "tender"),
    ("Schlumbergera x buckleyi", ["Christmas cactus", "Holiday cactus"], 10, 12, BI, 10, "tender"),
    ("Haworthiopsis attenuata", ["Zebra haworthia", "Zebra plant"], 10, 11, BI, 21, "tender"),
    ("Echeveria elegans", ["Mexican snowball", "Echeveria"], 9, 11, SUN, 14, "tender"),
    ("Nephrolepis exaltata", ["Boston fern"], 10, 12, MI, 4, "tender"),
    ("Adiantum raddianum", ["Maidenhair fern"], 10, 11, MI, 3, "tender"),
    ("Asplenium nidus", ["Bird's nest fern"], 11, 12, MI, 7, "tender"),
    ("Begonia rex", ["Rex begonia", "Painted-leaf begonia"], 10, 12, MI, 7, "tender"),
    ("Phalaenopsis", ["Moth orchid", "Orchid"], 10, 12, BI, 7, "tender"),
    ("Anthurium andraeanum", ["Anthurium", "Flamingo flower"], 11, 12, BI, 7, "tender"),
    ("Dieffenbachia seguine", ["Dumb cane", "Dieffenbachia"], 10, 12, MI, 7, "tender"),
    ("Syngonium podophyllum", ["Arrowhead plant", "Syngonium"], 10, 12, MI, 7, "tender"),
    ("Tradescantia zebrina", ["Inch plant", "Wandering dude"], 9, 12, BI, 7, "tender"),
    ("Curio rowleyanus", ["String of pearls"], 9, 12, BI, 14, "tender"),
    ("Ceropegia woodii", ["String of hearts", "Rosary vine"], 10, 11, BI, 14, "tender"),
    ("Chamaedorea elegans", ["Parlor palm"], 10, 12, "Low to medium, indirect", 7, "tender"),
    ("Dypsis lutescens", ["Areca palm", "Butterfly palm"], 10, 11, BI, 7, "tender"),
    ("Beaucarnea recurvata", ["Ponytail palm"], 9, 11, "Bright, some direct sun", 21, "tender"),
    ("Alocasia x amazonica", ["Alocasia", "African mask plant"], 10, 12, BI, 7, "tender"),
    ("Oxalis triangularis", ["Purple shamrock", "False shamrock"], 8, 11, BI, 7, "semi-hardy"),
    ("Saintpaulia ionantha", ["African violet"], 11, 12, BI, 7, "tender"),
    ("Kalanchoe blossfeldiana", ["Kalanchoe", "Flaming Katy"], 10, 12, "Bright, some direct sun", 14, "tender"),
    ("Tillandsia", ["Air plant"], 9, 11, BI, 7, "tender"),
    ("Opuntia microdasys", ["Bunny ears cactus"], 9, 11, SUN, 21, "tender"),
    ("Hedera helix", ["English ivy", "Ivy"], 5, 9, MI, 7, "hardy"),
    # Herbs and edibles
    ("Ocimum basilicum", ["Basil", "Sweet basil"], 10, 11, SUN, 2, "tender"),
    ("Mentha spicata", ["Spearmint", "Mint"], 4, 9, PART, 3, "hardy"),
    ("Salvia rosmarinus", ["Rosemary"], 8, 10, SUN, 10, "semi-hardy"),
    ("Lavandula angustifolia", ["English lavender", "Lavender"], 5, 8, SUN, 10, "hardy"),
    ("Thymus vulgaris", ["Thyme", "Common thyme"], 5, 9, SUN, 10, "hardy"),
    ("Petroselinum crispum", ["Parsley"], 5, 9, PART, 3, "hardy"),
    ("Salvia officinalis", ["Sage", "Garden sage"], 5, 8, SUN, 7, "hardy"),
    ("Allium schoenoprasum", ["Chives"], 3, 9, SUN, 4, "hardy"),
    ("Solanum lycopersicum", ["Tomato"], 10, 11, SUN, 2, "tender"),
    ("Capsicum annuum", ["Pepper", "Bell pepper", "Chili pepper"], 9, 11, SUN, 3, "tender"),
    ("Fragaria x ananassa", ["Strawberry", "Garden strawberry"], 5, 8, SUN, 3, "hardy"),
    ("Citrus x meyeri", ["Meyer lemon", "Lemon tree"], 9, 11, SUN, 7, "tender"),
    ("Ficus carica", ["Fig", "Common fig"], 7, 10, SUN, 7, "semi-hardy"),
    ("Olea europaea", ["Olive tree", "Olive"], 8, 10, SUN, 10, "semi-hardy"),
    # Garden perennials, shrubs, bulbs
    ("Hosta", ["Hosta", "Plantain lily"], 3, 8, SHADE, 4, "hardy"),
    ("Rosa", ["Rose", "Hybrid tea rose"], 5, 9, SUN, 4, "hardy"),
    ("Hydrangea macrophylla", ["Bigleaf hydrangea", "Hydrangea"], 6, 9, PART, 3, "hardy"),
    ("Hemerocallis", ["Daylily"], 3, 9, SUN, 7, "hardy"),
    ("Echinacea purpurea", ["Purple coneflower", "Coneflower", "Echinacea"], 3, 8, SUN, 7, "hardy"),
    ("Rudbeckia hirta", ["Black-eyed Susan"], 3, 7, SUN, 7, "hardy"),
    ("Paeonia lactiflora", ["Peony", "Chinese peony"], 3, 8, SUN, 7, "hardy"),
    ("Syringa vulgaris", ["Lilac", "Common lilac"], 3, 7, SUN, 10, "hardy"),
    ("Buxus sempervirens", ["Boxwood", "Common box"], 5, 8, PART, 7, "hardy"),
    ("Acer palmatum", ["Japanese maple"], 5, 8, PART, 7, "hardy"),
    ("Chrysanthemum x morifolium", ["Garden mum", "Chrysanthemum", "Mum"], 5, 9, SUN, 4, "hardy"),
    ("Pelargonium x hortorum", ["Geranium", "Zonal geranium"], 10, 11, SUN, 4, "tender"),
    ("Agave americana", ["Century plant", "Agave"], 8, 11, SUN, 21, "semi-hardy"),
    ("Yucca filamentosa", ["Adam's needle", "Yucca"], 4, 10, SUN, 21, "hardy"),
    ("Hylotelephium spectabile", ["Showy stonecrop", "Sedum"], 3, 9, SUN, 14, "hardy"),
    ("Sempervivum tectorum", ["Hens and chicks", "Houseleek"], 3, 8, SUN, 14, "hardy"),
    ("Opuntia humifusa", ["Eastern prickly pear", "Prickly pear"], 4, 9, SUN, 21, "hardy"),
    ("Gardenia jasminoides", ["Gardenia"], 8, 11, PART, 5, "semi-hardy"),
    ("Hibiscus rosa-sinensis", ["Tropical hibiscus", "Hibiscus"], 9, 11, SUN, 4, "tender"),
    ("Mandevilla sanderi", ["Mandevilla", "Brazilian jasmine"], 10, 11, SUN, 5, "tender"),
    ("Bougainvillea glabra", ["Bougainvillea"], 9, 11, SUN, 7, "tender"),
    ("Clematis", ["Clematis"], 4, 8, SUN, 7, "hardy"),
    ("Lonicera sempervirens", ["Coral honeysuckle", "Trumpet honeysuckle"], 4, 9, SUN, 7, "hardy"),
    ("Coleus scutellarioides", ["Coleus"], 10, 11, PART, 3, "tender"),
    ("Caladium bicolor", ["Caladium", "Angel wings"], 9, 10, PART, 4, "tender"),
    ("Colocasia esculenta", ["Elephant ear", "Taro"], 8, 11, PART, 3, "semi-hardy"),
    ("Begonia semperflorens", ["Wax begonia"], 10, 11, PART, 4, "tender"),
    ("Impatiens walleriana", ["Impatiens", "Busy Lizzie"], 10, 11, SHADE, 3, "tender"),
    ("Dahlia", ["Dahlia"], 8, 11, SUN, 4, "semi-hardy"),
    ("Canna x generalis", ["Canna lily", "Canna"], 8, 11, SUN, 4, "semi-hardy"),
    ("Gladiolus", ["Gladiolus", "Sword lily"], 7, 10, SUN, 4, "semi-hardy"),
    ("Tulipa", ["Tulip"], 3, 8, SUN, 7, "hardy"),
    ("Narcissus", ["Daffodil"], 3, 8, SUN, 7, "hardy"),
    ("Lilium", ["Lily"], 4, 8, SUN, 7, "hardy"),
    ("Lavandula stoechas", ["Spanish lavender"], 7, 9, SUN, 10, "semi-hardy"),
]


LIGHTS = {BI, MI, LI, SUN, PART, SHADE, "Low to medium, indirect", "Bright, some direct sun",
          "Bright, direct or indirect"}


def slug(latin: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", latin.lower()).strip("-")


def entry(latin, common, zmin, zmax, light, water, frost, source=None, verified=False) -> dict:
    assert zmin <= zmax and 1 <= zmin and zmax <= 13, latin
    assert light in LIGHTS, (latin, light)
    assert frost in ("tender", "semi-hardy", "hardy"), (latin, frost)
    assert 1 <= water <= 60, latin
    plain = latin.replace(" × ", " x ")
    return {
        "id": slug(plain),
        # Botanical convention writes hybrids with ×; the inputs use x for typing ease.
        "latin": plain.replace(" x ", " × "),
        "common": common,
        "zoneMin": zmin,
        "zoneMax": zmax,
        "light": light,
        "waterDays": water,
        "frost": frost,
        "source": source,
        "verified": verified,
    }


def main() -> None:
    by_id: dict[str, dict] = {}
    for row in json.loads(HOUSEPLANTS.read_text()) if HOUSEPLANTS.exists() else []:
        e = entry(row["latin"], row["common"], row["zoneMin"], row["zoneMax"], row["light"],
                  row["waterDays"], row["frost"], row.get("source"), bool(row.get("verified")))
        by_id[e["id"]] = e
    for row in ROWS:
        e = entry(*row)
        by_id.setdefault(e["id"], e)

    species = sorted(by_id.values(), key=lambda s: s["latin"])
    out = Path(__file__).resolve().parent.parent / "Greenhouse/Resources/species.json"
    out.write_text(json.dumps({"source": SOURCE, "species": species}, indent=2, ensure_ascii=False) + "\n")
    verified = sum(1 for s in species if s["verified"])
    print(f"wrote {len(species)} species ({verified} verified) to {out}")


if __name__ == "__main__":
    main()
