#!/usr/bin/env python3
"""Gives the build number of the next upload of the app, for the release workflow on GitHub.

The number is one more than the highest of:
- every build number that App Store Connect holds for the app: its builds of all versions, expired ones included, and
  its build uploads, which also list an upload that Apple refused or failed to process;
- the build of every tag builds/<version>/<build> of the repo.
So a run started again after a refused upload takes the next number, and a number is never used twice.
One counter for the whole app, never reset at a new version: the token list of the server names a build by its
number alone.
The version is MARKETING_VERSION of ios/Config/Base.xcconfig: the run reads it, and never changes it.

It calls App Store Connect with a token that it signs with the API key (ES256, by openssl), and it never prints the
token, nor sends it to another host than the one of the API.
It prints one line, and writes build=<n> and version=<x.y.z> to GITHUB_OUTPUT when it is set.
"""
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Callable, Dict, Iterable, List, Optional, Tuple

USAGE = """Usage: release-build-number.py next --key-file <AuthKey.p8> [--repo <folder>] [--api <base URL>]
       Reads the key ID and the issuer ID from APP_STORE_CONNECT_KEY_ID and APP_STORE_CONNECT_ISSUER_ID.
       --repo: the repo whose tags and version it reads (default: the repo of this script).
       --api: the base URL of the App Store Connect API (default: the real one; the script test uses a fake server)."""

API = "https://api.appstoreconnect.apple.com"
# Apple refuses a token that lives longer than 20 minutes.
TOKEN_SECONDS = 15 * 60
PAGE = 200
TAG = re.compile(r"^builds/[^/]+/(.+)$")
NUMBER = re.compile(r"^[0-9]+$")


class Refused(Exception):
    """A reason to give no number: a person must look first."""


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    """The DER signature of openssl (SEQUENCE of two INTEGERs) as the 64 bytes r || s that a JWT carries."""
    if len(der) < 8 or der[0] != 0x30:
        raise Refused("openssl gave no ECDSA signature")
    at = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    parts = []
    for _ in range(2):
        if der[at] != 0x02:
            raise Refused("openssl gave no ECDSA signature")
        length = der[at + 1]
        value = der[at + 2:at + 2 + length]
        parts.append(int.from_bytes(value, "big").to_bytes(32, "big"))
        at += 2 + length
    return parts[0] + parts[1]


def token(key_id: str, issuer_id: str, key_file: Path, now: int) -> str:
    """The token of Apple's page "Generating Tokens for API Requests", signed with the private key of key_file."""
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}, separators=(",", ":")).encode())
    claims = {"iss": issuer_id, "iat": now, "exp": now + TOKEN_SECONDS, "aud": "appstoreconnect-v1"}
    payload = b64url(json.dumps(claims, separators=(",", ":")).encode())
    signing_input = f"{header}.{payload}".encode()
    signed = subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(key_file)], input=signing_input,
                            capture_output=True)
    if signed.returncode != 0:
        raise Refused("openssl could not sign with the API key file: is it the .p8 file of the key?")
    return f"{header}.{payload}.{b64url(der_to_raw(signed.stdout))}"


class Api:
    """Reads the pages of App Store Connect, with the token only on the host of the API."""

    def __init__(self, base: str, bearer: str):
        self.base = base.rstrip("/")
        self.origin = urllib.parse.urlsplit(self.base)[:2]
        self.bearer = bearer

    def get(self, url: str) -> dict:
        if urllib.parse.urlsplit(url)[:2] != self.origin:
            raise Refused("App Store Connect gave a next page on another host: the token goes to its own host only")
        request = urllib.request.Request(url, headers={"Authorization": f"Bearer {self.bearer}"})
        try:
            with urllib.request.urlopen(request, timeout=60) as answer:
                return json.load(answer)
        except urllib.error.HTTPError as error:
            raise Refused(f"App Store Connect answered {error.code} to {urllib.parse.urlsplit(url).path}: "
                          f"{apple_error(error)}") from None
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
            raise Refused(f"App Store Connect could not be read: {error}") from None

    def all(self, path: str, query: Dict[str, str]) -> List[dict]:
        url: Optional[str] = f"{self.base}{path}?{urllib.parse.urlencode(query)}"
        items: List[dict] = []
        while url:
            page = self.get(url)
            items.extend(page.get("data") or [])
            url = (page.get("links") or {}).get("next")
        return items


def apple_error(error: urllib.error.HTTPError) -> str:
    """The title and the detail of Apple's error, which name no value of the key."""
    try:
        errors = json.load(error).get("errors") or [{}]
        first = errors[0]
        return " ".join(part for part in (first.get("title"), first.get("detail")) if part) or "no detail"
    except (json.JSONDecodeError, AttributeError, ValueError):
        return "no detail"


def number_of(text: object, where: str) -> int:
    """A build number of one integer, as every build of the app has; any other form stops the run."""
    if not isinstance(text, str) or not NUMBER.match(text):
        raise Refused(f"{where} has the build number {text!r}, which is not one integer: "
                      "a person looks before the next number is taken")
    return int(text)


