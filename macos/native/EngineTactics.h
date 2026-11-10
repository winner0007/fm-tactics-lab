// Mac counterparts of upstream native_tactic_export/import and native_fmf_probe.
// Only the hash-locked original serializer/parser produces or accepts TAC data.
struct TacticStream {
    void **methods; uint64_t reserved=0; uint32_t error=0,padding=0;
    std::vector<unsigned char> bytes; size_t cursor=0;
};
static void *tacticWrite(void *self,void *source,size_t n) {
    auto s=(TacticStream*)self;
    if(n>4*1024*1024||s->cursor>4*1024*1024-n){s->error=1;return self;}
    if(s->bytes.size()<s->cursor+n)s->bytes.resize(s->cursor+n);
    memcpy(s->bytes.data()+s->cursor,source,n);s->cursor+=n;return self;
}
static void *tacticRead(void *self,void *output,size_t n) {
    auto s=(TacticStream*)self;
    if(n>s->bytes.size()||s->cursor>s->bytes.size()-n){s->error=1;memset(output,0,std::min(n,size_t(4096)));return self;}
    memcpy(output,s->bytes.data()+s->cursor,n);s->cursor+=n;return self;
}
static uint64_t tacticTell(void *self){return ((TacticStream*)self)->cursor;}
static uint64_t tacticSeek(void *self,uint64_t position) {
    auto s=(TacticStream*)self;if(position>s->bytes.size())s->error=1;else s->cursor=position;return 0;
}
static NSData *readTacticArchive(void *resources,NSString *path,NSString **title) {
    begin("decode_original_fmf");
    NSDictionary *attributes=[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if(!attributes||[attributes[NSFileSize] unsignedLongLongValue]>4*1024*1024)fail("invalid_fmf_size",86);
    uintptr_t name=0;call<void*>(0x4388ef8,&name,path.fileSystemRepresentation,-1);
    void *file=nullptr,*folder=nullptr;
    fm_call_sret(at(0x4306224),&file,&name,(char*)resources+0x148);
    if(!file)fail("fmf_open_failed",86);
    fm_call_sret(at(0x4308a3c),&folder,&file,slot(0x56d5950));
    if(!folder)fail("fmf_archive_rejected",86);
    auto children=*(uintptr_t**)((char*)folder+0x38);
    if(!children)fail("fmf_entries_missing",86);
    auto first=(unsigned char**)children[0],last=(unsigned char**)children[1];
    if(last<first||last-first>64)fail("fmf_entries_invalid",86);
    NSData *result=nil;
    for(auto item=first;item<last;item++) {
        auto node=*item;uint64_t size=*(uint64_t*)(node+0x38);
        if(size<16||size>1024*1024)continue;
        void *raw=nullptr;fm_call_sret((*(void***)node)[22],&raw,node,nullptr);
        if(!raw)continue;
        NSMutableData *bytes=[NSMutableData dataWithLength:size];
        ((void*(*)(void*,void*,size_t))(*(void***)raw)[6])(raw,bytes.mutableBytes,size);
        if(*(uint32_t*)((char*)raw+0x10))fail("fmf_entry_read_failed",86);
        const unsigned char magic[]={3,1,0x63,0x61,0x74,0x2e,0x22,0};
        if(memcmp(bytes.bytes,magic,8))continue;
        if(result)fail("fmf_multiple_tactics",86);
        auto text=*(unsigned**)(node+0x18);
        if(!text||*text>4096)fail("fmf_name_invalid",86);
        *title=[[NSString alloc] initWithBytes:text+1 length:*text encoding:NSUTF8StringEncoding];
        if(!*title)fail("fmf_name_invalid",86);
        result=[bytes subdataWithRange:NSMakeRange(8,size-8)];
    }
    if(!result)fail("fmf_tactic_missing",86);
    event(@"native_fmf_decoded",@{@"accepted":@YES,@"name":*title,@"bytes":@(result.length)});return result;
}
static NSDictionary *tacticFields(unsigned char *plan) {
    NSMutableString *bits=[NSMutableString string];for(unsigned i=0;i<16;i++)[bits appendFormat:@"%02x",plan[0xe0+i]];
    NSMutableArray *phases=[NSMutableArray array],*mapping=[NSMutableArray array];
    for(unsigned i=0;i<11;i++)[mapping addObject:@(plan[0x7b4+i])];
    for(unsigned phase=0;phase<2;phase++) {
        NSMutableArray *cells=[NSMutableArray array];
        for(unsigned i=0;i<11;i++) {
            auto cell=plan+(phase?0x440:0x120)+i*0x48;auto entry=cellEntry(cell);
            [cells addObject:@{@"position":@(*(uint32_t*)cell),@"role":[NSString stringWithFormat:@"%llu",*(unsigned long long*)(cell+0x40)],@"flags":[NSString stringWithFormat:@"%llu",entry?(unsigned long long)entry[1]:0],@"targetPlayer":@(entry?((unsigned char*)entry)[20]:255),@"targetPosition":@(entry?*(uint32_t*)((unsigned char*)entry+16):0)}];
        }[phases addObject:cells];
    }
    return @{@"mentality":@(plan[0x105]),@"teamBits":bits,@"mapping":mapping,@"phases":phases};
}
static void exportTactic(unsigned char *match,NSString *output,unsigned side,NSString *title) {
    begin("serialize_original_tactic");
    auto team=*(unsigned char**)(match+0x15370+side*8),plan=*(unsigned char**)(team+0x640)+0x1800;
    call<void*>(0x4388ef8,plan+0x790,title.UTF8String,-1);
    void *methods[9]={};methods[3]=(void*)tacticTell;methods[4]=(void*)tacticSeek;methods[6]=(void*)tacticWrite;
    TacticStream writer={methods};void *reference=&writer;
    bool accepted=call<bool>(0x4a8d728,plan,&reference,unsigned(1));
    if(!accepted||writer.error||writer.bytes.empty())fail("tactic_serialization_failed",85);
    NSData *bytes=[NSData dataWithBytes:writer.bytes.data() length:writer.bytes.size()];
    if(![bytes writeToFile:output options:NSDataWritingAtomic error:nil])fail("tactic_write_failed",85);
    event(@"native_tactic_written",@{@"accepted":@YES,@"bytes":@(bytes.length),@"fields":tacticFields(plan)});_exit(0);
}
static void importTacticPlan(unsigned char *match,NSData *bytes,NSString *title) {
    begin("parse_original_tactic");
    if(bytes.length<8||bytes.length>1024*1024)fail("invalid_tactic_size",86);
    const unsigned char *raw=(const unsigned char*)bytes.bytes;
    if(raw[0]!=0x22||raw[3]!=27||*(uint16_t*)(raw+1)<60||*(uint16_t*)(raw+1)>68)fail("unsupported_tactic_revision",86);
    auto team=*(unsigned char**)(match+0x15370),plan=*(unsigned char**)(team+0x640)+0x1800;
    void *methods[9]={};methods[3]=(void*)tacticTell;methods[4]=(void*)tacticSeek;methods[6]=(void*)tacticRead;
    TacticStream reader={methods};reader.bytes.assign(raw,raw+bytes.length);void *reference=&reader;
    bool accepted=call<bool>(0x4856b6c,plan,&reference,unsigned(1));
    bool tail=reader.cursor==reader.bytes.size()||(reader.bytes.size()-reader.cursor==8&&std::all_of(reader.bytes.begin()+reader.cursor,reader.bytes.end(),[](unsigned char c){return c==0;}));
    if(!accepted||reader.error||!tail)fail("tactic_parse_incomplete",86);
    event(@"native_tactic_parsed",@{@"accepted":@YES,@"consumed":@(reader.cursor),@"bytes":@(bytes.length),@"name":title,@"fields":tacticFields(plan)});_exit(0);
}
