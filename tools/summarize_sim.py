"""Summarize synthetic SIM completion metadata from a ROM trace."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re

RESULT = re.compile(r'SIM RESULT ins=([0-9a-f]+) fid=([0-9a-f]+) sw=([0-9a-f]{4}) length=(\d+) offset=(\d+)(?: p1=([0-9a-f]+) p2=([0-9a-f]+) p3=([0-9a-f]+))?', re.I)

def summarize(text):
    results = []
    for match in RESULT.finditer(text):
        ins, fid, sw, length, offset, p1, p2, p3 = match.groups()
        item = dict(instruction=ins.lower(), file=fid.lower(),
                    status=sw.lower(), length=int(length), offset=int(offset))
        if p1 is not None:
            item['parameters'] = dict(p1=p1.lower(), p2=p2.lower(), p3=p3.lower())
        results.append(item)
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
