"""Read the installed 2700 database (DAT schema 4000) without starting a career.

DAT stores object footers and database ordinals; these are not the save's object
headers or runtime IDs. Every counted table is walked to its exact trailer.
Only selected squads are fully decoded. Zero/unrated fields are initialized
with a recorded deterministic policy, never described as game career values.
"""
from pathlib import Path
from collections import defaultdict
from datetime import date,timedelta
import hashlib,random,struct
from backports import zstd

MAGIC=bytes.fromhex('03017461642ea00fa90e0900')
FMF=bytes.fromhex('0201666d662e080000')
FILES=('server_db.dat','people_db.dat','basic_people_db.dat','lang_db.dat')
U32=struct.Struct('<I')

def u32(b,p):return U32.unpack_from(b,p)[0]
def string(b,p):
    n=u32(b,p);p+=4
    if n>16384 or p+n>len(b):raise ValueError('DAT 字符串越界。')
    return b[p:p+n].decode('utf8'),p+n

def frame(b,cap):
    d=zstd.ZstdDecompressor();raw=d.decompress(b,max_length=cap+1)
    if not d.eof or d.unused_data or len(raw)>cap:raise ValueError('DAT 压缩块未完整读取或超过上限。')
    return raw

class Archive:
    def __init__(self,b):
        if b[:12]!=MAGIC or b[12:21]!=FMF:raise ValueError('仅支持已验证的 2700 DAT 数据库归档。')
        total,second,revision=struct.unpack_from('<QQB',b,21)
        end=21+total
        if second!=17 or revision!=3 or total<17 or end+9>len(b) or b[end:end+9]!=FMF:raise ValueError('DAT 归档边界无效。')
        toc=frame(b[end+9:],8*1024**2);_,p=string(toc,0);count=u32(toc,p);p+=4
        if not 1<=count<=1000:raise ValueError('DAT 表目录数量无效。')
        self.entries={};self.b=b
        for _ in range(count):
            name,p=string(toc,p);ext,p=string(toc,p);off,stored,raw,_,_=struct.unpack_from('<QQQqq',toc,p);p+=40
            if name in self.entries or ext!='.dat' or off+stored>end-38 or raw>768*1024**2:raise ValueError('DAT 表目录无效。')
            self.entries[name]=(off,stored,raw)
        if toc[p:]!=bytes(4):raise ValueError('DAT 表目录包含未支持的子目录。')
    def read(self,name):
        off,n,size=self.entries[name];v=frame(self.b[38+off:38+off+n],size)
        if len(v)!=size:raise ValueError('DAT 表长度不一致。')
        return v

def table_end(b,p):
    if len(b)-p!=9 or b[p:p+5]!=b'\0\0\0\0\x01':raise ValueError('DAT 计数表尾部不匹配。')

def club_table(b):
    from fmsave._layouts.fm26_26_3_2 import CLUB_TABLE
    from fmsave.readers.club_table import walk_club_table
    rows=walk_club_table(b,8,CLUB_TABLE)
    if not rows:raise ValueError('DAT 俱乐部表未通过完整计数校验。')
    result={}
    for ordinal,row in enumerate(rows):
        p=row.body_start
        if b[p] not in (0,12):raise ValueError('未知 DAT 俱乐部类型。')
        nation=u32(b,p+1);p+=27+(4 if b[p]==12 else 0)
        name,p=string(b,p);short,p=string(b,p)
        result[row.unique_id]={'id':row.unique_id,'name':short or name or f'俱乐部 #{row.unique_id}','nation':nation}
    table_end(b,rows[-1].footer_start+12)
    return result

