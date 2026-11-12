// Experimental, version-locked original-engine host. Not a simulator.
// Runs only in a disposable child process against the user's installed game.
// No on-disk game changes, executable patches, or synthetic readiness flags.
#import <Foundation/Foundation.h>
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <sys/ucontext.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
#include <cstdio>
#include <cstring>
#include <cstdint>
#include <initializer_list>
#include <cmath>

static uintptr_t base;
static const char *stage = "start";
static void event(NSString *name, NSDictionary *details = @{}) {
    NSMutableDictionary *row = [details mutableCopy];
    row[@"event"] = name;
    NSData *json = [NSJSONSerialization dataWithJSONObject:row options:NSJSONWritingSortedKeys error:nil];
    write(1, json.bytes, json.length); write(1, "\n", 1);
}
static void begin(const char *name) { stage=name; event(@"stage", @{@"name":@(name)}); }
static void fail(const char *reason, int code) { event(@"failed", @{@"stage":@(stage),@"reason":@(reason),@"simulationReady":@NO,@"matchesExecuted":@0}); _exit(code); }
static void fault(int sig, siginfo_t *info, void *context) {
    auto *u = (ucontext_t *)context;
    char line[512];
    int n = snprintf(line, sizeof(line), "{\"event\":\"native_fault\",\"stage\":\"%s\",\"signal\":%d,\"pcRVA\":\"0x%llx\",\"lrRVA\":\"0x%llx\",\"address\":\"%p\",\"matchesExecuted\":0}\n", stage, sig,
      (unsigned long long)(u->uc_mcontext->__ss.__pc-base),
      (unsigned long long)(u->uc_mcontext->__ss.__lr-base), info->si_addr);
    write(1, line, n); _exit(128+sig);
}
#include "EngineProfiles.h"
static void *at(uintptr_t rva) { return (void *)(base+engineRVA(rva)); }
template<class R, class... A> static R call(uintptr_t rva, A... args) {
    return ((R(*)(A...))at(rva))(args...);
}
static void *slot(uintptr_t rva) { return *(void **)at(rva); }
extern "C" void fm_call_sret(void *fn, void *out, void *a0, void *a1=nullptr, void *a2=nullptr, void *a3=nullptr);
static NSString *hashFile(NSString *path) {
    NSFileHandle *f = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!f) return nil;
    CC_SHA256_CTX ctx; CC_SHA256_Init(&ctx);
    for (;;) { NSData *part=[f readDataOfLength:1024*1024]; if (!part.length) break; CC_SHA256_Update(&ctx,part.bytes,(CC_LONG)part.length); }
    [f closeFile]; unsigned char digest[32]; CC_SHA256_Final(digest,&ctx);
    NSMutableString *result=[NSMutableString string]; for (unsigned char c:digest) [result appendFormat:@"%02x",c]; return result;
}

#include "EngineScenario.h"
#include "EngineTactics.h"
#include "EngineStatistics.h"
#include "EngineStrategy.h"
#include "EngineGoals.h"

