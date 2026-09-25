#import <Preferences/PSListController.h>
#import <notify.h>

@interface NSRootListController : PSListController
@end
@implementation NSRootListController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (void)openDashboard { notify_post("com.netshield.show-dashboard"); }
@end
