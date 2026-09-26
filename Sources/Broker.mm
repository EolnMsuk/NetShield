#import "Shared.h"
#import <notify.h>
#import <sys/stat.h>

@implementation NSBroker
+ (instancetype)shared {
    static NSBroker *broker;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ broker = [self new]; });
    return broker;
}
- (instancetype)init {
    return [self initWithState:[NSDictionary dictionaryWithContentsOfFile:NSStore]];
}
- (instancetype)initWithState:(NSDictionary *)state {
    if ((self = [super init])) {
        _enabled = [state[@"enabled"] isKindOfClass:NSNumber.class] ? [state[@"enabled"] boolValue] : YES;
        _prompts = [state[@"prompts"] isKindOfClass:NSNumber.class] ? [state[@"prompts"] boolValue] : YES;
        _rules = [NSMutableDictionary new];
        _names = [NSMutableDictionary new];
        NSDictionary *savedRules = state[@"rules"];
        if ([savedRules isKindOfClass:NSDictionary.class]) {
            [savedRules enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
                if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSNumber.class] && NSValidRule([value intValue]))
                    self.rules[key] = @(NSNormalizeStoredRule([value intValue]));
            }];
        }
        NSDictionary *savedNames = state[@"names"];
        if ([savedNames isKindOfClass:NSDictionary.class]) {
            [savedNames enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
                if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSString.class]) self.names[key] = value;
            }];
        }
        _pending = [NSMutableArray new];
        _events = [NSMutableArray new];
        _clients = [NSMutableDictionary new];
        _status = @"Starting broker";
    }
    return self;
}
- (void)save {
    NSDictionary *state = @{@"version": @2, @"enabled": @(_enabled), @"prompts": @(_prompts),
                            @"rules": _rules, @"names": _names};
    if (![state writeToFile:NSStore atomically:YES]) {
        _status = @"Save failed — changes are in memory only";
    } else {
        chmod(NSStore.fileSystemRepresentation, 0600);
        _status = _ipcOnline ? @"Broker online - rules saved" : @"Rules saved - IPC unavailable";
    }
    notify_post(NSChanged);
}
- (void)setRule:(NSInteger)value identity:(NSString *)identity {
    if (!NSSelectableRule((int)value) || !identity.length) return;
    _rules[identity] = @(value);
    NSIndexSet *indices = [_pending indexesOfObjectsPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) {
        return [item[@"identity"] isEqualToString:identity];
    }];
    [_pending removeObjectsAtIndexes:indices];
    [self save];
}
- (void)removeRule:(NSString *)identity {
    [_rules removeObjectForKey:identity];
    [self save];
}
- (NSDictionary *)check:(NSString *)message userInfo:(NSDictionary *)info {
    // Public IPC exposes checks only. No rule mutations or dashboard data API.
    if (![info isKindOfClass:NSDictionary.class]) return @{@"mask": @(-1), @"enabled": @YES};
    NSString *identity = info[@"identity"], *name = info[@"name"], *host = info[@"host"];
    NSNumber *direction = info[@"direction"], *port = info[@"port"];
    if (![identity isKindOfClass:NSString.class] || !identity.length || identity.length > 512 ||
        ![name isKindOfClass:NSString.class] || name.length > 128 ||
        ![host isKindOfClass:NSString.class] || host.length > 128 ||
        ![direction isKindOfClass:NSNumber.class] ||
        (direction.intValue != NSInbound && direction.intValue != NSOutbound) ||
        ![port isKindOfClass:NSNumber.class] || port.intValue < 0 || port.intValue > 65535)
        return @{@"mask": @(-1), @"enabled": @YES};
    BOOL registration = [info[@"kind"] isEqual:@"register"];
    NSDictionary *previous = _clients[identity];
    BOOL newProcess = !previous || ![previous[@"pid"] isEqual:info[@"pid"]];
    if (_clients.count < 2048 || previous) {
        _clients[identity] = @{@"identity": identity, @"name": name, @"date": [NSDate date],
            @"pid": [info[@"pid"] isKindOfClass:NSNumber.class] ? info[@"pid"] : @0,
            @"hooks": @([info[@"hooks"] isEqual:@YES]),
            @"extraHooks": [info[@"extraHooks"] isKindOfClass:NSNumber.class] ? info[@"extraHooks"] : @0,
            @"observed": @(!registration || (!newProcess && [previous[@"observed"] boolValue]))};
    }
    int value = _rules[identity] ? [_rules[identity] intValue] : NSUnknown;
    if (_names.count < 2048 || _names[identity]) _names[identity] = name;
    NSDictionary *event = @{@"identity": identity, @"name": name, @"host": host, @"port": port,
        @"direction": direction, @"date": [NSDate date], @"kind": registration ? @"register" : @"socket",
        @"result": registration ? @"Client registered" : (NSAllows(_enabled, value, direction.intValue) ? @"Allowed" : @"Blocked")};
    // Bound IPC activity/history; each app reports at most once per second normally.
    if (!registration || newProcess) [_events insertObject:event atIndex:0];
    if (_events.count > 250) [_events removeLastObject];
    if (_enabled && value == NSUnknown && _pending.count < 100) {
        BOOL exists = NO;
        for (NSDictionary *item in _pending) if ([item[@"identity"] isEqualToString:identity]) { exists = YES; break; }
        if (!exists) [_pending addObject:[event mutableCopy]];
    }
    return @{@"mask": @(value), @"enabled": @(_enabled)};
}
@end

void NSStartBroker(void) {
    static int token;
    NSBroker *broker = NSBroker.shared;
    BOOL online = NSStartIPCServer(^NSDictionary *(NSDictionary *info) {
        return [broker check:@"check" userInfo:info];
    });
    broker.ipcOnline = online;
    broker.status = online ? @"Broker online" : @"IPC unavailable - loopback listener failed";
    notify_register_dispatch(NSShow, &token, dispatch_get_main_queue(), ^(int t) { NSShowDashboard(); });
    [NSTimer scheduledTimerWithTimeInterval:0.75 repeats:YES block:^(NSTimer *timer) { NSPresentNext(); }];
}
