"""Summarize observed DSP/LAPDm requests; never infer successful registration/calls."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re

REQUEST=re.compile(r'^DSP message=(\d+) opcode=([0-9a-f]+) sub=([0-9a-f]+) length=(\d+) payload=([0-9a-f]*)(\.\.\.)? cycle=(\d+)$')

def summarize(text):
    events=[]
    for line in text.splitlines():
        match=REQUEST.match(line)
        if not match:continue
        number,opcode,sub,length,prefix,truncated,cycle=match.groups()
        payload=bytes.fromhex(prefix)
        event=dict(message=int(number),opcode=int(opcode,16),cycle=int(cycle),
                   payload_length=int(length),captured_bytes=len(payload),
                   truncated=bool(truncated) or len(payload)<int(length))
        if int(length):event['sub']=int(sub,16)
        if event['opcode']==0x1b and len(payload)>=5:
            address,control,li=payload[2:5]
            event.update(logch=payload[1],sapi=(address>>2)&7,control=control,
                         information_length=li>>2,poll_final=bool(control&0x10))
            event['framing_valid']=bool(address&1 and li&1 and li>>2<=20 and int(length)>=5+(li>>2))
            if control&0xef==0x2f:
                event['lapdm']='SABM'
                # Only SABM begins a new information message; a later I-frame
                # may instead carry a continuation of an earlier segment.
                if len(payload)>=7:
                    event['initial_l3_pd']=payload[5]&15
                    event['initial_l3_type']=payload[6]
            elif control&0xef==0x43:event['lapdm']='DISC'
            elif control&15==1 and li==1:event.update(lapdm='RR',nr=control>>5)
            elif not control&1:event.update(lapdm='I',nr=control>>5,ns=(control>>1)&7,more=bool(li&2))
            else:event['lapdm']='other'
            event['information_prefix']=payload[5:5+(li>>2)].hex()
        events.append(event)
    return dict(events=events,opcode_counts=dict(Counter(f'{e["opcode"]:02x}' for e in events)),
                note='Observed requests only. This report does not establish registration, call success or SMS delivery.')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace',type=Path)
    parser.add_argument('--output',type=Path)
    args=parser.parse_args()
    result=json.dumps(summarize(args.trace.read_text(errors='replace')),indent=2)+'\n'
    if args.output:args.output.write_text(result)
    else:print(result,end='')
