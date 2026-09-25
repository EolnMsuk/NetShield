#import <sys/socket.h>
#import "Shared.h"
#import <dlfcn.h>
#import <rootless.h>

CPDistributedMessagingCenter *NSCreateCenter(void) {
    static void (*apply)(CPDistributedMessagingCenter *);
    static Class centerClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_NOW);
        void *rocket = dlopen(ROOT_PATH("/usr/lib/librocketbootstrap.dylib"), RTLD_NOW);
        if (rocket) apply = (void (*)(CPDistributedMessagingCenter *))dlsym(rocket, "rocketbootstrap_distributedmessagingcenter_apply");
        centerClass = NSClassFromString(@"CPDistributedMessagingCenter");
    });
    if (!centerClass || !apply) return nil;
    CPDistributedMessagingCenter *center = [centerClass centerNamed:NSCenterName];
    apply(center);
    return center;
}
