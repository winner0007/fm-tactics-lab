#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <unistd.h>
#include <signal.h>

// Disposable child process. Never call undocumented functions or transplant PE RVAs.
// The parent enforces a timeout as well; _exit avoids invoking plugin teardown
// without the corresponding Unity lifecycle.
int main(int argc, const char **argv) {
    alarm(20);
    @autoreleasepool {
        if (argc != 2) return 64;
        NSString *app = [NSString stringWithUTF8String:argv[1]];
        NSString *plugin = [app stringByAppendingPathComponent:@"Contents/PlugIns/game_plugin.bundle/Contents/MacOS/game_plugin"];
        void *handle = dlopen(plugin.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
        const char *error = handle ? NULL : dlerror();
        NSMutableDictionary *report = [@{@"schema": @1, @"appPath": app, @"loaded": (handle ? @YES : @NO),
            @"architecture": @"arm64", @"simulationReady": @NO, @"matchesExecuted": @0,
            @"timestamp": @([[NSDate date] timeIntervalSince1970]),
            @"error": error ? [NSString stringWithUTF8String:error] : @""} mutableCopy];
        NSArray *names = @[@"UnityPluginLoad", @"UnityPluginUnload",
            @"game_plugin__fm__gameplugin__i_game_plugin_initialise",
            @"game_plugin__fm__gameplugin__i_game_plugin_tick",
            @"simatchplayback__si__match__i_plugin_match_interface_setup"];
        NSMutableDictionary *symbols = [NSMutableDictionary dictionary];
        if (handle) for (NSString *name in names) symbols[name] = (dlsym(handle, name.UTF8String) ? @YES : @NO);
        report[@"symbols"] = symbols;
        NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingSortedKeys error:nil];
        write(STDOUT_FILENO, data.bytes, data.length);
        write(STDOUT_FILENO, "\n", 1);
        _exit(handle ? 0 : 1);
    }
}
