// Final result goals (+0x88), corroborated by the final incident registry
// (context +0x38). Unlike transient score changes, these exclude VAR reversals.
static NSArray *finalGoals;
static void collectGoals(unsigned char *context,int home,int away) {
    if(!engine2503222)return;
    auto result=*(unsigned char**)(context+0x18);auto holder=*(unsigned char***)(result+0x88);
    NSMutableArray *goals=[NSMutableArray array];int counts[2]={};
    if(holder) {
        auto start=holder[0],end=holder[1];
        if(end<start||end-start>3200||(end-start)%16)fail("invalid_final_goal_vector",82);
        auto ib=*(unsigned char***)(context+0x38),ie=*(unsigned char***)(context+0x40);
        if(ie<ib||ie-ib>4096)fail("invalid_final_incident_vector",82);
        for(auto p=start;p<end;p+=16) {
            unsigned side=p[12],type=p[13],minute=p[14],added=p[15],tick=*(uint32_t*)(p+8);
            if(side>1||type>3||minute>120||added>30||tick>=47996)fail("invalid_final_goal",82);
            // This result vector also contains dismissals (type 3). Confirmed
            // against seed 4: registry types 5/15 and the player's red card.
            if(type==3)continue;
            unsigned matches=0;
            for(auto q=ib;q<ie;q++) {
                auto row=*q;unsigned kind=row[0x1f],scoringSide=kind==2?1-row[0x1d]:row[0x1d];
                if(kind==type+1&&scoringSide==side&&*(uint32_t*)(row+0x18)==tick&&row[0x1c]==minute&&row[0x20]==added)matches++;
            }
            if(matches!=1)fail("goal_incident_disagreement",82);
            NSMutableDictionary *g=[@{@"side":@(side),@"nativeID":@(*(uint32_t*)p),@"tick":@(tick),@"type":@(type),@"minute":@(minute),@"added":@(added)} mutableCopy];
            uint32_t assist=*(uint32_t*)(p+4);if(assist!=UINT32_MAX)g[@"assistID"]=@(assist);
            [goals addObject:g];counts[side]++;
        }
    }
    if(counts[0]!=home||counts[1]!=away)fail("final_goals_score_mismatch",82);
    finalGoals=goals;
    event(@"native_final_goals",@{@"goals":goals,@"verified":@YES,@"source":@"original_final_result_and_incident_registry"});
}
