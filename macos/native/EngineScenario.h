// Mac arm64 input binding for the hash-locked FM27 profile.
// These are serialized input fields, not executable patches or readiness flags.
#include "../../native/fm27_tactic_bindings.h"
#include <set>
#include <vector>
#include "EnginePlayerPolicy.h"

static NSDictionary *scenario;
static NSString *scenarioHash;
static NSMutableArray *scenarioRoster;
static unsigned char *scenarioActors[2][26];
static uint32_t personKey(unsigned char *actor) {
    void *api=slot(0x5721a08);
    // Itanium method 63 returns the small key in w0, unlike Windows' sret ABI.
    return ((uint32_t(*)(void*,void*))(*(void***)api)[63])(api,actor+0x20);
}
static bool number(id value, uint64_t max) {
    if(![value isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID()) return false;
    double d=[value doubleValue];return std::isfinite(d)&&d>=0&&floor(d)==d&&d<=max;
}
static uint64_t roleValue(NSDictionary *cell) {
    id value=cell[@"role"];
    if(![value isKindOfClass:NSString.class]||[value length]>20) fail("invalid_role_value",83);
    const char *s=[value UTF8String];char *end;uint64_t v=strtoull(s,&end,10);
    uint64_t role=v&0xfffffffbf91fffffULL,duty=v&~0xfffffffbf91fffffULL;
    bool validDuty=false;for(uint64_t d:{0ULL,2097152ULL,4194304ULL,8388608ULL,33554432ULL,67108864ULL,17179869184ULL})if(d==duty)validDuty=true;
    if(!*s||*s=='-'||*end||!role||(role&(role-1))||!validDuty) fail("invalid_role_value",83);
    return v;
}
static bool profileField(unsigned char *actor,unsigned field,uint32_t value,bool write,unsigned char *team) {
    unsigned offset=0,size=0,max=0,min=0;
    if(field==0) {if(value<140||value>220)return false;if(!actor)return true;float height=value/100.0f;if(write)memcpy(actor+0x64,&height,4);return fabs(*(float*)(actor+0x64)-height)<0.0001;}
    if(field==1){offset=0x71;size=1;min=14;max=60;}
    else if(field>=2&&field<=8){offset=0x6a+field-2;size=1;min=1;max=20;}
    else if(field==9||field==10){offset=0xbb0+4*(field-9);size=4;max=UINT32_MAX;}
    else if(field>=11&&field<=18){static unsigned offsets[]={0xc90,0xc84,0xc8e,0xc70,0xc82,0xc88,0xc72,0xc7c};offset=offsets[field-11];size=2;max=field==11?200:(field==18?65535:10000);}
    else if(field==19){offset=0x68;size=1;min=40;max=140;}
    else if(field==20||field==21){offset=field==20?0xca0:0xc9a;size=1;min=field==20?25:0;max=field==20?82:100;}
    else if(field==22){offset=0xc9b;size=1;min=1;max=20;}
    else return false;
    if(value<min||value>max)return false;
    if(!actor)return true;
    if(write&&field==20){
        // Original preparation blends team cohesion, limiting the change to
        // +/-25 (4546290..45462e0). Invert that exact integer transform.
        bool found=false;int base=50+int((signed char)team[0x129])*5;
        for(int input=0;input<=100;input++) {
            int prepared=std::max(0,std::min(100,std::max(input-25,std::min(input+25,(input+base)/2))));
            if(prepared==int(value)){value=input;found=true;break;}
        }
        if(!found)return false;
    }
    if(write)memcpy(actor+offset,&value,size);
    uint32_t actual=0;memcpy(&actual,actor+offset,size);return actual==value;
}
#include "EngineSetPieces.h"

static void extraTeamBits(NSDictionary *t,unsigned char *bits) {
    id extra=t[@"extraTeamBits"];if(!extra)return;
    if(![extra isKindOfClass:NSString.class]||[extra length]!=32)fail("invalid_extra_team_bits",83);
    const char *text=[extra UTF8String];
    for(unsigned i=0;i<16;i++) {char word[]={text[2*i],text[2*i+1],0};char *end=nullptr;unsigned long value=strtoul(word,&end,16);if(*end||!isxdigit(word[0])||!isxdigit(word[1]))fail("invalid_extra_team_bits",83);bits[i]=(unsigned char)value;}
    for(auto o:fm27_team_options)if(o.bit&&(bits[o.bit/8]&(1<<(o.bit%8))))fail("extra_named_team_bit",83);
}

static void validateScenario() {
    if(!scenario)return;
    if(![scenario isKindOfClass:NSDictionary.class]||![scenario[@"schemaVersion"] isEqual:@1]||![scenario[@"teams"] isKindOfClass:NSArray.class]||[scenario[@"teams"] count]!=2) fail("invalid_scenario_schema",83);
    for(NSDictionary *t in scenario[@"teams"]) {
        if(![t isKindOfClass:NSDictionary.class]||!number(t[@"mentality"],7)||[t[@"mentality"] intValue]<1) fail("invalid_scenario_team",83);
        NSArray *players=t[@"players"],*phases=t[@"phases"],*instructions=t[@"instructions"];
        if(![players isKindOfClass:NSArray.class]||players.count<11||players.count>20||![phases isKindOfClass:NSArray.class]||phases.count!=2||![instructions isKindOfClass:NSArray.class]||instructions.count!=29) fail("invalid_scenario_roster",83);
        NSMutableSet *ids=[NSMutableSet set];
        for(NSDictionary *p in players) {
            if(![p isKindOfClass:NSDictionary.class]||![p[@"id"] isKindOfClass:NSString.class]||![p[@"name"] isKindOfClass:NSString.class]||[p[@"name"] length]>80||[ids containsObject:p[@"id"]]) fail("invalid_scenario_identity",83);
            [ids addObject:p[@"id"]];NSArray *a=p[@"attributes"];
            if(![a isKindOfClass:NSArray.class]||a.count!=69) fail("invalid_scenario_attributes",83);
            for(unsigned i=0;i<69;i++)if(!number(a[i],i<15?20:100)||(i>=15&&[a[i] intValue]<1))fail("invalid_scenario_attributes",83);
            if(![p[@"profile"] isKindOfClass:NSDictionary.class]||[p[@"profile"] count]!=23)fail("invalid_player_profile",83);
            for(NSString *field in p[@"profile"])if(![field isKindOfClass:NSString.class]||![[NSString stringWithFormat:@"%d",field.intValue] isEqual:field]||!number(p[@"profile"][field],UINT32_MAX)||!profileField(nullptr,field.intValue,[p[@"profile"][field] unsignedIntValue],false,nullptr))fail("invalid_player_profile",83);
        }
        if(![t[@"setPieces"] isKindOfClass:NSDictionary.class])fail("missing_setpieces",83);
        validateSetPieces(t[@"setPieces"],(unsigned)players.count);
        std::set<unsigned> groups;unsigned char bits[16]={};extraTeamBits(t,bits);
        for(NSDictionary *instruction in instructions) {
            if(![instruction isKindOfClass:NSDictionary.class]||!number(instruction[@"group"],32)||!number(instruction[@"value"],UINT32_MAX))fail("invalid_team_instruction",83);
            unsigned group=[instruction[@"group"] unsignedIntValue],value=[instruction[@"value"] unsignedIntValue];
            const FM27TeamOption *selected=nullptr;
            for(auto &o:fm27_team_options)if(o.group==group&&o.value==value)selected=&o;
            if(!selected||!groups.insert(group).second) fail("invalid_team_instruction",83);
            if(selected->bit)bits[selected->bit/8]|=1<<(selected->bit%8);
        }
        uint64_t low=0;memcpy(&low,bits,8);
        if(((low>>25&1)&&(low&0x70000000ULL))||((low>>26&1)&&(low&0x30000000ULL))||((low>>27&1)&&(low&0x50000000ULL)))fail("conflicting_team_instructions",83);
        for(unsigned phase=0;phase<2;phase++) {
            NSArray *cells=phases[phase];if(![cells isKindOfClass:NSArray.class]||cells.count!=11)fail("invalid_phase",83);
            std::set<unsigned> positions;unsigned cb=0,dm=0;
            for(NSDictionary *cell in cells) {
                if(![cell isKindOfClass:NSDictionary.class]||!number(cell[@"position"],UINT32_MAX)) fail("invalid_position",83);
                unsigned p=[cell[@"position"] unsignedIntValue];bool valid=false;for(auto a:fm27_positions)if(p==a)valid=true;
                if(!valid||!positions.insert(p).second)fail("invalid_position",83);
                cb+=(p&16)!=0;dm+=(p&128)!=0;
            }
            for(unsigned i=0;i<11;i++) {
                NSDictionary *cell=cells[i];unsigned p=[cell[@"position"] unsignedIntValue];uint64_t role=roleValue(cell)&0xfffffffbf91fffffULL;
                if((i==0)!=(p==1))fail("goalkeeper_position_mismatch",83);
                bool valid=false;for(auto r:fm27_role_contexts)if(r.phase==phase&&r.position==p&&r.centre_back_bucket==(cb>=3?3:0)&&r.single_dm==(dm==1)&&r.role==role)valid=true;
                if(!valid) fail("role_not_available_at_position",83);
                NSArray *options=cell[@"instructions"];if(![options isKindOfClass:NSArray.class])fail("invalid_player_instructions",83);
                std::set<unsigned> piGroups;
                for(id option in options) {
                    if(!number(option,42)||[option intValue]==0)fail("invalid_player_instruction",83);
                    bool found=false;for(auto o:fm27_player_options)if(o.value==[option unsignedIntValue]){if(!piGroups.insert(o.group).second)fail("conflicting_player_instructions",83);found=true;}
                    if(!found)fail("invalid_player_instruction",83);
                    bool permitted=false;
                    for(auto policy:nativePIPolicies)if(policy.phase==phase&&policy.position==p&&policy.role==role&&policy.states[[option unsignedIntValue]]=='0')permitted=true;
                    if(!permitted)fail("role_locked_player_instruction",83);
                }
                if(!number(cell[@"targetPlayer"],255)||!number(cell[@"targetPosition"],UINT32_MAX))fail("invalid_marking_target",83);
                unsigned target=[cell[@"targetPlayer"] unsignedIntValue],targetPosition=[cell[@"targetPosition"] unsignedIntValue];
                bool man=[options containsObject:@34],zone=[options containsObject:@35],validPosition=false;
                for(auto pos:fm27_positions)if(targetPosition==pos)validPosition=true;
                unsigned opponentCount=(unsigned)[scenario[@"teams"][[scenario[@"teams"] indexOfObjectIdenticalTo:t]==0?1:0][@"players"] count];
                if((man?target>=opponentCount:target!=255)||(zone?!validPosition:targetPosition!=0))fail("invalid_marking_target",83);
            }
        }
    }
}
static uint64_t instructionFlags(NSDictionary *cell) {uint64_t v=0;for(NSNumber *n in cell[@"instructions"])v|=1ULL<<n.unsignedIntValue;return v;}
static uint64_t markingTarget(NSDictionary *cell) {return (uint64_t([cell[@"targetPlayer"] unsignedIntValue])<<32)|[cell[@"targetPosition"] unsignedIntValue];}
static uint64_t *cellEntry(unsigned char *cell) {
    auto start=*(uint64_t**)(cell+8),end=*(uint64_t**)(cell+16);uint64_t role=*(uint64_t*)(cell+64)&0xfffffffbf91fffffULL;
    for(auto p=start;p<end;p+=3)if(*p==role)return p;return nullptr;
}
static void applyScenario(unsigned char *match) {
    if(!scenario)return;begin("apply_workbench_inputs");scenarioRoster=[NSMutableArray array];
    for(unsigned side=0;side<2;side++) {
        NSDictionary *t=scenario[@"teams"][side];NSArray *players=t[@"players"];
        auto team=*(unsigned char**)(match+0x15370+side*8),manager=*(unsigned char**)(team+0x640);
        if(team[0x73d]<players.count)fail("insufficient_native_carriers",83);
        *(uint32_t*)(manager+0x30d0)|=1; // Serialized human-controlled input.
        unsigned char creator[16]={};extraTeamBits(t,creator);
        for(NSDictionary *ins in t[@"instructions"])for(auto o:fm27_team_options)if(o.group==[ins[@"group"] unsignedIntValue]&&o.value==[ins[@"value"] unsignedIntValue]&&o.bit)creator[o.bit/8]|=1<<(o.bit%8);
        for(unsigned offset:{0x18e0u,0x20a0u,0x2860u}) {memcpy(manager+offset,creator,16);manager[offset+0x25]=[t[@"mentality"] unsignedCharValue];}
        for(unsigned i=0;i<players.count;i++) {
            auto actor=*(unsigned char**)(team+0x140+i*8);scenarioActors[side][i]=actor;
            NSDictionary *p=players[i];for(unsigned a=0;a<69;a++)actor[0x478+a]=[p[@"attributes"][a] unsignedCharValue];
            for(NSString *field in p[@"profile"])if(!profileField(actor,field.intValue,[p[@"profile"][field] unsignedIntValue],true,team))fail("profile_input_rejected",83);
            uint32_t key=personKey(actor);if(key==UINT32_MAX)fail("native_person_key_missing",83);
            [scenarioRoster addObject:@{@"side":@(side),@"slot":@(i),@"nativeID":@(key),@"playerID":p[@"id"],@"name":p[@"name"]}];
        }
        applySetPieces(manager,t[@"setPieces"],side);
        for(unsigned phase=0;phase<2;phase++)for(unsigned i=0;i<11;i++) {
            NSDictionary *c=t[@"phases"][phase][i];auto cell=manager+(phase?0x1c40:0x1920)+i*0x48;
            *(uint32_t*)cell=[c[@"position"] unsignedIntValue];*(uint64_t*)(cell+64)=roleValue(c);
            // A replacement input vector uses the engine's own allocator. Old
            // input storage is retained until this disposable process exits.
            auto entry=(uint64_t*)call<void*>(0x4aee72c,size_t(24));entry[0]=roleValue(c)&0xfffffffbf91fffffULL;entry[1]=instructionFlags(c);entry[2]=markingTarget(c);
            *(uint64_t**)(cell+8)=entry;*(uint64_t**)(cell+16)=entry+3;*(uint64_t**)(cell+24)=entry+3;
            manager[0x1fb4+i]=i; // Both phases use the same player's slot.
        }
    }
}
static void verifyScenario(unsigned char *match) {
    if(!scenario)return;begin("verify_workbench_inputs");
    for(unsigned side=0;side<2;side++) {
        NSDictionary *t=scenario[@"teams"][side];NSArray *players=t[@"players"];
        auto team=*(unsigned char**)(match+0x15370+side*8),manager=*(unsigned char**)(team+0x640);
        verifySetPieces(manager,t[@"setPieces"],side);
        // Match preparation must initialize all carrier objects before reducing
        // the eligible roster, as in the upstream native adapter.
        team[0x73d]=(unsigned char)players.count;
        unsigned char expected[16]={};extraTeamBits(t,expected);
        for(NSDictionary *ins in t[@"instructions"])for(auto o:fm27_team_options)if(o.group==[ins[@"group"] unsignedIntValue]&&o.value==[ins[@"value"] unsignedIntValue]&&o.bit)expected[o.bit/8]|=1<<(o.bit%8);
        if(!(*(uint32_t*)(manager+0x30d0)&1)||memcmp(expected,manager+0x18e0,16)||memcmp(expected,manager+0x2860,16)||manager[0x2885]!=[t[@"mentality"] intValue])fail("native_team_input_mismatch",84);
        for(unsigned i=0;i<players.count;i++) {
            auto actor=*(unsigned char**)(team+0x140+i*8);if(actor!=scenarioActors[side][i])fail("native_lineup_mismatch",84);
            for(unsigned a=0;a<69;a++)if(actor[0x478+a]!=[players[i][@"attributes"][a] unsignedCharValue])fail("native_attributes_mismatch",84);
            for(NSString *field in players[i][@"profile"])if(!profileField(actor,field.intValue,[players[i][@"profile"][field] unsignedIntValue],false,team)){event(@"profile_mismatch",@{@"field":field,@"side":@(side),@"slot":@(i),@"requested":players[i][@"profile"][field],@"preparedCohesion":@(actor[0xca0])});fail("native_profile_mismatch",84);}
            if(i>=11)continue;
            for(unsigned phase=0;phase<2;phase++) {
                NSDictionary *c=t[@"phases"][phase][i];
                for(auto actual:{manager+(phase?0x1c40:0x1920)+i*0x48,manager+(phase?0x2bc0:0x28a0)+i*0x48,actor+(phase?0xdb0:0xcd8)}) {
                    auto entry=cellEntry(actual);
                    if(*(uint32_t*)actual!=[c[@"position"] unsignedIntValue]||*(uint64_t*)(actual+64)!=roleValue(c)||!entry||entry[1]!=instructionFlags(c)||entry[2]!=markingTarget(c))fail("native_player_tactic_mismatch",84);
                }
            }
        }
    }
    event(@"workbench_readback_verified",@{@"configurationSHA256":scenarioHash,@"roster":scenarioRoster,@"verifiedPlayers":@22,@"phases":@2,@"afterOriginalPreparation":@YES});
}
