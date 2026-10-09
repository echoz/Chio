#!/usr/bin/env python3
"""Rebuild the offline map spike GeoJSON from the retained, attributed snapshots."""
import argparse
import collections
import gzip
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'Spikes/MapRendering/Fixtures'
KINDS = {'land', 'water', 'park', 'building', 'road', 'primaryRoad'}


def feature(identity, kind, name, geometry_type, coordinates):
    return {'type': 'Feature', 'id': identity,
            'properties': {'kind': kind, 'name': name},
            'geometry': {'type': geometry_type, 'coordinates': coordinates}}


def join_rings(segments):
    """Join relation member ways at exact OSM endpoints; never invent a closure."""
    pending = [list(segment) for segment in segments if len(segment) >= 2]
    rings = []
    while pending:
        ring = pending.pop(0)
        while ring[0] != ring[-1]:
            for index, segment in enumerate(pending):
                if ring[-1] == segment[0]:
                    ring.extend(segment[1:])
                elif ring[-1] == segment[-1]:
                    ring.extend(reversed(segment[:-1]))
                elif ring[0] == segment[-1]:
                    ring = segment[:-1] + ring
                elif ring[0] == segment[0]:
                    ring = list(reversed(segment[1:])) + ring
                else:
                    continue
                pending.pop(index)
                break
            else:
                raise ValueError('Relation boundary has an unclosed member chain')
        if len(ring) < 4:
            raise ValueError('Relation boundary has fewer than three vertices')
        rings.append(ring)
    return rings


def contains(ring, point):
    x, y = point
    inside = False
    for a, b in zip(ring, ring[1:]):
        if (a[1] > y) != (b[1] > y):
            crossing = (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]
            if x < crossing:
                inside = not inside
    return inside


def signed_area(ring):
    return sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(ring, ring[1:])) / 2


def orient_polygon(rings):
    # GeoJSON right-hand rule: counterclockwise shell and clockwise holes.
    return [ring if (signed_area(ring) > 0) == (index == 0) else list(reversed(ring))
            for index, ring in enumerate(rings)]


def osm_kind(tags):
    if tags.get('natural') == 'water':
        return 'water'
    if tags.get('leisure') == 'park':
        return 'park'
    if tags.get('building') and tags.get('name'):
        return 'building'
    if tags.get('highway'):
        return 'primaryRoad' if tags['highway'].split('_')[0] in {
            'motorway', 'trunk', 'primary'} else 'road'
    return None


def coordinates(geometry):
    return [[point['lon'], point['lat']] for point in geometry]


def singapore(source):
    features = []
    elements = sorted(source['elements'], key=lambda e: (e['type'], e['id']))
    # Retain a street-scale subset; complete water relation geometry remains intact.
    omitted_highways = {'service', 'footway', 'path', 'cycleway', 'living_street'}
    area_relations = [e for e in elements if e['type'] == 'relation'
                      and e.get('tags', {}).get('type') == 'multipolygon'
                      and osm_kind(e.get('tags', {})) in {'water', 'park', 'building'}]
    represented_members = {m['ref'] for e in area_relations for m in e['members']
                           if m['type'] == 'way' and m.get('role', '') in {'', 'outer', 'inner'}}
    for element in elements:
        tags = element.get('tags', {})
        kind = osm_kind(tags)
        if not kind or element['type'] not in {'way', 'relation'}:
            continue
        if tags.get('highway') in omitted_highways:
            continue
        if tags.get('name') == 'East Coast Park':
            continue  # A large coastal park mostly outside this neighborhood.
        identity = 'osm-{}-{}'.format(element['type'], element['id'])
        name = tags.get('name', '')
        if element['type'] == 'way':
            if element['id'] in represented_members and kind in {'water', 'park', 'building'}:
                continue
            points = coordinates(element['geometry'])
            if kind in {'road', 'primaryRoad'}:
                features.append(feature(identity, kind, name, 'LineString', points))
            elif len(points) >= 4 and points[0] == points[-1]:
                features.append(feature(identity, kind, name, 'Polygon', orient_polygon([points])))
            else:
                raise ValueError('Area way is not closed: ' + identity)
        else:
            if tags.get('type') == 'building':
                outlines = [coordinates(m['geometry']) for m in element['members']
                            if m['type'] == 'way' and m.get('role') == 'outline']
                for index, ring in enumerate(outlines):
                    if len(ring) < 4 or ring[0] != ring[-1]:
                        raise ValueError('Building outline is not closed: ' + identity)
                    features.append(feature(identity + '-outline-{}'.format(index), kind, name,
                                            'Polygon', orient_polygon([ring])))
                continue  # Parts-only buildings do not supply an unambiguous footprint.
            if tags.get('type') != 'multipolygon':
                raise ValueError('Unsupported selected area relation: ' + identity)
            outer = join_rings([coordinates(m['geometry']) for m in element['members']
                                if m['type'] == 'way' and m.get('role', '') in {'', 'outer'}])
            inner = join_rings([coordinates(m['geometry']) for m in element['members']
                                if m['type'] == 'way' and m.get('role') == 'inner'])
            polygons = [[ring] for ring in outer]
            for hole in inner:
                owners = [i for i, polygon in enumerate(polygons) if contains(polygon[0], hole[0])]
                if not owners:
                    raise ValueError('Unassigned hole: ' + identity)
                owner = min(owners, key=lambda i: abs(signed_area(polygons[i][0])))
                polygons[owner].append(hole)
            for index, polygon in enumerate(polygons):
                features.append(feature(identity + '-part-{}'.format(index), kind, name,
                                        'Polygon', orient_polygon(polygon)))
    return {'type': 'FeatureCollection', 'attribution': '© OpenStreetMap contributors',
            'license': 'https://opendatacommons.org/licenses/odbl/1-0/',
            'attributionURL': 'https://www.openstreetmap.org/copyright',
            'features': features}


