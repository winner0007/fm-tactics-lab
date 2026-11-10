"""Read-only FM27 roster/calendar bridge; reuses the upstream registered reader.

No engine initialization, cache extraction, save mutation or inferred tactics.
Output is private user data, never part of the app distribution or repository.
"""
from pathlib import Path
import argparse
import dataclasses
import hashlib
import json
import os
import resource
import signal
import sys
from collections import Counter, defaultdict

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'src'))
import desktop_save_compat
from desktop_save_players import selected_players


def plain(value):
    if dataclasses.is_dataclass(value):
        return {f.name: plain(getattr(value, f.name)) for f in dataclasses.fields(value)}
    if isinstance(value, dict): return {str(k): plain(v) for k,v in value.items()}
    if isinstance(value, (tuple, list)): return [plain(v) for v in value]
    if value is None or isinstance(value, (str, int, float, bool)): return value
    return str(value)


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp=path.with_suffix('.tmp')
    tmp.write_text(json.dumps(value,ensure_ascii=False,separators=(',',':')),encoding='utf8')
    tmp.replace(path)


def leagues(fixtures, today):
    groups=defaultdict(list)
    for f in fixtures:
        if f.get('home_team_slot')==0 and f.get('away_team_slot')==0 and f.get('round') is None and f.get('season_start_year') is not None:
            groups[(f['competition_id'],f['stage_id'],f['season_start_year'])].append(f)
    result=[]
    for (competition,stage,year),matches in groups.items():
        members={m[k] for m in matches for k in ('home_club_uid','away_club_uid')}
        if None in members or not 4<=len(members)<=40: continue
        pairs=Counter((m['home_club_uid'],m['away_club_uid']) for m in matches)
        if any(a==b for a,b in pairs) or len(pairs)!=len(members)*(len(members)-1) or set(pairs.values())!={1}: continue
        dates=[m['date'] for m in matches if m.get('date')]
        if not dates or max(dates)<today: continue
        result.append({'id':f'{competition}:{stage}:{year}','competitionID':competition,'stageID':stage,'season':year,'clubIDs':sorted(members),'fixtures':[{'id':str(i),'home':m['home_club_uid'],'away':m['away_club_uid'],'date':m.get('date'),'homeGoals':m.get('home_goals') if m.get('played') else None,'awayGoals':m.get('away_goals') if m.get('played') else None} for i,m in enumerate(sorted(matches,key=lambda m:(m['date'],m['home_club_uid'],m['away_club_uid'])))]})
    return sorted(result,key=lambda l:(l['season'],l['competitionID'],l['stageID']))


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('source',type=Path);parser.add_argument('output',type=Path)
    parser.add_argument('--clubs',default='')
    parser.add_argument('--expected-sha256')
    args=parser.parse_args()
    source=args.source.resolve();before=source.stat()
    if source.suffix.lower()!='.fm' or not 0<before.st_size<=2*1024**3: raise ValueError('请选择不超过 2 GiB 的 FM27 .fm 存档。原始数据库 .dat 与编辑器 .fmf 使用其他格式。')
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    signal.alarm(300)
    with source.open('rb') as stream: digest=hashlib.file_digest(stream,'sha256').hexdigest()
    if args.expected_sha256 and args.expected_sha256!=digest: raise ValueError('存档已更新，请重新读取目录后导入阵容。')
    desktop_save_compat.install()
    import fmsave
    with fmsave.open(source) as save:
        if save.info.game!='FM27': raise ValueError('当前只启用 FM27 的已登记结构。')
        result={'schemaVersion':1,'sourceName':source.name,'sourceSHA256':digest,'gameDate':str(save.info.game_date),'build':save.info.build,
                'notes':['存档解析复用原项目 fmsave 0.9.0 与版本登记；通过结构校验，不等同于逐字段游戏内对照。','只导入一线队注册球员。战术须在工作台选择或核对，不把默认阵型当作存档实战战术。','独立比赛按固定开赛状态运行，不模拟跨场伤病、停赛、转会或训练。']}
        if args.clubs:
            wanted={int(v) for v in args.clubs.split(',')}
            if not 1<=len(wanted)<=40: raise ValueError('一次读取 1–40 支球队。')
            known={c.uid:c for c in save.clubs()}
            if not wanted.issubset(known): raise ValueError('球队不在此存档中。')
            players,*_=selected_players(save,wanted,roster_only=True)
            squads=defaultdict(list)
            fields=['uid','unique_id','name','positions','raw_attributes','raw_left_foot','raw_right_foot','height_cm','age','ability','personality','trait_bits','reputation']
            for p in players:
                if p.team_slot==0: squads[p.club_uid].append({k:plain(getattr(p,k)) for k in fields})
            result['rosters']=[{'clubID':uid,'name':known[uid].short_name or known[uid].name,'players':squads[uid]} for uid in sorted(wanted)]
            if any(not 11<=len(r['players'])<=100 for r in result['rosters']): raise ValueError('有球队的一线队注册名单不足 11 人或超过 100 人；请另选球队，或在游戏中核对注册情况。')
        else:
            result['clubs']=[{'id':c.uid,'name':c.short_name or c.name} for c in save.clubs()]
            result['managedClubIDs']=[m.club_uid for m in save.managed_clubs()]
            result['leagues']=leagues([plain(f) for f in save.fixtures()],str(save.info.game_date))
    after=source.stat()
    if (before.st_size,before.st_mtime_ns)!=(after.st_size,after.st_mtime_ns): raise ValueError('读取期间存档发生变化，未导入。')
    write(args.output,result)
    print(json.dumps({'status':'complete','output':str(args.output),'sourceSHA256':digest}),flush=True)


if __name__=='__main__':
    try: main()
    except Exception as error:
        print(json.dumps({'status':'failed','error':str(error)},ensure_ascii=False),flush=True)
        sys.exit(2)
