"""Opt-in DAT integration checks; source files remain read-only.

Run with the SaveReader build venv: check-database.py <2700_fm> <output-dir>
The output contains private game data and must not be committed or packaged.
"""
from pathlib import Path
import hashlib,json,sys,tempfile
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'runtime'))
from DatabaseReader import load,frame,FILES

root=Path(sys.argv[1]);output=Path(sys.argv[2]);output.mkdir(parents=True,exist_ok=True)
def hashes():return {n:hashlib.sha256((root/n).read_bytes()).hexdigest() for n in FILES}
before=hashes();catalog=load(root,set())
league=next(l for l in catalog['leagues'] if l['competitionID']==11)
assert len(league['clubIDs'])==20
rosters=load(root,set(league['clubIDs']),catalog['sourceSHA256'])
again=load(root,set(league['clubIDs']),catalog['sourceSHA256'])
assert rosters==again,'DAT initialization changed on reimport'
assert {r['clubID'] for r in rosters['rosters']}==set(league['clubIDs'])
for team in rosters['rosters']:
    assert len({p['uid'] for p in team['players']})==len(team['players'])>=11
    for p in team['players']:
        assert p['name'] and p['unique_id']==p['uid'] and len(p['positions'])==15
        assert len(p['raw_attributes'])==52 and all(5<=v<=100 for v in p['raw_attributes'].values())
        assert len(p['personality'])==8 and all(1<=v<=20 for v in p['personality'].values())
        assert len(p['databaseRaw']['attributes'])==54
try:load(root,set(),expected_hash='0'*64)
except ValueError:pass
else:raise AssertionError('Accepted changed database cohort')
try:frame((root/'people_db.dat').read_bytes()[12:-1],768*1024**2)
except ValueError:pass
else:raise AssertionError('Accepted truncated compression frame')
with tempfile.TemporaryDirectory(dir=output) as missing:
    try:load(Path(missing),set())
    except FileNotFoundError:pass
    else:raise AssertionError('Accepted missing database components')
assert before==hashes(),'Reader changed the game database'
for name,value in [('catalog',catalog),('rosters',rosters)]:
    (output/(name+'.json')).write_text(json.dumps(value,ensure_ascii=False),encoding='utf8')
print('PASS DAT:',len(catalog['clubs']),'clubs;',len(catalog['leagues']),'complete candidate leagues;',len(rosters['rosters']),'imported clubs;',sum(len(r['players']) for r in rosters['rosters']),'players')
print('PASS deterministic initialization, identity/ranges, mismatched cohort, truncated frame, missing components, read-only source')
