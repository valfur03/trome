#!/usr/bin/env python3
import json
import math
import sys
import urllib.request
from pathlib import Path

DATASETS_URL = "https://data.iledefrance-mobilites.fr/api/explore/v2.1/catalog/datasets/"
SOURCE_URL = DATASETS_URL + "arrets-lignes/exports/json"
HUBS_URL = (
    DATASETS_URL
    + "relations/exports/json?select=pdeid,zdaid,arrid&where=pdeid%20is%20not%20null"
)
STOP_AREA_PREFIX = "IDFM:monomodalStopPlace:"
OUTPUT = (
    Path(__file__).resolve().parent.parent
    / "Packages/RATPCore/Sources/RATPCore/Resources/stations.json"
)
MODES = {"Metro": "metro", "RapidTransit": "rer"}
METRO_LINES = {str(number) for number in range(1, 15)} | {"3B", "7B"}
RER_LINES = {"A", "B", "C", "D", "E"}
LINE_NAMES = {"3B": "3bis", "7B": "7bis"}
STATION_NAMES = {
    "Aéroport CDG 1 (Terminal 3) - RER": "Aéroport Charles de Gaulle 1",
    "Aéroport Charles de Gaulle 2 (Terminal 2)": "Aéroport Charles de Gaulle 2 TGV",
    "Rosny Bois Perrier": "Rosny-Bois-Perrier",
}
SAME_STATION_MAX_METERS = 1000


def distance_meters(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = (
        math.sin((lat2 - lat1) / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    )
    return 6_371_000 * 2 * math.asin(math.sqrt(h))


def is_wanted(row):
    mode = MODES.get(row.get("mode"))
    line = row.get("shortname")
    if mode == "metro":
        return line in METRO_LINES
    if mode == "rer":
        return line in RER_LINES
    return False


def cluster_by_distance(rows):
    clusters = []
    for row in rows:
        position = (float(row["stop_lat"]), float(row["stop_lon"]))
        near = [
            cluster
            for cluster in clusters
            if any(
                distance_meters(position, other) <= SAME_STATION_MAX_METERS
                for other in cluster["positions"]
            )
        ]
        merged = {"rows": [row], "positions": [position]}
        for cluster in near:
            merged["rows"] += cluster["rows"]
            merged["positions"] += cluster["positions"]
            clusters.remove(cluster)
        clusters.append(merged)
    return [cluster["rows"] for cluster in clusters]


def line_sort_key(line):
    order = 0 if line["mode"] == "metro" else 1
    digits = "".join(c for c in line["name"] if c.isdigit())
    return (order, int(digits) if digits else 0, line["name"])


def station_name(row):
    return STATION_NAMES.get(row["stop_name"], row["stop_name"])


def download(url):
    with urllib.request.urlopen(url) as response:
        return json.load(response)


def hub_ids_by_stop_id(relations):
    hubs = {}
    for relation in relations:
        if relation.get("arrid"):
            hubs["IDFM:" + relation["arrid"]] = relation["pdeid"]
        if relation.get("zdaid"):
            hubs[STOP_AREA_PREFIX + relation["zdaid"]] = relation["pdeid"]
    return hubs


def add_hub_ids(stations, hubs_by_stop_id):
    for station in stations:
        stop_ids = [stop_id for line in station["lines"] for stop_id in line["stopIds"]]
        hub_ids = sorted({hubs_by_stop_id[stop_id] for stop_id in stop_ids if stop_id in hubs_by_stop_id})
        if hub_ids:
            station["hubId"] = hub_ids[0]
    station_count = {}
    for station in stations:
        if "hubId" in station:
            station_count[station["hubId"]] = station_count.get(station["hubId"], 0) + 1
    for station in stations:
        if station_count.get(station.get("hubId"), 0) < 2:
            station.pop("hubId", None)


def build_station(rows):
    lines = {}
    for row in rows:
        mode = MODES[row["mode"]]
        name = LINE_NAMES.get(row["shortname"], row["shortname"])
        line = lines.setdefault((mode, name), {"mode": mode, "name": name, "stopIds": set()})
        line["stopIds"].add(row["stop_id"])
    latitude = sum(float(row["stop_lat"]) for row in rows) / len(rows)
    longitude = sum(float(row["stop_lon"]) for row in rows) / len(rows)
    sorted_lines = sorted(lines.values(), key=line_sort_key)
    return {
        "id": min(row["stop_id"] for row in rows),
        "name": station_name(rows[0]),
        "latitude": round(latitude, 6),
        "longitude": round(longitude, 6),
        "lines": [
            {"mode": line["mode"], "name": line["name"], "stopIds": sorted(line["stopIds"])}
            for line in sorted_lines
        ],
    }


def main():
    rows = download(SOURCE_URL)

    by_name = {}
    for row in filter(is_wanted, rows):
        by_name.setdefault(station_name(row), []).append(row)

    stations = [
        build_station(cluster)
        for name_rows in by_name.values()
        for cluster in cluster_by_distance(name_rows)
    ]
    stations.sort(key=lambda station: (station["name"], station["id"]))
    add_hub_ids(stations, hub_ids_by_stop_id(download(HUBS_URL)))

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", encoding="utf-8") as output:
        output.write("[\n")
        output.write(
            ",\n".join(json.dumps(station, ensure_ascii=False) for station in stations)
        )
        output.write("\n]\n")

    print(f"Wrote {len(stations)} stations to {OUTPUT}", file=sys.stderr)


if __name__ == "__main__":
    main()
