#!/usr/bin/env python3
"""Fetch the official LoL Esports schedule without an API token.

The public lolesports.com schedule page embeds its Apollo/GraphQL state in the
HTML. This script extracts the EventMatch objects from that page, filters the
worlds schedule for Invictus Gaming, and writes a small JSON cache that the
menu bar app reads.

Usage:
    python3 tools/fetch_schedule.py
    python3 tools/fetch_schedule.py --out ~/Desktop/ig-schedule.json
    python3 tools/fetch_schedule.py --team IG --league worlds
    python3 tools/fetch_schedule.py --print

No API key, token, cookie, or login is required.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

SCHEDULE_URL = "https://lolesports.com/schedule?leagueId=98767975604431411"
FALLBACK_URL = "https://lolesports.com/"
WORLDS_LEAGUE_ID = "98767975604431411"
DEFAULT_TEAM = "IG"
DEFAULT_OUT = Path.home() / "Library/Application Support/IGCheer/schedule.json"


def fetch(url: str) -> str:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
            ),
            "Accept": "text/html,application/xhtml+xml",
            "Accept-Encoding": "identity",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        raw = response.read()
    return raw.decode("utf-8", errors="replace")


def find_event_objects(html: str) -> list[dict]:
    """Return every JSON EventMatch object embedded in the page.

    The HTML is not a single JSON document; the same object shape can occur in
    Apollo SSR payloads and in smaller hydration chunks. A balanced-brace scan
    avoids depending on the surrounding script format.
    """
    marker = '{"__typename":"EventMatch"'
    events = {}
    cursor = 0
    while True:
        marker_at = html.find(marker, cursor)
        if marker_at < 0:
            break
        start = marker_at
        depth = 0
        in_string = False
        escaped = False
        end = None
        for index in range(start, len(html)):
            char = html[index]
            if in_string:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == '"':
                    in_string = False
                continue
            if char == '"':
                in_string = True
            elif char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    end = index + 1
                    break
        if end is None:
            break
        try:
            event = json.loads(html[start:end])
        except json.JSONDecodeError:
            cursor = start + len(marker)
            continue
        if event.get("__typename") == "EventMatch" and event.get("id"):
            events[event["id"]] = event
        cursor = end
    return list(events.values())


def best_of(event: dict) -> int:
    strategy = (event.get("match") or {}).get("strategy") or {}
    try:
        return int(strategy.get("count") or 0)
    except (TypeError, ValueError):
        return 0


def parse_event(event: dict, team_code: str) -> dict | None:
    teams = event.get("matchTeams") or []
    if not any((team.get("code") or "").upper() == team_code.upper() for team in teams):
        return None

    league = event.get("league") or {}
    tournament = event.get("tournament") or {}
    normalized_teams = []
    for team in teams:
        result = team.get("result") or {}
        normalized_teams.append(
            {
                "code": team.get("code") or "",
                "name": team.get("name") or team.get("code") or "",
                "gameWins": result.get("gameWins"),
                "outcome": result.get("outcome"),
            }
        )

    start = event.get("startTime") or ""
    return {
        "id": str(event.get("id")),
        "startTime": start,
        "state": event.get("state") or "unstarted",
        "stage": event.get("blockName") or "",
        "league": league.get("name") or "",
        "leagueSlug": league.get("slug") or "",
        "tournament": tournament.get("name") or "",
        "bestOf": best_of(event),
        "teams": normalized_teams,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Fetch IG's official LoL Esports schedule.")
    parser.add_argument("--team", default=DEFAULT_TEAM, help="team code (default: IG)")
    parser.add_argument(
        "--league",
        default="worlds",
        help="league slug to keep, or 'all' (default: worlds)",
    )
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="output JSON path")
    parser.add_argument("--print", action="store_true", dest="print_only", help="print only, do not write")
    parser.add_argument("--url", default=SCHEDULE_URL, help="schedule page URL")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    html = ""
    last_error = None
    for url in (args.url, FALLBACK_URL):
        try:
            html = fetch(url)
            if '{"__typename":"EventMatch"' in html:
                break
            last_error = RuntimeError(f"no schedule data in {url}")
        except Exception as exc:  # noqa: BLE001 - surface network failures plainly
            last_error = exc
    if not html:
        print(f"ERROR: could not load lolesports schedule: {last_error}", file=sys.stderr)
        return 1

    events = find_event_objects(html)
    if not events:
        print("ERROR: schedule page loaded, but no EventMatch objects were found", file=sys.stderr)
        return 2

    matches = []
    for event in events:
        parsed = parse_event(event, args.team)
        if not parsed:
            continue
        if args.league != "all" and parsed["leagueSlug"].lower() != args.league.lower():
            continue
        matches.append(parsed)

    matches.sort(key=lambda match: match.get("startTime") or "")
    payload = {
        "version": 1,
        "source": args.url,
        "fetchedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "team": args.team.upper(),
        "league": args.league,
        "matches": matches,
    }

    if args.print_only:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        try:
            os.chmod(args.out, 0o600)
        except OSError:
            pass
        print(f"Wrote {len(matches)} {args.team.upper()} match(es) to {args.out}")

    if not matches:
        print(f"No {args.team.upper()} matches found for league={args.league}.", file=sys.stderr)
        return 3

    for match in matches:
        opponents = [t for t in match["teams"] if t["code"].upper() != args.team.upper()]
        opponent = opponents[0]["code"] if opponents else "TBD"
        print(f'{match["startTime"]}  {match["stage"] or "Worlds"}  {args.team.upper()} vs {opponent}  BO{match["bestOf"]}')
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
