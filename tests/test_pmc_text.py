"""tools/pmc_text.py against canned answers: no request leaves the machine.

Run: python3 -m unittest discover -s tests -p 'test_*.py'
"""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from urllib.parse import quote

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("pmc_text", HERE.parent / "tools" / "pmc_text.py")
assert spec is not None and spec.loader is not None
pmc_text = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pmc_text)

EPMC = pmc_text.EPMC
BUCKET = pmc_text.BUCKET


def search_url(query: str) -> str:
    return f"{EPMC}/search?query={quote(query)}&format=json&resultType=lite"


def search_answer(*pmcids: str) -> bytes:
    return json.dumps({"resultList": {"result": [{"pmcid": p} if p else {} for p in pmcids]}}).encode()


def listing_url(pmcid: str, token: str = "") -> str:
    url = f"{BUCKET}/?list-type=2&prefix={quote(pmcid + '.')}"
    return url + (f"&continuation-token={quote(token)}" if token else "")


def listing(keys: list[str], next_token: str = "") -> bytes:
    body = "".join(f"<Contents><Key>{k}</Key></Contents>" for k in keys)
    if next_token:
        body += f"<IsTruncated>true</IsTruncated><NextContinuationToken>{next_token}</NextContinuationToken>"
    else:
        body += "<IsTruncated>false</IsTruncated>"
    return f"<ListBucketResult>{body}</ListBucketResult>".encode()


class Fake:
    """A fetch that answers from a table and records every URL it was asked for."""

    def __init__(self, answers: dict[str, tuple[int, bytes]]):
        self.answers = answers
        self.asked: list[str] = []

    def __call__(self, url: str) -> tuple[int, bytes]:
        self.asked.append(url)
        return self.answers.get(url, (404, b"<Error><Code>NoSuchKey</Code></Error>"))


class FullText(unittest.TestCase):
    def setUp(self):
        self.out = Path(tempfile.mkdtemp())
        self.real_fetch = pmc_text.fetch

    def tearDown(self):
        setattr(pmc_text, "fetch", self.real_fetch)

    def run_with(self, answers, ident):
        setattr(pmc_text, "fetch", Fake(answers))
        return pmc_text.full_text(ident, self.out)

    def test_the_latest_version_of_the_text_is_saved(self):
        # The newest version sits in the middle, and sorts before .2 as a string
        keys = [
            "PMC1.1/PMC1.1.pdf",
            "PMC1.1/PMC1.1.txt",
            "PMC1.10/PMC1.10.txt",
            "PMC1.2/fig1.jpg",
            "PMC1.2/PMC1.2.txt",
        ]
        path = self.run_with(
            {
                search_url("EXT_ID:123 AND SRC:MED"): (200, search_answer("PMC1")),
                listing_url("PMC1"): (200, listing(keys)),
                f"{BUCKET}/PMC1.10/PMC1.10.txt": (200, b"the whole paper"),
            },
            "123",
        )
        self.assertEqual(Path(path).read_bytes(), b"the whole paper")
        self.assertEqual(Path(path).parent, self.out)

    def test_a_listing_is_read_past_its_first_page(self):
        path = self.run_with(
            {
                search_url("PMCID:PMC2"): (200, search_answer("PMC2")),
                listing_url("PMC2"): (200, listing(["PMC2.1/fig.jpg"], next_token="t/1")),
                listing_url("PMC2", "t/1"): (200, listing(["PMC2.1/PMC2.1.txt"])),
                f"{BUCKET}/PMC2.1/PMC2.1.txt": (200, b"text"),
            },
            "PMC2",
        )
        self.assertEqual(Path(path).read_bytes(), b"text")

    def test_europe_pmc_xml_stands_in_when_the_bucket_has_no_text(self):
        path = self.run_with(
            {
                search_url('DOI:"10.1000/x"'): (200, search_answer("PMC3")),
                listing_url("PMC3"): (200, listing([])),
                f"{EPMC}/PMC3/fullTextXML": (200, b"<article><front/><body><p>text</p></body></article>"),
            },
            "10.1000/x",
        )
        self.assertIn(b"<body>", Path(path).read_bytes())

    def test_xml_without_a_body_is_not_full_text(self):
        with self.assertRaises(pmc_text.NoFullText):
            self.run_with(
                {
                    search_url("PMCID:PMC4"): (200, search_answer("PMC4")),
                    listing_url("PMC4"): (200, listing([])),
                    f"{EPMC}/PMC4/fullTextXML": (200, b"<article><front/></article>"),
                },
                "PMC4",
            )
        self.assertEqual(list(self.out.iterdir()), [])

    def test_an_empty_text_file_is_not_full_text(self):
        with self.assertRaises(pmc_text.NoFullText):
            self.run_with(
                {
                    search_url("PMCID:PMC6"): (200, search_answer("PMC6")),
                    listing_url("PMC6"): (200, listing(["PMC6.1/PMC6.1.txt"])),
                    f"{BUCKET}/PMC6.1/PMC6.1.txt": (200, b" \n"),
                },
                "PMC6",
            )

    def test_an_article_with_no_pmc_copy_is_said_so(self):
        with self.assertRaisesRegex(pmc_text.NoFullText, "no PMC copy"):
            self.run_with({search_url("EXT_ID:5 AND SRC:MED"): (200, search_answer(""))}, "5")

    def test_a_refused_search_is_not_an_absent_copy(self):
        with self.assertRaises(pmc_text.Unreachable):
            self.run_with({search_url("EXT_ID:7 AND SRC:MED"): (503, b"busy")}, "7")


class Identifiers(unittest.TestCase):
    def test_each_form_maps_to_its_query(self):
        self.assertEqual(pmc_text.query_for("32015507"), "EXT_ID:32015507 AND SRC:MED")
        self.assertEqual(pmc_text.query_for("pmc7095418"), "PMCID:PMC7095418")
        self.assertEqual(pmc_text.query_for("10.1038/s41586-020-2012-7"), 'DOI:"10.1038/s41586-020-2012-7"')

    def test_anything_else_is_refused(self):
        for bad in ("", "arXiv:2212.04356", "PMC", "10.1038"):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                pmc_text.query_for(bad)


if __name__ == "__main__":
    unittest.main()
