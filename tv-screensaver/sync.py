#!/usr/bin/env python3
"""Keep the Immich album "TV Screensaver" filled with Jack's photos and videos
from 2021 on that show any face or a dog. Run nightly by tv-screensaver-album.timer.
Selection is read from Postgres; album changes go through the Immich API."""
import json, subprocess, sys, urllib.request

API = "http://127.0.0.1:2283/api"
KEY = open("/opt/immich/tv-screensaver/api-key").read().strip()
OWNER = "133bd102-8e69-4925-bae5-b9644c7ee9c8"      # Jack
SINCE = "2021-01-01"
DOG_TEXT = "a photo of a dog"
DOG_MAX_DIST = 0.77   # CLIP cosine distance; checked by eye 2026-11-10 (<0.77 all dogs, 0.77-0.78 mostly not)
ALBUM = "TV Screensaver"
MODEL = "ViT-B-32__openai"

def sh(*cmd, inp=None):
    return subprocess.run(cmd, input=inp, capture_output=True, text=True, check=True).stdout

def api(method, path, body=None):
    req = urllib.request.Request(API + path, method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={"x-api-key": KEY, "Content-Type": "application/json", "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        data = r.read()
        return json.loads(data) if data else None

def sql(q):
    return [l for l in sh("docker", "exec", "-i", "immich_postgres", "psql", "-U", "postgres",
                          "-d", "immich", "-At", "-v", "ON_ERROR_STOP=1", inp=q).splitlines() if l]

entries = json.dumps({"clip": {"textual": {"modelName": MODEL}}})
vec = json.loads(sh("docker", "exec", "immich_server", "curl", "-sf", "-F", "entries=" + entries,
                    "-F", "text=" + DOG_TEXT, "http://immich_machine_learning:3003/predict"))["clip"]
assert vec.startswith("[") and vec.count(",") > 100, "bad embedding"

want = set(sql(f"""
select a.id from asset a
where a."ownerId"='{OWNER}' and a."deletedAt" is null and a.visibility='timeline'
  and a."localDateTime" >= '{SINCE}'
  and (exists (select 1 from asset_face f where f."assetId"=a.id and f."deletedAt" is null and f."isVisible")
       or exists (select 1 from smart_search s where s."assetId"=a.id and s.embedding <=> '{vec}'::vector < {DOG_MAX_DIST}));"""))
if len(want) < 1000:
    sys.exit(f"only {len(want)} matches; refusing to shrink the album (check ML/person data)")

albums = [a for a in api("GET", "/albums") if a["albumName"] == ALBUM]
album = albums[0]["id"] if albums else api("POST", "/albums", {"albumName": ALBUM,
    "description": "Filled nightly by /opt/immich/tv-screensaver/sync.py (any face or a dog, 2021+). Edits get overwritten."})["id"]
have = set(sql(f"""select "assetId" from album_asset where "albumId"='{album}';"""))

add, rem = sorted(want - have), sorted(have - want)
for i in range(0, len(add), 500):
    api("PUT", f"/albums/{album}/assets", {"ids": add[i:i+500]})
for i in range(0, len(rem), 500):
    api("DELETE", f"/albums/{album}/assets", {"ids": rem[i:i+500]})
print(f"album {album}: {len(want)} wanted, +{len(add)} -{len(rem)}")
