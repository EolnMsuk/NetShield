#pragma once
#import <sys/socket.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Policy.h"

#import "IPC.h"
#define NSChanged "com.netshield.rules-changed"
#define NSShow "com.netshield.show-dashboard"
#define NSStore @"/var/mobile/Library/Preferences/com.netshield.state.plist"

void NSStartClient(void);
bool NSCheckSocket(int fd, int direction, const struct sockaddr *address, socklen_t length);
void NSStartBroker(void);
void NSShowDashboard(void);
void NSPresentNext(void);
BOOL NSDeviceLocked(void);

@interface NSBroker : NSObject
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL ipcOnline;
@property(nonatomic) BOOL prompts;
@property(nonatomic, strong) NSMutableDictionary *rules;
@property(nonatomic, strong) NSMutableDictionary *names;
@property(nonatomic, strong) NSMutableArray *pending;
@property(nonatomic, strong) NSMutableArray *events;
@property(nonatomic, copy) NSString *status;
+ (instancetype)shared;
- (NSDictionary *)check:(NSString *)message userInfo:(NSDictionary *)info;
- (void)save;
- (void)setRule:(NSInteger)mask identity:(NSString *)identity;
- (void)removeRule:(NSString *)identity;
@end