def world(source):
    features = []
    for index, item in enumerate(source['features']):
        geometry = item['geometry']
        polygons = ([geometry['coordinates']] if geometry['type'] == 'Polygon'
                    else geometry['coordinates'])
        if geometry['type'] not in {'Polygon', 'MultiPolygon'}:
            raise ValueError('Unexpected Natural Earth geometry')
        for part, polygon in enumerate(polygons):
            features.append(feature('natural-earth-land-{}-part-{}'.format(index, part),
                                    'land', '', 'Polygon', orient_polygon(polygon)))
    return {'type': 'FeatureCollection', 'attribution': 'Made with Natural Earth',
            'license': 'https://www.naturalearthdata.com/about/terms-of-use/',
            'features': features}


def validate(document):
    identities = set()
    points = []
    counts = collections.Counter()
    holes = 0
    assert document['type'] == 'FeatureCollection'
    for item in document['features']:
        identity = item['id']
        assert isinstance(identity, str) and identity and identity not in identities
        identities.add(identity)
        assert item['type'] == 'Feature'
        props = item['properties']
        assert props['kind'] in KINDS and isinstance(props['name'], str)
        assert len(props['name'].encode('utf-8')) <= 256
        assert all(ord(character) >= 32 and ord(character) != 127 for character in props['name'])
        counts[props['kind']] += 1
        geometry = item['geometry']
        if geometry['type'] == 'Polygon':
            rings = geometry['coordinates']
            assert rings
            holes += len(rings) - 1
            for ring in rings:
                assert len(ring) >= 4 and ring[0] == ring[-1]
                points.extend(ring)
        else:
            assert geometry['type'] == 'LineString'
            assert len(geometry['coordinates']) >= 2
            points.extend(geometry['coordinates'])
    assert points and len(points) < 100000
    for point in points:
        assert len(point) == 2 and all(math.isfinite(value) for value in point)
        assert -180 <= point[0] <= 180 and -90 <= point[1] <= 90
    return {'features': len(identities), 'vertices': len(points), 'holes': holes,
            'kinds': dict(sorted(counts.items())),
            'bounds': [min(p[0] for p in points), min(p[1] for p in points),
                       max(p[0] for p in points), max(p[1] for p in points)]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', action='store_true', help='Check exact snapshot reproduction without writing')
    args = parser.parse_args()
    for name, transform in [('world', world), ('singapore', singapore)]:
        source_path = FIXTURES / (name + '-source.json.gz')
        source = json.loads(gzip.decompress(source_path.read_bytes()))
        document = transform(source)
        stats = validate(document)
        encoded = (json.dumps(document, separators=(',', ':'), ensure_ascii=False) + '\n').encode()
        assert len(encoded) < 1000000
        destination = FIXTURES / (name + '.geojson')
        if args.verify:
            assert destination.read_bytes() == encoded, 'Fixture differs from retained snapshot: ' + name
            validate(json.loads(destination.read_bytes()))
        else:
            destination.write_bytes(encoded)
        stats.update(bytes=len(encoded), sha256=hashlib.sha256(encoded).hexdigest())
        print(name + ': ' + json.dumps(stats, sort_keys=True))

    # The MVT fixture is the exact provider response, not converted GeoJSON.
    # Swift's decoder/adapter tests verify geometry and source semantics.
    manifest = json.loads((FIXTURES / 'provenance.json').read_text())['sources']['openfreemap']
    tile = (FIXTURES / manifest['fixture']).read_bytes()
    assert len(tile) == manifest['bytes'] and len(tile) <= 2 * 1024 * 1024
    assert hashlib.sha256(tile).hexdigest() == manifest['sha256'], 'Provider tile bytes changed'
    metadata = (FIXTURES / manifest['tileJSON']).read_bytes()
    assert hashlib.sha256(metadata).hexdigest() == manifest['tileJSONSHA256'], 'TileJSON bytes changed'
    coordinate = manifest['tile']
    assert 0 <= coordinate['zoom'] <= 22
    assert all(0 <= coordinate[axis] < 2 ** coordinate['zoom'] for axis in ('x', 'y'))
    template = json.loads(metadata)['tiles'][0]
    assert template.format(z=coordinate['zoom'], x=coordinate['x'], y=coordinate['y']) == manifest['sourceURL']
    print('openfreemap: ' + json.dumps({'bytes': len(tile), 'sha256': manifest['sha256'], 'tile': coordinate}, sort_keys=True))


if __name__ == '__main__':
    main()
