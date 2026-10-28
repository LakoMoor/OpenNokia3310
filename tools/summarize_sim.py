"""Summarize synthetic SIM completion metadata from a ROM trace."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re

RESULT = re.compile(r'SIM RESULT ins=([0-9a-f]+) fid=([0-9a-f]+) sw=([0-9a-f]{4}) length=(\d+) offset=(\d+)', re.I)

def summarize(text):
    results = []
    for match in RESULT.finditer(text):
        ins, fid, sw, length, offset = match.groups()
        results.append(dict(instruction=ins.lower(), file=fid.lower(),
                            status=sw.lower(), length=int(length), offset=int(offset)))
    # 90xx and 9Fxx are normal completion/response-available statuses.
    errors = [item for item in results if item['status'][:2] not in ('90', '9f')]
    return dict(completions=len(results), statuses=dict(Counter(item['status'] for item in results)),
                non_success_responses=errors, last_response=results[-1] if results else None,
                interpretation='Observed responses only; phone acceptance is not inferred.')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace', type=Path)
    args = parser.parse_args()
    print(json.dumps(summarize(args.trace.read_text(errors='replace')), indent=2))
