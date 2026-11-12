// Original FM command application, verified on 27.0.1.2503222 arm64.
// Commands update the current, canonical and on-field tactics without preparing
// a new match or resetting the players' condition, score or set pieces.
static int activePlan[2]={-1,-1},lastPlanClock[2]={-100000,-100000};
static unsigned strategySwitchCount=0;
static bool strategyCondition(int code,int difference,int margin) {
    switch(code){case 0:return true;case 1:return difference<0;case 2:return difference==0;case 3:return difference>0;case 4:return difference>=margin;case 5:return difference<=-margin;default:return false;}
}
static void verifyLiveCell(unsigned char *actual,NSDictionary *c) {
    auto entry=cellEntry(actual);
    if(*(uint32_t*)actual!=[c[@"position"] unsignedIntValue]||*(uint64_t*)(actual+64)!=roleValue(c)||!entry||entry[1]!=instructionFlags(c)||entry[2]!=markingTarget(c))fail("live_tactic_readback_mismatch",84);
}
static void applyLivePlan(unsigned char *match,unsigned side,NSDictionary *plan) {
    auto team=*(unsigned char**)(match+0x15370+side*8),manager=*(unsigned char**)(team+0x640);
    unsigned count=team[0x73e];if(count>26)fail("invalid_active_lineup",84);
    unsigned char *actors[26];uint16_t condition[26];unsigned char slots[26];
    for(unsigned i=0;i<count;i++){actors[i]=*(unsigned char**)(team+0x140+i*8);condition[i]=*(uint16_t*)(actors[i]+0xc88);slots[i]=actors[i][0x1e51];}
    int tick=*(int*)(match+0x154dc),clock=*(int*)(match+0x15454);
    for(unsigned phase=0;phase<2;phase++)for(unsigned i=0;i<11;i++) {
        NSDictionary *c=plan[@"phases"][phase][i];
        alignas(16) unsigned char change[0x60]={};change[0xe]=side;change[0xf]=i;
        auto cell=change+0x10;uint64_t entry[3]={roleValue(c)&0xfffffffbf91fffffULL,instructionFlags(c),markingTarget(c)};
        *(uint32_t*)cell=[c[@"position"] unsignedIntValue];*(uint64_t*)(cell+64)=roleValue(c);
        *(uint64_t**)(cell+8)=entry;*(uint64_t**)(cell+16)=entry+3;*(uint64_t**)(cell+24)=entry+3;
        ((void(*)(void*,void*,void*,void*,void*,void*))(base+(phase?0x4895d7c:0x489290c)))(change,nullptr,nullptr,nullptr,nullptr,match);
    }
    alignas(16) unsigned char change[0x40]={};change[0xe]=side;
    memcpy(change+0x10,manager+0x2860,0x28);memset(change+0x10,0,16);extraTeamBits(plan,change+0x10);
    for(NSDictionary *ins in plan[@"instructions"])for(auto o:fm27_team_options)if(o.group==[ins[@"group"] unsignedIntValue]&&o.value==[ins[@"value"] unsignedIntValue]&&o.bit)change[0x10+o.bit/8]|=1<<(o.bit%8);
    change[0x35]=[plan[@"mentality"] unsignedCharValue];
    ((void(*)(void*,void*,void*,void*,void*,void*))(base+0x4896558))(change,nullptr,nullptr,nullptr,nullptr,match);
    for(unsigned offset:{0x18e0u,0x2860u})if(memcmp(manager+offset,change+0x10,16)||manager[offset+0x25]!=change[0x35])fail("live_team_readback_mismatch",84);
    for(unsigned phase=0;phase<2;phase++)for(unsigned i=0;i<11;i++)for(auto cell:{manager+(phase?0x1c40:0x1920)+i*0x48,manager+(phase?0x2bc0:0x28a0)+i*0x48})verifyLiveCell(cell,plan[@"phases"][phase][i]);
    std::set<unsigned> verifiedSlots;
    for(unsigned i=0;i<count;i++) {
        auto actor=*(unsigned char**)(team+0x140+i*8);unsigned slot=actor[0x1e51];
        if(actor!=actors[i]||slot!=slots[i]||*(uint16_t*)(actor+0xc88)!=condition[i])fail("live_change_reset_player",84);
        if(slot<11 && verifiedSlots.insert(slot).second)for(unsigned phase=0;phase<2;phase++)verifyLiveCell(actor+(phase?0xdb0:0xcd8),plan[@"phases"][phase][slot]);
    }
    if(count!=team[0x73e]||tick!=*(int*)(match+0x154dc)||clock!=*(int*)(match+0x15454))fail("live_change_reset_match",84);
}
static void evaluateStrategies(unsigned char *match,int elapsedClock,int home,int away) {
    if(!scenario)return;
    int clock=*(int*)(match+0x15454),tick=*(int*)(match+0x154dc);
    for(unsigned side=0;side<2;side++) {
        NSDictionary *s=scenario[@"teams"][side][@"strategy"];if(!s)continue;
        if(activePlan[side]<0)activePlan[side]=[s[@"kickoffSlot"] intValue];
        if(elapsedClock-lastPlanClock[side]<[s[@"cooldownMinutes"] intValue]*240)continue;
        int target=[s[@"returnToKickoff"] boolValue]?[s[@"kickoffSlot"] intValue]:activePlan[side];NSString *rule=@"fallback";
        for(NSDictionary *r in s[@"rules"])if(clock/240>=[r[@"fromMinute"] intValue]&&clock/240<=[r[@"throughMinute"] intValue]&&strategyCondition([r[@"condition"] intValue],side?away-home:home-away,[r[@"margin"] intValue])){target=[r[@"target"] intValue];rule=r[@"id"];break;}
        if(target==activePlan[side])continue;
        begin("apply_live_strategy");applyLivePlan(match,side,s[@"plans"][target]);
        auto context=*(unsigned char**)(match+0x14e90),h=*(unsigned char**)(context+0x68),a=*(unsigned char**)(context+0x70);
        event(@"native_strategy_switch",@{@"side":@(side),@"from":@(activePlan[side]),@"to":@(target),@"ruleID":rule,@"tick":@(tick),@"clock":@(clock),@"elapsedClock":@(elapsedClock),@"score":@[@(home),@(away)],@"xg":@[@(*(float*)(h+0x60)),@(*(float*)(a+0x60))],@"statistics":@[cumulativeStatistics(h),cumulativeStatistics(a)],@"readbackVerified":@YES});
        activePlan[side]=target;lastPlanClock[side]=elapsedClock;strategySwitchCount++;stage="run_original_match";
    }
}
