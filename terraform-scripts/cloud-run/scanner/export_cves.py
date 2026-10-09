import csv
import io
import logging
import os
import re
import sys
from datetime import datetime, timezone
from urllib.parse import quote

import google.auth
from google.auth.transport.requests import AuthorizedSession


LOG = logging.getLogger("cve-exporter")
API_BASE = "https://artifactregistry.googleapis.com/v1"
ANALYSIS_BASE = "https://containeranalysis.googleapis.com/v1"
GCS_UPLOAD_BASE = "https://storage.googleapis.com/upload/storage/v1"
CVE_PATTERN = re.compile(r"\bCVE-\d{4}-\d{4,}\b", re.IGNORECASE)
CSV_COLUMNS = [
    "collected_at_utc",
    "image_uri",
    "cve_id",
    "severity",
    "effective_severity",
    "cvss_score",
    "package",
    "installed_version",
    "fixed_version",
    "description",
    "references",
]


def get_required_env(name):
    value = os.environ.get(name, "").strip()
    if not value:
        raise ValueError(f"Required environment variable {name} is not set")
    return value


def get_all_pages(session, url, params, response_key):
    items = []
    page_token = None
    while True:
        request_params = dict(params)
        if page_token:
            request_params["pageToken"] = page_token
        response = session.get(url, params=request_params, timeout=60)
        response.raise_for_status()
        payload = response.json()
        items.extend(payload.get(response_key, []))
        page_token = payload.get("nextPageToken")
        if not page_token:
            return items


def list_images(session, project_id, location, repository):
    parent = (
        f"projects/{quote(project_id, safe='')}/locations/{quote(location, safe='')}"
        f"/repositories/{quote(repository, safe='')}"
    )
    return get_all_pages(
        session,
        f"{API_BASE}/{parent}/dockerImages",
        {"pageSize": 1000},
        "dockerImages",
    )


def list_vulnerabilities(session, project_id, image_uri):
    filter_value = f'kind="VULNERABILITY" AND resourceUrl="{image_uri}"'
    return get_all_pages(
        session,
        f"{ANALYSIS_BASE}/projects/{quote(project_id, safe='')}/occurrences",
        {"filter": filter_value, "pageSize": 1000},
        "occurrences",
    )


def occurrence_rows(occurrence, image_uri, collected_at):
    vulnerability = occurrence.get("vulnerability", {})
    references = [
        item.get("url", "")
        for item in vulnerability.get("relatedUrls", [])
        if item.get("url")
    ]
    text_to_search = " ".join(
        [
            vulnerability.get("shortDescription", ""),
            vulnerability.get("longDescription", ""),
            " ".join(references),
        ]
    )
    cve_ids = sorted({value.upper() for value in CVE_PATTERN.findall(text_to_search)})
    if not cve_ids:
        return []

    package_issues = vulnerability.get("packageIssue", [])
    if not package_issues:
        package_issues = [{}]

    rows = []
    for cve_id in cve_ids:
        for issue in package_issues:
            affected = issue.get("affectedVersion", {})
            fixed = issue.get("fixedVersion", {})
            rows.append(
                {
                    "collected_at_utc": collected_at,
                    "image_uri": image_uri,
                    "cve_id": cve_id,
                    "severity": vulnerability.get("severity", ""),
                    "effective_severity": vulnerability.get("effectiveSeverity", ""),
                    "cvss_score": vulnerability.get("cvssScore", ""),
                    "package": issue.get("affectedPackage", ""),
                    "installed_version": affected.get("name", ""),
                    "fixed_version": fixed.get("name", ""),
                    "description": vulnerability.get("shortDescription", ""),
                    "references": " ".join(references),
                }
            )
    return rows


def upload_csv(session, bucket, object_name, contents):
    encoded_object_name = quote(object_name, safe="")
    url = (
        f"{GCS_UPLOAD_BASE}/b/{quote(bucket, safe='')}/o"
        f"?uploadType=media&name={encoded_object_name}"
    )
    response = session.post(
        url,
        data=contents.encode("utf-8"),
        headers={"Content-Type": "text/csv; charset=utf-8"},
        timeout=120,
    )
    response.raise_for_status()
    return response.json().get("name", object_name)


def main():
    project_id = get_required_env("GCP_PROJECT_ID")
    location = get_required_env("GAR_LOCATION")
    repository = get_required_env("GAR_REPOSITORY")
    bucket = get_required_env("GCS_BUCKET")
    prefix = os.environ.get("GCS_PREFIX", "cve-findings").strip("/")

    credentials, _ = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    session = AuthorizedSession(credentials)
    collected_at_dt = datetime.now(timezone.utc)
    collected_at = collected_at_dt.isoformat(timespec="seconds").replace("+00:00", "Z")
    rows = []

    images = list_images(session, project_id, location, repository)
    LOG.info("Found %d Artifact Registry image digests", len(images))
    for image in images:
        image_uri = image.get("uri")
        if not image_uri:
            LOG.warning("Skipping Artifact Registry image without a URI: %s", image.get("name"))
            continue

        occurrences = list_vulnerabilities(session, project_id, image_uri)
        for occurrence in occurrences:
            rows.extend(occurrence_rows(occurrence, image_uri, collected_at))

    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=CSV_COLUMNS, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    filename = f"cves-{collected_at_dt.strftime('%Y%m%dT%H%M%SZ')}.csv"
    object_name = f"{prefix}/{collected_at_dt:%Y/%m/%d}/{filename}" if prefix else filename
    uploaded_name = upload_csv(session, bucket, object_name, output.getvalue())
    LOG.info(
        "Uploaded %d CVE/package rows to gs://%s/%s",
        len(rows),
        bucket,
        uploaded_name,
    )


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    try:
        main()
    except Exception:
        LOG.exception("CVE export failed")
        sys.exit(1)
