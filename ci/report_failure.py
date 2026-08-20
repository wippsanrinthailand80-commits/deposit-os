#!/usr/bin/env python3
import json, os, urllib.request

sha = os.environ.get("GITHUB_SHA", "")
repo = os.environ.get("GITHUB_REPOSITORY", "")
tok = os.environ.get("GITHUB_TOKEN", "")

if not (sha and repo and tok):
    print("missing GITHUB_SHA/GITHUB_REPOSITORY/GITHUB_TOKEN; skipping report")
    raise SystemExit(0)

body = open("/tmp/err.md").read()[:3500]
data = json.dumps({"body": body}).encode()
url = "https://api.github.com/repos/%s/commits/%s/comments" % (repo, sha)
req = urllib.request.Request(
    url, data=data,
    headers={
        "Authorization": "Bearer " + tok,
        "Accept": "application/vnd.github+json",
        "Content-Type": "application/json",
    },
    method="POST",
)
print("posted failure comment:", urllib.request.urlopen(req).status)
