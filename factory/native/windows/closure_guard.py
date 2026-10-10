"""Exact immutable tuple10 closure receipt guard shared by factory producers."""
from datetime import datetime, timezone
import json
from pathlib import Path
import re
from factory.core.artifacts import file_hash

def validate(status: Path, receipt: Path) -> dict:
    overall=re.findall(r'^\*\*Overall:\s*(.+?)\*\*',status.read_text(),re.M)
    if len(overall)!=1 or not re.match(r'SR0 is CLOSED\b',overall[0]) or not re.search(r'tuple\s*0?10\b',overall[0],re.I):
        raise ValueError('unique Overall CLOSED tuple10 declaration required')
    value=json.loads(receipt.read_text())
    def synthetic(v):
        if isinstance(v,dict):return v.get('synthetic') is True or v.get('producer')=='test-fixture' or any(synthetic(x) for x in v.values())
        return isinstance(v,list) and any(synthetic(x) for x in v)
    if synthetic(value):raise ValueError('synthetic closure receipt rejected')
    if value.get('tuple')!='10' or value.get('decision')!='CLOSED' or value.get('statusHash')!=file_hash(status):
        raise ValueError('exact CLOSED tuple10 status receipt binding required')
    stamp=value.get('closedAt')
    if not isinstance(stamp,str) or not stamp.endswith('Z'):raise ValueError('explicit UTC closure timestamp required')
    at=datetime.fromisoformat(stamp[:-1]+'+00:00')
    if at>datetime.now(timezone.utc):raise ValueError('future closure timestamp rejected')
    return value