def team_table(b,clubs):
    count=u32(b,8);p=13;rows=[]
    if not 1<=count<=200000:raise ValueError('DAT 球队表数量无效。')
    for ordinal in range(count):
        if b[p] not in (10,11):raise ValueError('DAT 球队类型无效。')
        pos=p
        while True:
            pos=b.find(U32.pack(ordinal),pos,min(len(b)-12,p+100000))
            if pos<0:raise ValueError('DAT 球队记录缺少结尾。')
            uid,copy=struct.unpack_from('<II',b,pos+4)
            if uid==copy and (ordinal==count-1 or b[pos+12] in (10,11)):break
            pos+=1
        if b[p]==10:
            n=struct.unpack_from('<H',b,p+34)[0]
            if p+36+n*4>pos:raise ValueError('DAT 球队名单越界。')
            players=struct.unpack_from('<'+'I'*n,b,p+36)
            if uid not in clubs or len(set(players))!=len(players):raise ValueError('DAT 球队与俱乐部无法对应。')
            rows.append({'clubID':uid,'ordinal':ordinal,'competition':u32(b,p+5),'players':players,'reputation':struct.unpack_from('<H',b,p+3)[0]})
        p=pos+12
    table_end(b,p)
    return rows

def competitions(raw,localized):
    n=u32(localized,8);p=12;names=[]
    for _ in range(n):
        uid=u32(localized,p);p+=4;name,p=string(localized,p);p+=1;short,p=string(localized,p);p+=1;_,p=string(localized,p)
        if localized[p]!=0:raise ValueError('不支持此 DAT 联赛名称变体。')
        p+=1;names.append((uid,name,short))
    if p!=len(localized) or n!=u32(raw,8):raise ValueError('DAT 联赛名称表数量不一致。')
    p=13;result={}
    for ordinal,(uid,name,short) in enumerate(names):
        end=raw.find(struct.pack('<III',ordinal,uid,uid),p)
        if end<0:raise ValueError('DAT 联赛记录与名称无法对应。')
        result[ordinal]={'id':uid,'name':short or name};p=end+12
    table_end(raw,p);return result

def basic_people(b):
    count=u32(b,0);p=5;by_id={};by_index={}
    if not 1<=count<=2000000 or b[4]!=0:raise ValueError('DAT 人物索引头无效。')
    sizes={1:72,2:72,3:72,4:22,5:10}
    for i in range(count):
        if b[p]!=17 or b[p+1] not in sizes:raise ValueError('DAT 人物索引类型无效。')
        end=p+sizes[b[p+1]];ordinal,uid,copy=struct.unpack_from('<III',b,end)
        if ordinal!=i or uid!=copy or uid in by_id:raise ValueError('DAT 人物索引身份不一致。')
        by_id[uid]=(i,p,end,b[p+1]);by_index[i]=uid;p=end+12
    table_end(b,p);return by_id,by_index

def person_table(b,by_index):
    count=u32(b,2);p=6;rows={}
    if b[:2]!=bytes(2) or count!=len(by_index):raise ValueError('DAT 人物表与索引数量不同。')
    for _ in range(count):
        ordinal=u32(b,p);kind=b[p+4]
        if ordinal not in by_index or kind not in (1,2,3,4,5):raise ValueError('DAT 人物记录类型无效。')
        uid=by_index[ordinal];end=b.find(struct.pack('<III',ordinal,uid,uid),p+5,min(p+100000,len(b)))
        if end<0 or uid in rows:raise ValueError('DAT 人物记录缺失或重复。')
        rows[uid]=(ordinal,p,end,kind);p=end+12
    # The people stream also retains its object-category counters.
    if len(b)-p!=28:raise ValueError('DAT 人物流尾部不匹配。')
    return rows

def name_pool(b):
    n=u32(b,8);p=12;names=[]
    for i in range(n):
        if u32(b,p)!=i:raise ValueError('DAT 姓名表顺序无效。')
        value,p=string(b,p+4);names.append(value)
    if p!=len(b):raise ValueError('DAT 姓名表尾部无效。')
    return names

def name_reference(b,p,end,pool):
    if p+5>end:raise ValueError('name boundary')
    identity=u32(b,p);flag=b[p+4];p+=5
    if flag==0:
        if identity==0xffffffff:return '',p
        if identity>=len(pool):raise ValueError('name id')
        return pool[identity],p
    if flag!=1 or identity>=len(pool):raise ValueError('name type')
    value,p=string(b,p)
    if p+16>end or u32(b,p)!=identity or value!=pool[identity]:raise ValueError('inline name identity')
    return value,p+16