// Plain statistics records retain their field layout on this profile. Verified
// against Mac producers: 493eaf4 (xG), 493d140/493d668 (shots),
// 493f508..524 (passes), 493d7c4 (goals), 493ccb4 (cards),
// 49a231c (possession ticks). The canonical player vector is +0x250.
static void emitStatistics(unsigned char *context) {
    NSMutableArray *teams=[NSMutableArray array],*players=[NSMutableArray array];
    auto home=*(unsigned char**)(context+0x68),away=*(unsigned char**)(context+0x70);
    unsigned total=*(unsigned*)(home+0x7c)+*(unsigned*)(away+0x7c);
    if(!total) fail("possession_stats_missing",82);
    for(unsigned side=0;side<2;side++) {
        auto stats=side?away:home;
        double xg=*(float*)(stats+0x60);
        unsigned shots=stats[0x16f],onTarget=stats[0x170];
        unsigned passes=*(uint16_t*)(stats+0xd8),complete=*(uint16_t*)(stats+0xda);
        if(!std::isfinite(xg)||xg<0||xg>100||onTarget>shots||complete>passes) fail("invalid_team_statistics",82);
        auto start=*(unsigned char***)(stats+0x250),end=*(unsigned char***)(stats+0x258);
        if(end<start||end-start<11||end-start>26) fail("invalid_player_statistics_vector",82);
        NSMutableSet *ids=[NSMutableSet set];
        unsigned sumShots=0,sumTarget=0,sumPasses=0,sumComplete=0,sumCrosses=0,sumCompletedCrosses=0,yellow=0,red=0;double sumXg=0;
        for(auto p=start;p!=end;p++) {
            auto row=*p; NSNumber *identity=@(*(uint32_t*)(row+0x18));
            if([ids containsObject:identity]) fail("duplicate_player_statistics_identity",82);
            [ids addObject:identity];
            double pxg=*(float*)(row+0x1c);
            if(!std::isfinite(pxg)||pxg<0||pxg>100||row[0x91]>row[0x90]||row[0xbb]>row[0xba]) fail("invalid_player_statistics",82);
            NSMutableDictionary *values=[@{@"goals":@(row[0x8b]),@"shots":@(row[0x90]),@"shots_on_target":@(row[0x91]),@"passes":@(row[0xba]),@"completed_passes":@(row[0xbb]),@"xg":@(pxg),@"yellow_cards":@(row[0xa6]),@"red_cards":@(row[0xa7])} mutableCopy];
            if(engine2503222) {
                values[@"crosses"]=@(unsigned(row[0x9a])+row[0x9b]);values[@"completed_crosses"]=@(row[0x9a]);
                sumCrosses+=unsigned(row[0x9a])+row[0x9b];sumCompletedCrosses+=row[0x9a];
            }
            if(finalGoals) {
                unsigned assists=0,goals=0;
                for(NSDictionary *g in finalGoals)if([g[@"side"] unsignedIntValue]==side) {
                    if([g[@"nativeID"] isEqual:identity]&&[g[@"type"] intValue]!=1)goals++;
                    if([g[@"assistID"] isEqual:identity])assists++;
                }
                if(goals!=row[0x8b])fail("final_goals_player_mismatch",82);
                values[@"assists"]=@(assists);
            }
            bool selected=!scenario;
            if(scenario)for(NSDictionary *p in scenarioRoster)if([p[@"side"] unsignedIntValue]==side&&[p[@"nativeID"] isEqual:identity])selected=true;
            if(selected)[players addObject:@{@"side":@(side),@"nativeID":identity,@"statistics":values}];
            else for(NSNumber *value in values.allValues)if(value.doubleValue!=0)fail("unselected_player_participated",84);
            sumShots+=row[0x90];sumTarget+=row[0x91];sumPasses+=row[0xba];sumComplete+=row[0xbb];sumXg+=pxg;yellow+=row[0xa6];red+=row[0xa7];
        }
        if(sumShots!=shots||sumTarget!=onTarget||sumPasses!=passes||sumComplete!=complete||fabs(sumXg-xg)>0.001) fail("team_player_statistics_mismatch",82);
        NSMutableDictionary *values=[@{@"xg":@(xg),@"shots":@(shots),@"shots_on_target":@(onTarget),@"passes":@(passes),@"completed_passes":@(complete),@"possession":@(100.0*(*(unsigned*)(stats+0x7c))/total),@"yellow_cards":@(yellow),@"red_cards":@(red)} mutableCopy];
        if(engine2503222) {
            if(sumCrosses!=unsigned(stats[0x17f])+stats[0x180]||sumCompletedCrosses!=stats[0x17f])fail("team_player_crosses_mismatch",82);
            [values addEntriesFromDictionary:cumulativeStatistics(stats)];
        }
        [teams addObject:@{@"side":@(side),@"statistics":values}];
    }
    event(@"native_match_statistics",@{@"teams":teams,@"players":players,@"totalsVerified":@YES});
}

