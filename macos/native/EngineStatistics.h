// Cumulative counters on the verified 27.0.1.2503222 profile.
// Cross event names: 49313ec..4931434, enums 19 (completed), 20 (incomplete).
// Producer 4a467fc, jump table 54a05cc: cases 19/20 -> 4a48db0/4a49170.
// Team bytes +17f/+180, player bytes +9a/+9b; attempted = both categories.
static NSDictionary *cumulativeStatistics(unsigned char *stats) {
    return @{@"shots":@(stats[0x16f]),@"shots_on_target":@(stats[0x170]),
        @"passes":@(*(uint16_t*)(stats+0xd8)),@"completed_passes":@(*(uint16_t*)(stats+0xda)),
        @"crosses":@(unsigned(stats[0x17f])+stats[0x180]),@"completed_crosses":@(stats[0x17f]),
        @"possession_ticks":@(*(unsigned*)(stats+0x7c))};
}
