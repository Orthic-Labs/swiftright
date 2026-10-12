#!/usr/bin/env python3
"""Archive bounded CLI review output, identity & supervised terminal receipt."""
import datetime as dt
import hashlib
import json
from pathlib import Path

repo = Path(__file__).resolve().parents[3]
out = Path(__file__).resolve().parent / 'actual-r1'
logs = repo / '.factory-work/root-logs/fable-max-checkpoint-review-r1'

def read(path):
    if not path.is_file() or path.is_symlink() or path.stat().st_size > 1024 * 1024:
        raise RuntimeError('bounded regular review input required: ' + str(path))
    return path.read_bytes()

raw = read(logs / 'stdout.bin')
result = json.loads(raw)
invocation = json.loads(read(out / 'invocation.json'))
terminal = json.loads(read(out / 'terminal.json'))
supervision_raw = read(logs / 'receipt.json')
supervision = json.loads(supervision_raw)
assert result['is_error'] is False and result['subtype'] == 'success'
assert result['terminal_reason'] == 'completed' and result['permission_denials'] == []
assert result['session_id'] == invocation['sessionId'] == terminal['sessionId']
assert invocation['modelRequested'] == 'fable' and invocation['effortRequested'] == 'max'
assert terminal['exitCode'] == supervision['exitCode'] == 0
assert supervision['budgetFailure'] is None and supervision['ownedGroupQuiescent'] is True
assert supervision['quiescenceKnown'] is True
actual_models = list(result['modelUsage'])
assert actual_models and all(name.startswith('claude-fable-') for name in actual_models)
assert result['subagent_stats']['spawned'] == 0
for name, data in [('cli-result.json', raw), ('supervision.json', supervision_raw),
                   ('review.md', (result['result'] + '\n').encode())]:
    with (out / name).open('xb') as stream:
        stream.write(data)
ended = terminal['endedAt']
due = (dt.datetime.fromisoformat(ended) + dt.timedelta(hours=1)).isoformat()
ledger = {
    'kind': 'factory-checkpoint-review-ledger-v1', 'lastCompletedAt': ended,
    'nextActiveWorkReviewNoLaterThan': due, 'majorCheckpointReviewRequired': True,
    'majorCheckpoints': ['new original pilot block verified with paired20',
                         'five/ten/twenty cumulative cohort verified',
                         'SR0 qualification completion', 'material scope or delivery change'],
    'automationId': 'swiftright-fable-max-checkpoint-review',
    'reviewInProgress': False, 'latestSessionId': result['session_id'],
    'requestedModel': 'fable', 'requestedEffort': 'max', 'actualModels': actual_models,
    'latestReviewPath': str((out / 'review.md').relative_to(repo)),
    'resultHash': 'sha256:' + hashlib.sha256(raw).hexdigest(),
    'supervisionHash': 'sha256:' + hashlib.sha256(supervision_raw).hexdigest(),
    'verdict': 'at-risk', 'qualifiedOriginalPilotBlocks': 0,
    'peakGroupRssBytes': supervision['peakGroupRssBytes'], 'exitCode': 0,
    'ownedGroupQuiescent': True,
}
(out.parent / 'checkpoint-ledger.json').write_text(json.dumps(ledger, indent=2) + '\n')
print(json.dumps(ledger))
