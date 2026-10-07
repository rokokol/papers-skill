#!/usr/bin/env python3
"""Save the open-access full text of a biomedical paper from PMC, and print its path.

Usage: pmc_text.py [-o DIR] ID

ID is a PMID (digits), a PMCID (PMC followed by digits) or a DOI. Europe PMC's search
names the article's PMCID. The text then comes from PMC's open-access dataset on AWS,
the plain-text file of the article's latest version. When the dataset holds no such
file, the Europe PMC full-text XML stands in, if it carries the article's body. The file
lands in DIR (default: the current directory), and its path is the one line on stdout.

Needs Python 3.9 and its standard library only.

Exit 0 with the path; 1 when the paper has no open-access full text in either place, or
a service could not be reached, with the reason on stderr; 2 on a usage error.
"""

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import quote

EPMC = "https://www.ebi.ac.uk/europepmc/webservices/rest"
BUCKET = "https://pmc-oa-opendata.s3.amazonaws.com"
TIMEOUT = 60
AGENT = "papers-skill pmc_text.py (https://github.com/rokokol/papers-skill)"


class NoFullText(Exception):
    """The paper has no open-access full text in PMC or Europe PMC."""


class Unreachable(Exception):
    """A service refused or failed, which says nothing about the paper."""


def fetch(url: str) -> tuple[int, bytes]:
    """GET a URL; an HTTP error is a status, not an exception."""
    request = urllib.request.Request(url, headers={"User-Agent": AGENT})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()
    except (urllib.error.URLError, TimeoutError) as exc:
        raise Unreachable(f"could not reach {url}: {exc}") from exc


def query_for(ident: str) -> str:
    """The Europe PMC search query that finds one article by its identifier."""
    ident = ident.strip()
    if re.fullmatch(r"\d+", ident):
        return f"EXT_ID:{ident} AND SRC:MED"
    if re.fullmatch(r"(?i)pmc\d+", ident):
        return f"PMCID:{ident.upper()}"
    if re.fullmatch(r"10\.\d{4,}/\S+", ident):
        return f'DOI:"{ident}"'
    raise ValueError(f"{ident!r} is not a PMID, a PMCID or a DOI")


def resolve(ident: str) -> str:
    """The PMCID of the article, or NoFullText when it has none."""
    url = f"{EPMC}/search?query={quote(query_for(ident))}&format=json&resultType=lite"
    status, body = fetch(url)
    if status != 200:
        raise Unreachable(f"Europe PMC search answered {status} for {ident}")
    results = json.loads(body).get("resultList", {}).get("result", [])
    pmcid = results[0].get("pmcid", "") if results else ""
    if not pmcid:
        raise NoFullText(f"Europe PMC knows no PMC copy of {ident}")
    return pmcid


def latest_text_key(pmcid: str) -> str:
    """The bucket key of the newest version's plain text, or "" when there is none.

    A version is a key prefix PMCID.N/, and N grows with each revision, so the largest
    one is current. A listing holds at most 1000 keys and figures count among them, so
    every page is read
    """
    pattern = re.compile(rf"^{re.escape(pmcid)}\.(\d+)/{re.escape(pmcid)}\.\1\.txt$")
    best, best_version, token = "", -1, ""
    while True:
        url = f"{BUCKET}/?list-type=2&prefix={quote(pmcid + '.')}"
        if token:
            url += f"&continuation-token={quote(token)}"
        status, body = fetch(url)
        if status != 200:
            raise Unreachable(f"the PMC bucket answered {status} to a listing of {pmcid}")
        page = body.decode()
        for key in re.findall(r"<Key>([^<]+)</Key>", page):
            match = pattern.match(key)
            if match and int(match.group(1)) > best_version:
                best, best_version = key, int(match.group(1))
        more = re.search(r"<NextContinuationToken>([^<]+)</NextContinuationToken>", page)
        if "<IsTruncated>true</IsTruncated>" not in page or not more:
            return best
        token = more.group(1)


def full_text(ident: str, out_dir: Path) -> Path:
    """Save the full text of the article in out_dir and return the file's path."""
    pmcid = resolve(ident)
    key = latest_text_key(pmcid)
    if key:
        status, body = fetch(f"{BUCKET}/{key}")
        if status == 200 and body.strip():
            return save(out_dir / key.rsplit("/", 1)[1], body)
    status, body = fetch(f"{EPMC}/{pmcid}/fullTextXML")
    # A record with no body is the front matter alone: title, authors, the abstract
    if status == 200 and re.search(rb"<body[\s>]", body):
        return save(out_dir / f"{pmcid}.xml", body)
    raise NoFullText(f"{pmcid} has no open-access full text in PMC or Europe PMC")


def save(path: Path, body: bytes) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(body)
    return path


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="pmc_text.py",
        description="Save the open-access full text of a biomedical paper from PMC, and print its path.",
    )
    parser.add_argument("-o", "--out", default=".", help="the directory the file lands in")
    parser.add_argument("id", help="a PMID, a PMCID or a DOI")
    args = parser.parse_args(argv[1:])
    try:
        query_for(args.id)
    except ValueError as exc:
        parser.error(str(exc))
    try:
        print(full_text(args.id, Path(args.out).expanduser()))
    except (NoFullText, Unreachable) as exc:
        print(f"pmc_text.py: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