def person_fields(b,start,end,basic,pools,today):
    nation=u32(basic,2);year=struct.unpack_from('<H',basic,52)[0];matches=[]
    for q in range(start+8,end-50):
        if b[q+4] not in (0,1):continue
        try:
            first,next=name_reference(b,q,end,pools[0]);last,next=name_reference(b,next,end,pools[1]);common,next=name_reference(b,next,end,pools[2])
            legal,birth=string(b,next)
            if birth+30>end:continue
            day,y=struct.unpack_from('<HH',b,birth);personality=list(b[birth+22:birth+30])
            if y!=year or not 1900<=y<=today.year or not 1<=day<=366 or u32(b,birth+14)!=nation or max(personality)>20:continue
            dob=date(y,1,1)+timedelta(days=day-1)
        except (ValueError,UnicodeError,struct.error):continue
        name=common or ' '.join(x for x in (first,last) if x) or legal
        if not name:continue
        matches.append((name,today.year-y-((today.month,today.day)<(dob.month,dob.day)),personality,struct.unpack_from('<Q',b,q-8)[0]))
    if len(matches)!=1:raise ValueError('DAT 球员姓名、出生日期与性格未能唯一对应。')
    return matches[0]

def player(b,entry,basic,pools,today,uid):
    from fmsave._layouts.fm26_26_3_2 import PLAYER_RECORDS
    ordinal,p,end,kind=entry
    if kind not in (2,3):return None
    ca=p+11
    if basic[1]!=kind or u32(b,ca+16)!=u32(basic,10):raise ValueError(f'球员 #{uid} 的类型或俱乐部索引与人物表不一致。')
    ability,potential=struct.unpack_from('<Hh',b,ca)
    ratings=list(b[ca+24:ca+39]);attrs=list(struct.unpack_from('<54b',b,ca+39));height=b[ca+121]
    if not 0<=ability<=200 or not -100<=potential<=200 or len(attrs)!=54 or max(ratings+attrs)>20 or min(attrs)<-10:raise ValueError(f'DAT 球员 #{uid} 类型 {kind} 的能力或位置数值无效：CA {ability} / PA {potential} / 属性最大 {max(ratings+attrs)}。')
    try:name,age,personality,traits=person_fields(b,p,end,basic,pools,today)
    except ValueError as error:raise ValueError(f"球员 #{uid}：{error}") from error
    if not 14<=age<=60:return None
    raw_initial={'attributes':attrs.copy(),'positions':ratings.copy(),'personality':personality.copy(),'ability':ability,'potential':potential,'height':height}
    rng=random.Random(f'dat2700-unrated-v1:{uid}');unknown=0
    base=max(4,min(17,round((ability or 50)/12)))
    keys=list(PLAYER_RECORDS.attribute_field_order);keys[24:24]=['left_foot','right_foot']
    hidden={'consistency','important_matches','injury_proneness','versatility','dirtiness','eccentricity','punching','aggression','flair','leadership'}
    strengths=set()
    for positions,fields in [((0,), 'handling reflexes one_on_ones aerial_reach command_of_area communication positioning concentration agility'),((1,3),'marking tackling heading jumping_reach strength positioning anticipation concentration bravery'),((2,4,13,14),'pace stamina acceleration crossing tackling work_rate positioning'),((5,),'tackling positioning anticipation passing decisions teamwork stamina'),((6,8,9,11),'pace acceleration dribbling crossing off_the_ball technique agility'),((7,10),'passing vision decisions first_touch teamwork stamina technique'),((12,),'finishing off_the_ball anticipation composure acceleration heading first_touch')]:
        if any(ratings[j]>=15 for j in positions):strengths.update(fields.split())
    dominant=rng.choice((24,25,25,25))
    for i,v in enumerate(attrs):
        if v<=0:
            unknown+=1
            if keys[i] in hidden:attrs[i]=rng.randint(1,20)
            elif i in (24,25):attrs[i]=20 if i==dominant else rng.randint(4,14)
            else:
                keeper=ratings[0]>=15;gk=keys[i] in {'handling','aerial_reach','command_of_area','communication','kicking','throwing','one_on_ones','reflexes','rushing_out'}
                centre=3 if gk and not keeper else base+(2 if keys[i] in strengths else -1)
                attrs[i]=max(1,min(20,centre+min(0,v)+rng.randint(-3,3)))
    for i,v in enumerate(personality):
        if v==0:personality[i]=rng.randint(5,16);unknown+=1
    if not 140<=height<=220:height=185 if ratings[0]>=15 else 178;unknown+=1
    if ability==0:ability=base*12;unknown+=1
    positions=dict(zip(('gk','sw','dl','dc','dr','dm','ml','mc','mr','aml','amc','amr','stc','wbl','wbr'),ratings))
    feet=(attrs[24]*5,attrs[25]*5);without=attrs[:24]+attrs[26:]
    reputation=dict(zip(('home','current','world'),struct.unpack_from('<3H',b,p+5)))
    # Initial reputation is stored on the 0–200 scale, unlike save values.
    if max(reputation.values())>200:raise ValueError('DAT 声望超出原始值范围。')
    reputation={k:v*50 for k,v in reputation.items()}
    return {'uid':uid,'unique_id':uid,'name':name,'positions':positions,'raw_attributes':dict(zip(PLAYER_RECORDS.attribute_field_order,(v*5 for v in without))),
      'raw_left_foot':feet[0],'raw_right_foot':feet[1],'height_cm':height,'age':age,'ability':{'current':ability},'personality':dict(zip(('adaptability','ambition','loyalty','pressure','professionalism','sportsmanship','temperament','controversy'),personality)),
      'trait_bits':traits,'reputation':reputation,'initializedFields':unknown,'databaseRaw':raw_initial}

