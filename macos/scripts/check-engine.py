"""Real-engine regression checks; requires the user's installed supported game.
No engine resources are copied to the app. Reports stay in ignored .build/.
"""
import argparse
import json
from pathlib import Path
import subprocess
import time

p=argparse.ArgumentParser()
p.add_argument('app',type=Path)
p.add_argument('--helper',type=Path,default=Path(__file__).resolve().parents[1]/'dist/FM Tactics Lab 0.5.app/Contents/MacOS/EngineRuntimeProbe')
a=p.parse_args()
root=Path(__file__).resolve().parents[1]
out=root/'.build/evidence-v04';out.mkdir(parents=True,exist_ok=True)
reports=[]
for i,seed in enumerate([1131885006,1,1,2,3,4,5,4294967295,0]):
    run=subprocess.run([str(a.helper),str(a.app),'--seed',str(seed)],capture_output=True,timeout=60)
    (out/f'match-{i}-seed-{seed}.jsonl').write_bytes(run.stdout)
    (out/f'match-{i}-seed-{seed}.stderr.txt').write_bytes(run.stderr)
    rows=[json.loads(line) for line in run.stdout.splitlines()]
    assert run.returncode==0,(run.returncode,rows[-1] if rows else run.stderr)
    final=rows[-1]
    assert final['event']=='natural_match_finished' and final['fullMatchCompleted']
    assert final['clock']>=21600 and final['tick']<47996 and final['flags']&4
    assert final['seed']==seed and final['source']=='fm_original_engine' and not final['workbenchApplied']
    stats=next(r for r in rows if r['event']=='native_match_statistics')
    assert stats['totalsVerified'] and len(stats['players'])==40
    progress=[r for r in rows if r['event']=='native_match_progress']
    assert progress[-1]['tick']==final['tick'] and progress[-1]['score']==final['score']
    reports.append((final,stats,progress))
    print('PASS original match',seed,final['score'],round(final['clock']/240,2),'minutes',round(final['elapsedSeconds'],2),'seconds',flush=True)
assert reports[1][1:]==reports[2][1:], 'same seed statistics or progress changed'
assert len({tuple(r[0]['score']) for r in reports})>1,'seed inputs did not change outputs'
# Unsupported/missing binary never produces a valid match.
missing=subprocess.run([str(a.helper),str(out/'missing.app'),'--seed','1'],capture_output=True,timeout=60)
(out/'missing-engine.jsonl').write_bytes(missing.stdout)
assert missing.returncode!=0 and b'natural_match_finished' not in missing.stdout
# Cancellation affects only our owned helper, and cannot be accepted as a match.
with (out/'cancelled.jsonl').open('wb') as stream:
    child=subprocess.Popen([str(a.helper),str(a.app),'--seed','9'],stdout=stream,stderr=subprocess.DEVNULL)
    time.sleep(.05);child.terminate();child.wait(timeout=5)
assert child.returncode!=0 and b'natural_match_finished' not in (out/'cancelled.jsonl').read_bytes()
summary={'completedMatches':len(reports),'sameSeedIdentical':True,'differentSeedsVary':True,'missingEngineRejected':True,'cancelledRunRejected':True,'engineSource':'original_installed_game','inputs':'bundled_test_fixture','workbenchApplied':False}
(out/'summary.json').write_text(json.dumps(summary,indent=2))
print(json.dumps(summary))
