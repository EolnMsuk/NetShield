#import "../Sources/Shared.h"
#import <assert.h>
#import <stdio.h>

// UI entry points are intentionally not exercised by this host model test.
void NSShowDashboard(void) {}
void NSPresentNext(void) {}
@interface MemoryBroker : NSBroker
@property(nonatomic) NSUInteger saves;
@property(nonatomic, copy) NSDictionary *savedState;
@end
@implementation MemoryBroker
- (void)save {
    self.saves++;
    self.savedState = @{@"version": @3, @"enabled": @(self.enabled), @"prompts": @(self.prompts), @"strict": @(self.strict),
        @"rules": [self.rules copy], @"names": [self.names copy]};
}
@end

int main(void) {
    @autoreleasepool {
        MemoryBroker *fresh = [[MemoryBroker alloc] initWithState:nil];
        assert(!fresh.enabled && !fresh.prompts && !fresh.strict);
        NSBroker *malformed = [[NSBroker alloc] initWithState:@{@"enabled": @"yes", @"prompts": @"yes"}];
        assert(!malformed.enabled && !malformed.prompts);
        MemoryBroker *broker = [[MemoryBroker alloc] initWithState:
            @{@"rules": @{@"legacy": @1, @"out": @2, @"both": @3}, @"enabled": @YES}];
        assert(!broker.strict); // Preserve the stable default on upgrade.
        assert([broker.rules[@"legacy"] isEqual:@0]);
        assert([broker.rules[@"out"] isEqual:@2]);
        assert([broker.rules[@"both"] isEqual:@3]);
        NSMutableDictionary *info = [@{@"identity": @"test.app", @"name": @"Test", @"host": @"", @"port": @0,
            @"direction": @(NSOutbound), @"kind": @"register", @"pid": @100,
            @"hooks": @YES, @"extraHooks": @4} mutableCopy];
        NSDictionary *reply = [broker check:@"check" userInfo:info];
        assert([reply[@"mask"] intValue] == NSUnknown);
        assert([reply[@"strict"] isEqual:@NO]);
        broker.strict = YES;
        reply = [broker check:@"check" userInfo:info];
        assert([reply[@"strict"] isEqual:@YES]);
        [broker save];
        NSBroker *strictReload = [[NSBroker alloc] initWithState:broker.savedState];
        assert(strictReload.strict);
        broker.saves = 0;
        assert(broker.pending.count == 1); // Prompt even before a socket hook fires.
        assert(broker.clients.count == 1);
        assert(![broker.clients[@"test.app"][@"observed"] boolValue]);
        assert([broker.events.firstObject[@"result"] isEqual:@"Client registered"]);
        [broker check:@"check" userInfo:info];
        assert(broker.pending.count == 1 && broker.events.count == 1);
        [broker setRule:NSInbound identity:@"test.app"];
        assert(broker.rules[@"test.app"] == nil && broker.saves == 0);
        [broker setRule:NSOutbound identity:@"test.app"];
        assert(broker.pending.count == 0 && broker.saves == 1);
        info[@"kind"] = @"socket";
        info[@"direction"] = @(NSInbound);
        [broker check:@"check" userInfo:info];
        assert([broker.events.firstObject[@"result"] isEqual:@"Blocked"]);
        assert([broker.clients[@"test.app"][@"observed"] boolValue]);
        info[@"direction"] = @(NSOutbound);
        [broker check:@"check" userInfo:info];
        assert([broker.events.firstObject[@"result"] isEqual:@"Allowed"]);
        info[@"kind"] = @"register";
        [broker check:@"check" userInfo:info];
        assert([broker.clients[@"test.app"][@"observed"] boolValue]);
        info[@"pid"] = @101;
        [broker check:@"check" userInfo:info];
        assert(![broker.clients[@"test.app"][@"observed"] boolValue]);
        [broker removeRule:@"test.app"];
        [broker check:@"check" userInfo:info];
        assert(broker.pending.count == 1);
        [broker setRule:0 identity:@"test.app"];
        assert(broker.pending.count == 0);
        broker.enabled = NO;
        info[@"identity"] = @"other.app";
        [broker check:@"check" userInfo:info];
        assert(broker.pending.count == 0); // Disabled protection does not prompt on launch.
        broker.enabled = YES;
        info[@"identity"] = @"pending.app";
        [broker check:@"check" userInfo:info];
        assert(broker.pending.count > 0 && broker.clients.count > 0 && broker.events.count > 0);
        assert(broker.rules.count > 0 && broker.names.count > 0);
        broker.enabled = YES;
        broker.prompts = YES;
        broker.ipcOnline = YES;
        NSUInteger savesBeforeReset = broker.saves;
        [broker resetToDefaults];
        assert(!broker.enabled && !broker.prompts && broker.ipcOnline && !broker.strict);
        assert(broker.rules.count == 0 && broker.names.count == 0);
        assert(broker.pending.count == 0 && broker.events.count == 0 && broker.clients.count == 0);
        assert(broker.saves == savesBeforeReset + 1);
        NSBroker *reloaded = [[NSBroker alloc] initWithState:broker.savedState];
        assert(!reloaded.enabled && !reloaded.prompts && !reloaded.strict && reloaded.rules.count == 0 && reloaded.names.count == 0);
        reply = [broker check:@"check" userInfo:info];
        assert([reply[@"mask"] intValue] == NSUnknown && ![reply[@"enabled"] boolValue]);
        assert(broker.pending.count == 0 && broker.clients.count == 1);
        broker.ipcOnline = NO;
        [broker resetToDefaults];
        assert(!broker.ipcOnline); // Reset cannot claim a failed listener is healthy.
        assert(broker.pending.count == 0 && broker.clients.count == 0);
        puts("Broker registration, diagnostics, rules, migration and reset tests passed");
    }
    return 0;
}
