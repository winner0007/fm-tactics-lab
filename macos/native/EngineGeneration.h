// Original AI preparation is a separate disposable process. Its output becomes
// an ordinary, verified fixed input for the match process; no carrier may leak.
static bool generatingTactics=false;
static void prepareGeneration(unsigned char *match) {
    if(!generatingTactics)return;
    if(!engine2503222 || !scenario)fail("generation_requires_updated_engine",87);
    for(unsigned side=0;side<2;side++) {
        auto team=*(unsigned char**)(match+0x15370+side*8),manager=*(unsigned char**)(team+0x640);
        NSDictionary *input=scenario[@"teams"][side];
        // Both registered and actor-pool counts must agree before preparation.
        team[0x73d]=team[0x73e]=(unsigned char)[input[@"players"] count];
        if(![input[@"generation"] isKindOfClass:NSDictionary.class])continue;
        NSDictionary *coach=input[@"generation"];
        if(coach[@"parameters"]) {
            NSArray *profile=coach[@"parameters"],*codes=coach[@"formationCodes"];
            if(![profile isKindOfClass:NSArray.class]||profile.count!=52||![codes isKindOfClass:NSArray.class]||codes.count!=8)fail("invalid_ai_coach",87);
            for(unsigned i=0;i<52;i++){if(!number(profile[i],100))fail("invalid_ai_coach",87);manager[0x2ff8+i]=[profile[i] unsignedCharValue];}
            for(unsigned i=0;i<8;i++){if(!number(codes[i],64))fail("invalid_ai_formation",87);manager[0x30c8+i]=[codes[i] unsignedCharValue];}
        }
        *(uint32_t*)(manager+0x30d0)&=~1u;
    }
}
static void finishGeneration(unsigned char *match) {
    if(!generatingTactics)return;
    NSMutableArray *teams=[NSMutableArray array];
    for(unsigned side=0;side<2;side++) {
        auto team=*(unsigned char**)(match+0x15370+side*8),manager=*(unsigned char**)(team+0x640);
        NSDictionary *input=scenario[@"teams"][side];unsigned count=(unsigned)[input[@"players"] count];
        NSMutableArray *order=[NSMutableArray array];std::set<unsigned> seen;
        for(unsigned i=0;i<count;i++) {
            auto actor=*(unsigned char**)(team+0x140+i*8);unsigned original=count;
            for(unsigned j=0;j<count;j++)if(actor==scenarioActors[side][j])original=j;
            if(original==count || !seen.insert(original).second)fail("ai_selected_unknown_carrier",87);
            for(unsigned a=0;a<69;a++)if(actor[0x478+a]!=[input[@"players"][original][@"attributes"][a] unsignedCharValue])fail("ai_player_attributes_changed",87);
            for(NSString *field in input[@"players"][original][@"profile"])if(!profileField(actor,field.intValue,[input[@"players"][original][@"profile"][field] unsignedIntValue],false,team))fail("ai_player_profile_changed",87);
            [order addObject:@(original)];
        }
        NSMutableString *profile=[NSMutableString string];for(unsigned i=0;i<52;i++)[profile appendFormat:@"%02x",manager[0x2ff8+i]];
        NSDictionary *coach=input[@"generation"];
        if(coach[@"parameters"]) {
            for(unsigned i=0;i<52;i++)if(manager[0x2ff8+i]!=[coach[@"parameters"][i] unsignedCharValue])fail("ai_coach_readback_mismatch",87);
            for(unsigned i=0;i<8;i++)if(manager[0x30c8+i]!=[coach[@"formationCodes"][i] unsignedCharValue])fail("ai_formation_readback_mismatch",87);
        }
        [teams addObject:@{@"side":@(side),@"order":order,@"fields":tacticFields(manager+0x1800),@"coachProfile":profile}];
    }
    event(@"native_tactics_generated",@{@"accepted":@YES,@"teams":teams,@"seed":@(*(uint32_t*)(match+0x18)),@"configurationSHA256":scenarioHash,@"tick":@(*(int*)(match+0x154dc))});
    _exit(0);
}