def tag_numbers(tags: Iterable[str]) -> List[int]:
    numbers = []
    for tag in tags:
        match = TAG.match(tag)
        if match:
            numbers.append(number_of(match.group(1), f"the tag {tag}"))
    return numbers


def app_id(api: Api, bundle_id: str) -> str:
    apps = api.all("/v1/apps", {"filter[bundleId]": bundle_id, "fields[apps]": "bundleId", "limit": str(PAGE)})
    ids = [app.get("id") for app in apps if (app.get("attributes") or {}).get("bundleId") == bundle_id]
    if len(ids) != 1 or not ids[0]:
        raise Refused(f"App Store Connect has {len(ids)} apps with the bundle ID {bundle_id}, not one")
    return ids[0]


def apple_numbers(api: Api, app: str) -> Tuple[List[int], List[int]]:
    """The build numbers of every build of the app (all versions, expired ones included: no filter on them), and of
    every build upload (an upload that Apple refused or failed to process is in this list, not always in the first)."""
    builds = api.all("/v1/builds", {"filter[app]": app, "fields[builds]": "version,expired", "limit": str(PAGE)})
    uploads = api.all(f"/v1/apps/{app}/buildUploads",
                      {"fields[buildUploads]": "cfBundleVersion,state", "limit": str(PAGE)})
    return ([number_of((build.get("attributes") or {}).get("version"), "a build of App Store Connect")
             for build in builds],
            [number_of((upload.get("attributes") or {}).get("cfBundleVersion"), "an upload of App Store Connect")
             for upload in uploads])


def next_number(builds: List[int], uploads: List[int], tags: List[int]) -> int:
    return max(builds + uploads + tags + [0]) + 1


def setting(path: Path, name: str) -> str:
    match = re.search(rf"^{name} = (\S+)\s*$", path.read_text(), re.MULTILINE)
    if not match:
        raise Refused(f"{path.name} has no {name}")
    return match.group(1)


def release_bundle_id(project: Path) -> str:
    """APP_BUNDLE_ID of the Release configuration of ios/project.yml: the one value with no $( in it."""
    ids = re.findall(r"^\s+APP_BUNDLE_ID: ([A-Za-z0-9.-]+)\s*$", project.read_text(), re.MULTILINE)
    if len(ids) != 1:
        raise Refused("ios/project.yml has no single App Store ID in APP_BUNDLE_ID")
    return ids[0]


def git_tags(repo: Path) -> List[str]:
    listed = subprocess.run(["git", "-C", str(repo), "tag", "--list", "builds/*"], capture_output=True, text=True)
    if listed.returncode != 0:
        raise Refused(f"git could not list the tags: {listed.stderr.strip()}")
    return listed.stdout.split()


def run(repo: Path, key_file: Path, base: str, environ: Dict[str, str],
        now: Callable[[], float] = time.time) -> Tuple[str, int, str]:
    key_id = environ.get("APP_STORE_CONNECT_KEY_ID", "")
    issuer_id = environ.get("APP_STORE_CONNECT_ISSUER_ID", "")
    if not key_id or not issuer_id:
        raise Refused("APP_STORE_CONNECT_KEY_ID or APP_STORE_CONNECT_ISSUER_ID is empty")
    if not key_file.is_file():
        raise Refused(f"no API key file at {key_file}")
    version = setting(repo / "ios/Config/Base.xcconfig", "MARKETING_VERSION")
    bundle_id = release_bundle_id(repo / "ios/project.yml")
    tags = tag_numbers(git_tags(repo))
    api = Api(base, token(key_id, issuer_id, key_file, int(now())))
    builds, uploads = apple_numbers(api, app_id(api, bundle_id))
    number = next_number(builds, uploads, tags)
    line = (f"Build number {number} of {bundle_id} {version}: Apple's highest is {max(builds + uploads + [0])} "
            f"({len(builds)} builds and {len(uploads)} uploads of all versions), "
            f"the highest builds/ tag is {max(tags + [0])}")
    return version, number, line


def main(argv: List[str]) -> int:
    if len(argv) < 1 or argv[0] != "next":
        print(USAGE, file=sys.stderr)
        return 2
    options = dict(zip(argv[1::2], argv[2::2]))
    if len(argv[1:]) % 2 or set(options) - {"--key-file", "--repo", "--api"} or "--key-file" not in options:
        print(USAGE, file=sys.stderr)
        return 2
    repo = Path(options.get("--repo", Path(__file__).resolve().parents[2]))
    try:
        version, number, line = run(repo, Path(options["--key-file"]), options.get("--api", API), dict(os.environ))
    except Refused as reason:
        print(f"release-build-number: no number: {reason}", file=sys.stderr)
        return 1
    print(line)
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a") as file:
            file.write(f"build={number}\nversion={version}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
