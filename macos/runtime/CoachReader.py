"""Capture checked staff preferences through the upstream save reader.

The 52-byte coaching block and 8 formation codes are used by the original
match AI. Unreadable or missing first-team managers remain explicitly absent.
"""
import struct

def coaches(save, wanted):
    import fmsave.readers.staff as reader
    original_read,original_person=reader._read_ability_block,reader._PersonObject
    profiles={};by_uid={}
    def capture(db,header,layout):
        result=original_read(db,header,layout)
        if result[0] is not None and all(result[1:]):
            base=header+layout.ability_base_offset+layout.entry_bytes*db[header+layout.entry_count_offset]
            start=base+layout.preferences_offset;end=base+layout.block_40_offset+layout.block_40_count
            raw=list(db[start:end]);codes=list(db[base+layout.codes_offset:base+layout.codes_offset+layout.code_count])
            if len(raw)==52 and max(raw)<=100 and len(codes)==8 and max(codes)<=64:
                profiles[header]=(raw,[codes[i] for i in (0,1,3,2,4,5,7,6)])
        return result
    def person(*args,**kwargs):
        value=original_person(*args,**kwargs)
        by_uid[value.uid]=value.header
        return value
    reader._read_ability_block=capture;reader._PersonObject=person
    try:
        result={}
        for staff in save.staff():
            if staff.club_uid not in wanted or staff.job is None or staff.job.raw!=16 or by_uid.get(staff.uid) not in profiles:continue
            # A listed youth/reserve manager must not displace the first team.
            if staff.team_slot not in (None,0):continue
            raw,codes=profiles[by_uid[staff.uid]]
            row={'id':str(staff.uid),'name':staff.name or '存档主教练','source':'存档主教练 · 已读取教练参数与阵型偏好','parameters':raw,'formationCodes':codes}
            result.setdefault(staff.club_uid,[]).append(row)
        return {club:rows[0] for club,rows in result.items() if len(rows)==1}
    finally:
        reader._read_ability_block=original_read;reader._PersonObject=original_person
