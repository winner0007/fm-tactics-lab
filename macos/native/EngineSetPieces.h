// Original routine objects and virtual setters. No hand-written match events.
static const unsigned spVectors[]={0x15e8,0x1618,0x1678,0x16a8,0x1648,0x1600,0x1630,0x1690,0x16c0,0x1660};
static const uint16_t spAllowed[]={0x0fda,0xf024,0x105a,0x8020,0x0bf0,0xc40c,0xf400,0x0bf0};
static unsigned char *priorityVector(unsigned char *manager,unsigned id) {
    if(id==0)return manager+0x8b0;
    if(id==1)return manager+0x8c8;
    if(id<12)return manager+0x6e8+(id-2)*24;
    if(id<20)return manager+0x7d8+(id-12)*24;
    return nullptr;
}
static bool validStrategy(unsigned kind,unsigned value) {
    if(kind==0||kind==1||kind==4||kind==9)return value==255;
    if(value<=2)return true;
    return (value==3&&(kind==5||kind==7||kind==8))||(value==4&&(kind==7||kind==8))||(kind==7&&value==6);
}
static void validateSetPieces(NSDictionary *sp,unsigned rosterCount) {
    if(!sp)return;
    if(![sp isKindOfClass:NSDictionary.class]||![sp[@"routines"] isKindOfClass:NSArray.class]||[sp[@"routines"] count]!=10||![sp[@"throwStyles"] isKindOfClass:NSArray.class]||[sp[@"throwStyles"] count]!=3||![sp[@"priorities"] isKindOfClass:NSDictionary.class])fail("invalid_setpieces",83);
    for(id style in sp[@"throwStyles"])if(!number(style,1))fail("invalid_throw_style",83);
    for(NSString *key in sp[@"priorities"]) {
        if(key.intValue<0||key.intValue>=20)fail("invalid_setpiece_priority",83);
        id list=sp[@"priorities"][key];if(![list isKindOfClass:NSArray.class]||[list count]>rosterCount)fail("invalid_setpiece_priority",83);
        std::set<unsigned> seen;for(id p in list)if(!number(p,rosterCount-1)||!seen.insert([p unsignedIntValue]).second)fail("invalid_setpiece_priority",83);
    }
    for(unsigned kind=0;kind<10;kind++) {
        NSArray *variants=sp[@"routines"][kind];if(![variants isKindOfClass:NSArray.class]||variants.count<1||variants.count>3)fail("invalid_routine_count",83);
        for(NSDictionary *r in variants) {
            if(![r isKindOfClass:NSDictionary.class]||!number(r[@"frequency"],2)||!number(r[@"strategy"],255)||!validStrategy(kind,[r[@"strategy"] unsignedIntValue])||!number(r[@"swing"],255))fail("invalid_routine_strategy",83);
            unsigned swing=[r[@"swing"] unsignedIntValue];if((kind==5||kind==7)?swing>1:swing!=255)fail("invalid_routine_swing",83);
            NSArray *groups=r[@"groups"],*priority=r[@"priority"],*backups=r[@"backups"];
            if(![groups isKindOfClass:NSArray.class]||groups.count!=8||![priority isKindOfClass:NSArray.class]||![backups isKindOfClass:NSArray.class]||backups.count!=8)fail("invalid_routine_groups",83);
            std::set<unsigned> order;for(id g in priority)if(!number(g,7)||!order.insert([g unsignedIntValue]).second)fail("invalid_routine_order",83);
            std::set<unsigned> expected=kind>=5?std::set<unsigned>{4,5,6,7}:(kind==0||kind==4)?std::set<unsigned>{0,1,2}:std::set<unsigned>{0,1,2,3};
            if(order!=expected)fail("invalid_routine_order",83);
            unsigned total=0;
            for(unsigned g=0;g<8;g++) {
                NSArray *tasks=groups[g],*fallback=backups[g];
                if(![tasks isKindOfClass:NSArray.class]||tasks.count>10||![fallback isKindOfClass:NSArray.class]||fallback.count!=tasks.count||(!order.count(g)&&tasks.count))fail("invalid_routine_tasks",83);
                for(id task in tasks)if(!number(task,15)||!(spAllowed[g]&(1<<[task unsignedIntValue])))fail("invalid_routine_task",83);
                for(id task in fallback)if(!number(task,15))fail("invalid_routine_backup",83);
                total+=tasks.count;
            }
            if(total!=(kind>=5?9:10))fail("setpiece_assignment_count",83);
        }
    }
}
template<class T>static void replaceVector(unsigned char *vector,const std::vector<T> &values) {
    T *start=nullptr;
    if(!values.empty()){start=(T*)call<void*>(0x4aee72c,values.size()*sizeof(T));memcpy(start,values.data(),values.size()*sizeof(T));}
    *(T**)vector=start;*(T**)(vector+8)=start?start+values.size():nullptr;*(T**)(vector+16)=start?start+values.size():nullptr;
}
static void applySetPieces(unsigned char *manager,NSDictionary *sp,unsigned side) {
    if(!sp)return;
    for(unsigned kind=0;kind<10;kind++) {
        auto vector=manager+spVectors[kind];auto begin=*(unsigned char***)vector,end=*(unsigned char***)(vector+8);
        if(begin==end||end-begin>3)fail("native_routine_missing",83);
        auto source=*begin;auto vt=*(void***)source;
        if(((unsigned char(*)(void*))vt[7])(source)!=kind)fail("native_routine_type_mismatch",83);
        std::vector<unsigned char*> objects;
        for(NSDictionary *r in sp[@"routines"][kind]) {
            auto obj=(unsigned char*)call<void*>(0x4aee72c,size_t(0x158));memset(obj,0,0x158);*(void***)obj=vt;
            ((void(*)(void*,void*))vt[3])(obj,source);
            *(uint32_t*)(obj+0x10)=0x4e554c4c;obj[0x14]=[r[@"frequency"] unsignedCharValue];obj[0x15]=0;
            if([r[@"strategy"] intValue]!=255)((void(*)(void*,unsigned char))vt[21])(obj,[r[@"strategy"] unsignedCharValue]);
            if([r[@"swing"] intValue]!=255)((void(*)(void*,unsigned char))vt[22])(obj,[r[@"swing"] unsignedCharValue]);
            std::vector<unsigned char> fallback;
            for(unsigned g=0;g<8;g++) {
                unsigned char *entry=nullptr;for(unsigned j=0;j<8;j++)if(obj[0x18+j*0x20]==g)entry=obj+0x18+j*0x20;
                if(!entry)fail("native_routine_category_missing",83);
                std::vector<unsigned char> tasks;for(NSNumber *n in r[@"groups"][g])tasks.push_back(n.unsignedCharValue);
                replaceVector(entry+8,tasks);
                NSArray *backs=r[@"backups"][g];for(unsigned j=0;j<backs.count;j++)if([backs[j] intValue]){fallback.push_back(g);fallback.push_back(j);fallback.push_back([backs[j] unsignedCharValue]);}
            }
            std::vector<unsigned char> order;for(NSNumber *n in r[@"priority"])order.push_back(n.unsignedCharValue);
            replaceVector(obj+0x118,order);replaceVector(obj+0x130,fallback);objects.push_back(obj);
        }
        replaceVector(vector,objects);
    }
    for(unsigned i=0;i<3;i++)manager[0x16d8+i]=[sp[@"throwStyles"][i] unsignedCharValue];
    for(unsigned id=0;id<20;id++) {
        std::vector<uint32_t> keys;
        for(NSNumber *n in sp[@"priorities"][[NSString stringWithFormat:@"%u",id]])keys.push_back(personKey(scenarioActors[side][n.unsignedIntValue]));
        replaceVector(priorityVector(manager,id),keys);
    }
    *(uint32_t*)(manager+0x8e0)=0x4e554c4c;
    for(NSNumber *n in sp[@"priorities"][@"0"])if(n.unsignedIntValue<11){*(uint32_t*)(manager+0x8e0)=personKey(scenarioActors[side][n.unsignedIntValue]);break;}
}
static void verifySetPieces(unsigned char *manager,NSDictionary *sp,unsigned side) {
    if(!sp)return;
    for(unsigned kind=0;kind<10;kind++) {
        auto vector=manager+spVectors[kind];auto begin=*(unsigned char***)vector,end=*(unsigned char***)(vector+8);
        NSArray *variants=sp[@"routines"][kind];if(end-begin!=variants.count)fail("setpiece_count_readback",84);
        for(unsigned v=0;v<variants.count;v++) {
            auto obj=begin[v];auto vt=*(void***)obj;NSDictionary *r=variants[v];
            if(obj[0x14]!=[r[@"frequency"] intValue]||((unsigned char(*)(void*))vt[19])(obj)!=[r[@"strategy"] intValue]||((unsigned char(*)(void*))vt[20])(obj)!=[r[@"swing"] intValue])fail("setpiece_strategy_readback",84);
            for(unsigned g=0;g<8;g++) {
                unsigned char *entry=nullptr;for(unsigned j=0;j<8;j++)if(obj[0x18+j*0x20]==g)entry=obj+0x18+j*0x20;
                if(!entry)fail("setpiece_category_readback",84);
                auto a=*(unsigned char**)(entry+8),b=*(unsigned char**)(entry+16);NSArray *tasks=r[@"groups"][g];if(b-a!=tasks.count)fail("setpiece_tasks_readback",84);
                for(unsigned j=0;j<tasks.count;j++)if(a[j]!=[tasks[j] intValue])fail("setpiece_tasks_readback",84);
            }
            auto a=*(unsigned char**)(obj+0x118),b=*(unsigned char**)(obj+0x120);NSArray *order=r[@"priority"];
            if(b-a!=order.count)fail("setpiece_order_readback",84);
            for(unsigned j=0;j<order.count;j++)if(a[j]!=[order[j] intValue])fail("setpiece_order_readback",84);
            std::vector<unsigned char> expected;
            for(unsigned g=0;g<8;g++)for(unsigned j=0;j<[r[@"backups"][g] count];j++)if([r[@"backups"][g][j] intValue]){expected.push_back(g);expected.push_back(j);expected.push_back([r[@"backups"][g][j] unsignedCharValue]);}
            a=*(unsigned char**)(obj+0x130);b=*(unsigned char**)(obj+0x138);
            if(b-a!=expected.size()||!std::equal(expected.begin(),expected.end(),a))fail("setpiece_backups_readback",84);
        }
    }
    for(NSNumber *n in sp[@"priorities"][@"0"])if(n.unsignedIntValue<11){
        unsigned slot=manager[0x3521]; // Original selector at 44f1cec.
        if(slot!=n.unsignedIntValue)fail("captain_readback",84);
        event(@"captain_readback_verified",@{@"side":@(side),@"slot":@(slot)});break;
    }
    for(unsigned i=0;i<3;i++)if(manager[0x16d8+i]!=[sp[@"throwStyles"][i] intValue])fail("throw_style_readback",84);
    for(unsigned id=0;id<20;id++) {
        auto vector=priorityVector(manager,id);auto a=*(uint32_t**)vector,b=*(uint32_t**)(vector+8);NSArray *list=sp[@"priorities"][[NSString stringWithFormat:@"%u",id]];
        if(b-a!=list.count)fail("setpiece_priority_readback",84);
        for(unsigned i=0;i<list.count;i++)if(a[i]!=personKey(scenarioActors[side][[list[i] unsignedIntValue]]))fail("setpiece_priority_readback",84);
    }
    event(@"setpieces_readback_verified",@{@"side":@(side),@"types":@10});
}