int main(int argc, char **argv) {
    bool exportTAC=argc==7&&!strcmp(argv[2],"--export-tactic");
    bool importTAC=argc==4&&!strcmp(argv[2],"--import-plan");
    bool importFMF=argc==4&&!strcmp(argv[2],"--import-tactic");
    if (!exportTAC && argc != 2 && argc != 4 && argc != 6) return 64;
    bool overrideSeed=argc>=4&&!exportTAC&&!importTAC&&!importFMF;
    uint32_t requestedSeed=0;
    if(overrideSeed) {
        char *end=nullptr; unsigned long long value=strtoull(argv[3],&end,10);
        if(strcmp(argv[2],"--seed")||!argv[3][0]||*end||value>UINT32_MAX||argv[3][0]=='-') return 64;
        requestedSeed=(uint32_t)value;
    }
    setvbuf(stdout,nullptr,_IONBF,0);
    struct rlimit core={0,0}; setrlimit(RLIMIT_CORE,&core);
    struct sigaction sa={}; sa.sa_sigaction=fault; sa.sa_flags=SA_SIGINFO;
    for (int sig:{SIGSEGV,SIGBUS,SIGILL,SIGABRT,SIGALRM}) sigaction(sig,&sa,nullptr);
    alarm(45);
    double started=NSProcessInfo.processInfo.systemUptime;
    @autoreleasepool {
        if(argc==6||exportTAC) {
          if(!exportTAC&&strcmp(argv[4],"--scenario"))return 64;
          NSString *scenarioPath=@(argv[exportTAC?3:5]);
          NSData *bytes=[NSData dataWithContentsOfFile:scenarioPath];
          if(!bytes||bytes.length>1000000)fail("invalid_scenario_file",83);
          scenario=[NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil];
          scenarioHash=hashFile(scenarioPath);validateScenario();
        }
        NSString *app=@(argv[1]);
        NSString *plugin=[app stringByAppendingPathComponent:@"Contents/PlugIns/game_plugin.bundle/Contents/MacOS/game_plugin"];
        begin("verify_engine_profile");
        NSString *hash=hashFile(plugin);
        if (!selectEngineProfile(hash)) fail("unsupported_engine_binary",65);
        if([scenario[@"schemaVersion"] isEqual:@2]&&!engine2503222)fail("strategy_requires_updated_engine",65);
        begin("load_original_engine");
        void *handle=dlopen(plugin.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL);
        if (!handle) fail(dlerror(),66);
        Dl_info di={}; if (!dladdr(dlsym(handle,"UnityPluginLoad"),&di)) fail("engine_base_missing",66);
        base=(uintptr_t)di.dli_fbase;
        event(@"original_engine_loaded",@{@"sha256":hash,@"architecture":@"arm64"});
        begin("initialize_icu");
        NSString *root=[app stringByAppendingPathComponent:@"Contents/PlugIns/game_plugin.bundle/Contents/Resources"];
        NSString *icu=[root stringByAppendingPathComponent:@"icudt65l.dat"];
        int fd=open(icu.fileSystemRepresentation,O_RDONLY); struct stat st={};
        if(fd<0||fstat(fd,&st)||st.st_size<32) fail("icu_data_missing",67);
        void *data=mmap(nullptr,st.st_size,PROT_READ,MAP_PRIVATE,fd,0); close(fd);
        if(data==MAP_FAILED) fail("icu_map_failed",67);
        auto set=(void(*)(const void*,int*))dlsym(handle,"udata_setCommonData_65");
        auto init=(void(*)(int*))dlsym(handle,"u_init_65");
        auto version=(void(*)(unsigned char*,int*))dlsym(handle,"u_getDataVersion_65");
        if(!set||!init) fail("icu_symbols_missing",67);
        int status=0; unsigned char v[4]={}; set(data,&status); init(&status); if(version) version(v,&status);
        event(@"icu_initialized",@{@"status":@(status),@"dataVersionAvailable":@(version!=nullptr)});
        if(status>0) fail("icu_init_failed",67);
        begin("initialize_native_filesystem");
        int fsStatus=call<int>(0x4424544);
        event(@"native_filesystem_initialized",@{@"status":@(fsStatus),@"rootPresent":@(slot(0x56d5960)!=nullptr)});
        if(fsStatus||!slot(0x56d5960)) fail("filesystem_init_failed",68);
        begin("construct_resource_manager");
        void *resources=call<void *>(0x4aee72c,size_t(0x1a0));
        call<void *>(0x436550c,resources); *(void **)at(0x56a4ae0)=resources;
        event(@"resource_manager_constructed",@{@"bytes":@416});
        begin("construct_structured_data_manager");
        void *structured=call<void *>(0x4aee72c,size_t(0x10));
        call<void *>(0x43db068,structured); *(void **)at(0x56a4c20)=structured;
        call<void>(0x43b6108);
        event(@"structured_data_manager_constructed");
        begin("register_resource_types");
        // Same vector insertion + native type initializer as 0x4378940.
        for(uintptr_t type:{0x56d5dd0,0x56d5d50}) {
            void *value=at(type);
            call<void>(0x436c610,(char*)resources+0xe8,&value);
            auto methods=*(void ***)value;
            ((void(*)(void*))methods[2])(value);
        }
        auto words=(uintptr_t*)resources;
        event(@"resource_types_registered",@{@"count":@((words[0xf0/8]-words[0xe8/8])/8)});
        for (NSString *relative in @[@"shared/data/simatch.fmf", @"shared/data/simatchshared.fmf"]) {
            begin("open_original_archive");
            NSString *path=[root stringByAppendingPathComponent:relative];
            uintptr_t name=0; call<void *>(0x4388ef8,&name,path.fileSystemRepresentation,-1);
            void *file=nullptr, *folder=nullptr;
            fm_call_sret(at(0x4306224),&file,&name,(char*)resources+0x148);
            event(@"native_file_opened",@{@"file":relative,@"success":@(file!=nullptr)});
            if(!file) fail("archive_file_open_failed",68);
            fm_call_sret(at(0x4308a3c),&folder,&file,slot(0x56d5950));
            event(@"native_archive_opened",@{@"file":relative,@"success":@(folder!=nullptr)});
            if(!folder) fail("archive_decode_failed",69);
            begin("register_archive_root");
            uintptr_t folderPath=0;
            fm_call_sret((*(void ***)folder)[5],&folderPath,folder);
            const unsigned *s=(const unsigned *)folderPath;
            event(@"archive_virtual_path",@{@"path":s?[[NSString alloc] initWithBytes:s+1 length:*s encoding:NSUTF8StringEncoding]:@""});
            call<void>(0x4366eb8,resources,&folderPath,at(0x56d63d0));
        }
        event(@"asset_roots_registered",@{@"count":@((words[0x108/8]-words[0x100/8])/0x30)});
        begin("index_original_resources");
        int scan=call<int>(0x436760c,resources);
        event(@"resource_index_built",@{@"status":@(scan),@"indexedKeys":@(words[0xe0/8])});
        if(scan) fail("resource_index_failed",70);
        begin("query_xg_models");
        uintptr_t query[2]={},folders[3]={};
        call<void *>(0x4363e88,query,at(0x573cf28));
        bool found=call<bool>(0x4369268,resources,query,folders);
        event(@"xg_folder_found",@{@"found":@(found),@"entries":@((folders[1]-folders[0])/8)});
        if(!found||folders[0]==folders[1]) fail("xg_models_not_found",71);
        begin("bootstrap_original_match_engine");
        unsigned char input[0x88]; memcpy(input,at(0x5721828),sizeof(input));
        bool initialized=call<bool>(0x4abe840,input,(void*)nullptr);
        event(@"engine_bootstrap_returned",@{@"accepted":@(initialized)});
        if(!initialized) fail("engine_bootstrap_failed",72);
        begin("open_native_fixture_stream");
        NSString *fixture=[root stringByAppendingPathComponent:@"data/game_simulation/test match/match.pkm"];
        if(![hashFile(fixture) isEqualToString:@"39c594c7e876cc0ad325dfa51c377f4cf360840612479ed72d800ec548e504b6"]) fail("fixture_profile_mismatch",73);
        uintptr_t fixturePath=0;
        call<void *>(0x4388ef8,&fixturePath,fixture.fileSystemRepresentation,-1);
        void *fixtureFile=nullptr,*stream=nullptr,*extra=nullptr;
        fm_call_sret(at(0x4306224),&fixtureFile,&fixturePath,(char*)resources+0x148);
        if(!fixtureFile) fail("fixture_open_failed",73);
        fm_call_sret(at(0x4319980),&stream,&fixtureFile,nullptr,&extra);
        event(@"native_recording_stream_opened",@{@"success":@(stream!=nullptr)});
        if(!stream) fail("fixture_decode_failed",74);
        begin("construct_native_match");
        auto match=(unsigned char*)call<void *>(0x4aee72c,size_t(0x15590));
        call<void *>(0x4486a74,match);
        // Original game's benchmark-derived match (27c1b9c..27c1bc0).
        *(void **)match=at(0x55fa258); match[0x15588]=0;
        struct {void *match; uint64_t flags;} threadContext={match,0};
        auto descriptor=at(0x56c4438);
        void **threadSlot=((void **(*)(void*))(*(void**)descriptor))(descriptor);
        *threadSlot=&threadContext;
        event(@"native_match_constructed",@{@"bytes":@0x15590,@"interfacePresent":@(slot(0x5721a08)!=nullptr)});
        begin("deserialize_original_fixture");
        void *reference=stream;
        __atomic_add_fetch((unsigned*)((char*)stream+8),1,__ATOMIC_RELAXED);
        bool accepted=call<bool>(0x4a5988c,match,&reference,slot(0x5721a08),unsigned(0));
        event(@"native_fixture_deserialized",@{@"accepted":@(accepted)});
        if(!accepted) fail("fixture_deserialization_failed",75);
        // Original 0x4488288 loads +0x18 into the PCG seed before preparation.
        uint32_t fixtureSeed=*(uint32_t*)(match+0x18);
        if(overrideSeed) *(uint32_t*)(match+0x18)=requestedSeed;
        event(@"native_input_seed",@{@"fixtureSeed":@(fixtureSeed),@"effectiveSeed":@(*(uint32_t*)(match+0x18)),@"overridden":@(overrideSeed)});
        applyScenario(match);
        if(exportTAC) {if(strcmp(argv[5],"0")&&strcmp(argv[5],"1"))return 64;exportTactic(match,@(argv[4]),unsigned(atoi(argv[5])),@(argv[6]));}
        if(importTAC) importTacticPlan(match,[NSData dataWithContentsOfFile:@(argv[3])],@"导入战术");
        if(importFMF) {NSString *title=nil;NSData *plan=readTacticArchive(resources,@(argv[3]),&title);importTacticPlan(match,plan,title);}
        begin("prepare_original_match");
        call<void>(0x4a5618c,match);
        event(@"native_preparation_returned",@{@"gates":@[@(match[0x15560]),@(match[0x1555e]),@(match[0x15565])],@"tick":@(*(int*)(match+0x154dc))});
        if(match[0x15560]!=1||match[0x1555e]!=1||!match[0x15565]) fail("match_preparation_incomplete",76);
        verifyScenario(match);
        begin("run_original_match");
        // 0x4a56c10 confirms the native result accessor: context +0x18,
        // score pointer method +0x38 (Itanium vtable includes two destructors).
        auto context=*(unsigned char**)(match+0x14e90);
        auto result=*(void**)(context+0x18);
        auto score=(unsigned char*(*)(void*,unsigned))(*(void***)result)[7];
        auto readScore=[&](unsigned side) { auto value=score(result,side); return value?int(*value):-1; };
        event(@"initial_score",@{@"score":@[@(readScore(0)),@(readScore(1))]});
        int previousHome=readScore(0),previousAway=readScore(1);
        if(previousHome||previousAway||*(int*)(match+0x154dc)||*(int*)(match+0x15454)) fail("fixture_not_at_kickoff",81);
        int elapsedClock=0;
        for (int iteration=0;iteration<100000;iteration++) {
            int tick=*(int*)(match+0x154dc),clock=*(int*)(match+0x15454);
            unsigned flags=*(unsigned*)(match+0x154f0);
            int home=readScore(0),away=readScore(1);
            if(home!=previousHome||away!=previousAway) {
                event(@"observed_score_change",@{@"tick":@(tick),@"clock":@(clock),@"score":@[@(home),@(away)]});
                previousHome=home; previousAway=away;
            }
            if(flags&4) {
                if(clock<21600||home<0||away<0) fail("invalid_finished_result",80);
                collectGoals(context,home,away);
                emitStatistics(context);
                if(engine2503222)event(@"native_analysis_verified",@{@"analysisVersion":@2,@"strategySwitchCount":@(strategySwitchCount)});
                event(@"natural_match_finished",@{@"fullMatchCompleted":@YES,@"tick":@(tick),@"clock":@(clock),@"elapsedClock":@(elapsedClock),@"flags":@(flags),@"score":@[@(home),@(away)],@"matchesExecuted":@1,@"source":@"fm_original_engine",@"input":scenario?@"workbench_scenario":@"bundled_test_fixture",@"clockTicksPerMinute":@240,@"seed":@(*(uint32_t*)(match+0x18)),@"elapsedSeconds":@(NSProcessInfo.processInfo.systemUptime-started),@"workbenchApplied":@(scenario!=nil),@"schemaVersion":@(scenario?2:1),@"configurationSHA256":scenarioHash?:@""});
                _exit(0);
            }
            if(tick>=47995) fail("watchdog_boundary_rejected",77);
            evaluateStrategies(match,elapsedClock,home,away);
            int target=tick+1;
            call<void>(0x448a2f4,match,unsigned(1),target);
            int after=*(int*)(match+0x154dc);
            int nextClock=*(int*)(match+0x15454);
            // Match display clock resets to 45:00 after first-half stoppage
            // time. Count only forward clock increments, at single-tick
            // resolution, to plot elapsed play without a backwards x-axis.
            if(nextClock>=clock) elapsedClock+=nextClock-clock;
            else event(@"native_clock_reset",@{@"tick":@(after),@"before":@(clock),@"after":@(nextClock)});
            auto homeStats=*(unsigned char**)(context+0x68),awayStats=*(unsigned char**)(context+0x70);
            if(after%240==0||(*(unsigned*)(match+0x154f0)&4)) event(@"native_match_progress",@{@"tick":@(after),@"clock":@(nextClock),@"elapsedClock":@(elapsedClock),@"flags":@(*(unsigned*)(match+0x154f0)),@"score":@[@(readScore(0)),@(readScore(1))],@"xg":@[@(*(float*)(homeStats+0x60)),@(*(float*)(awayStats+0x60))]});
            if(after==tick && !(*(unsigned*)(match+0x154f0)&4)) fail("match_stalled",78);
        }
        fail("iteration_limit",79);
        _exit(0);
    }
}
