// Exact binary profiles; offsets are Mach-O arm64 RVAs, never Windows addresses.
// 2503222 entries were relocated through matching functions and their callers.
// Shared object fields are checked by native preparation/readback and statistics.
#pragma once
static bool engine2503222 = false;
static bool selectEngineProfile(NSString *sha) {
    if ([sha isEqualToString:@"774cacde63567fd3901c47719e7a6ed94cc3a0a62e9b94989dcac6b4890ec0e1"]) {engine2503222=false; return true;}
    if ([sha isEqualToString:@"68adfde2e0588458c1830cb7e688855d9c61237973a7eb7a105af5ac4ed112a4"]) {engine2503222=true; return true;}
    return false;
}
static uintptr_t engineRVA(uintptr_t legacy) {
    if (!engine2503222) return legacy;
    switch (legacy) {
        case 0x4306224: return 0x431ee60;
        case 0x4308a3c: return 0x4321678;
        case 0x4319980: return 0x43325bc;
        case 0x4363e88: return 0x437cab0;
        case 0x436550c: return 0x437e134;
        case 0x4366eb8: return 0x437fae0;
        case 0x436760c: return 0x4380234;
        case 0x4369268: return 0x4381e90;
        case 0x436c610: return 0x4385238;
        case 0x4388ef8: return 0x43a1b14;
        case 0x43b6108: return 0x43ced24;
        case 0x43db068: return 0x43f3c08;
        case 0x4424544: return 0x443dfd8;
        case 0x4486a74: return 0x44a1c50;
        case 0x448a2f4: return 0x44a6450;
        case 0x4856b6c: return 0x4906798;
        case 0x4a5618c: return 0x4b70388;
        case 0x4a5988c: return 0x4b721ac;
        case 0x4a8d728: return 0x4905350;
        case 0x4abe840: return 0x4b812c0;
        case 0x4aee72c: return 0x4b885f0;
        case 0x55fa258: return 0x5696258;
        case 0x56a4ae0: return 0x5740ae0;
        case 0x56a4c20: return 0x5740c20;
        case 0x56c4438: return 0x5760470;
        case 0x56d5950: return 0x5771988;
        case 0x56d5960: return 0x5771998;
        case 0x56d5d50: return 0x5771d88;
        case 0x56d5dd0: return 0x5771e08;
        case 0x56d63d0: return 0x5772408;
        case 0x5721828: return 0x57bd858;
        case 0x5721a08: return 0x57bda30;
        case 0x573cf28: return 0x57d8f40;
        default: fail("unmapped_engine_symbol",65); return 0;
    }
}