def coaches(people,records,basic,basic_ids,pools,today,teams):
    selected={t['ordinal']:t['clubID'] for t in teams};found=defaultdict(list)
    for uid,(_,p,e,kind) in basic_ids.items():
        if kind!=1 or u32(basic,p+10) not in selected or basic[p+54]!=5:continue
        _,s,end,kind=records[uid]
        if kind!=1:continue
        ca=s+13+7*struct.unpack_from('<H',people,s+5)[0]
        if ca+66>end or people[ca+4]!=16 or people[ca+13]!=12:continue
        ability,potential=struct.unpack_from('<HH',people,ca)
        raw=list(people[ca+14:ca+66]);codes=list(people[ca+5:ca+13])
        if not 0<=ability<=200 or not ability<=potential<=200 or len(raw)!=52 or max(raw)>20 or max(codes)>64:continue
        name=person_fields(people,s,end,basic[p:e],pools,today)[0]
        profile=raw[:26]+[v*5 for v in raw[26:]]
        found[selected[u32(basic,p+10)]].append({'id':str(uid),'name':name,'source':'DAT 主教练 · 教练参数与阵型偏好；未设定值保留 0','parameters':profile,'formationCodes':[codes[i] for i in (0,1,3,2,4,5,7,6)]})
    return {club:rows[0] for club,rows in found.items() if len(rows)==1}

def load(source,wanted,expected_hash=None):
    root=source if source.is_dir() else source.parent
    payloads={};stats={};h=hashlib.sha256()
    for name in FILES:
        path=root/name;stat=path.stat()
        if not 0<stat.st_size<256*1024**2:raise ValueError('DAT 数据库组件大小无效。')
        raw=path.read_bytes()
        if raw[:12]!=MAGIC:raise ValueError('数据库组件版本不匹配；请选择完整的 2700_fm 目录。')
        payloads[name]=raw;stats[name]=(stat.st_size,stat.st_mtime_ns);h.update(name.encode());h.update(hashlib.sha256(raw).digest())
    digest=h.hexdigest()
    if expected_hash and expected_hash!=digest:raise ValueError('数据库文件已变化，请重新读取目录。')
    server=Archive(payloads['server_db.dat']);simple=server.read('simple_vars')
    version,_=string(simple,18)
    if version!='2700':raise ValueError('当前只验证了 2700 原始数据库。')
    clubs=club_table(server.read('table_3'));teams=team_table(server.read('table_24'),clubs)
    lang=Archive(payloads['lang_db.dat']);comps=competitions(server.read('table_25'),lang.read('8_25'))
    today=date(2026,7,1)
    result={'schemaVersion':1,'sourceKind':'database','sourceName':'FM27 数据库 2700','sourceSHA256':digest,'gameDate':today.isoformat(),'build':'DAT 4000 / 2700',
      'notes':['读取本机原始 DAT 俱乐部、球队名单、球员能力与隐藏资料，不读取职业生涯进度。','未设定或负值预设的球员属性按位置和能力补全；性格独立取值。缺少能力、身高时也会补全，使用固定球员 ID 种子。原始值和补全数量保存在导入数据中。这是工具初始化规则，不是 FM 开档初始化器。','初始球员池未分配存档一线队注册，导入 14–60 岁球员，最多保留能力最高的 100 人；比赛选用工作台首发及候补。年龄按 2026-07-01 计算。兼任职员的球员只导入球员资料。','联赛归属取自数据库球队表；赛程由工具生成双循环，积分和同分规则需在导入时核对。数据库编辑补丁 DBC、LNC 和职业生涯动态规则未加载。'],
      'calendarWarning':'原始数据库没有职业生涯赛程；导入联赛后由工具生成循环赛程。'}
    if wanted:
        if not 1<=len(wanted)<=40 or not wanted.issubset(clubs):raise ValueError('请选择数据库中 1–40 支球队。')
        basic=frame(payloads['basic_people_db.dat'][12:],128*1024**2);people=frame(payloads['people_db.dat'][12:],768*1024**2)
        basic_ids,by_index=basic_people(basic);records=person_table(people,by_index)
        pools=[name_pool(server.read(f'name_table_extra_{i}'))for i in range(3)]
        managers=coaches(people,records,basic,basic_ids,pools,today,[t for t in teams if t['clubID'] in wanted])
        result['rosters']=[]
        for team in teams:
            uid=team['clubID']
            if uid not in wanted:continue
            players=[]
            for ordinal in team['players']:
                if ordinal not in by_index:raise ValueError('数据库球队名单出现未知人物。')
                identity=by_index[ordinal];_,p,e,kind=basic_ids[identity]
                if kind not in (2,3):continue
                if u32(basic,p+10)!=team['ordinal']:raise ValueError('数据库球队名单与球员所属球队不一致。')
                value=player(people,records[identity],basic[p:e],pools,today,identity)
                if value:players.append(value)
            players.sort(key=lambda p:(-p['ability']['current'],p['uid']))
            if len(players)<11:raise ValueError(clubs[uid]['name']+' 的可用数据库球员不足 11 人，请另选球队或从存档导入。')
            result['rosters'].append({'clubID':uid,'name':clubs[uid]['name'],'players':players[:100],'coach':managers.get(uid)})
        if set(r['clubID'] for r in result['rosters'])!=wanted:raise ValueError('所选俱乐部缺少可用球队名单。')
    else:
        playable={t['clubID'] for t in teams if len(t['players'])>=11}
        result['clubs']=[{'id':u,'name':c['name']}for u,c in clubs.items() if u in playable];result['managedClubIDs']=[]
        groups=defaultdict(list)
        for team in teams:
            if team['competition'] in comps:groups[team['competition']].append(team['clubID'])
        result['leagues']=[{'id':f'dat2700:{comps[k]["id"]}','name':comps[k]['name'],'competitionID':comps[k]['id'],'stageID':0,'season':2026,'clubIDs':v,'fixtures':[]}for k,v in groups.items() if 4<=len(v)<=40 and len(set(v))==len(v) and set(v)<=playable]
    for name,(size,mtime) in stats.items():
        stat=(root/name).stat()
        if (stat.st_size,stat.st_mtime_ns)!=(size,mtime):raise ValueError('读取期间 DAT 文件发生变化，未导入。')
    return result
