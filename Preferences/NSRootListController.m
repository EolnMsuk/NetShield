#import <Preferences/PSListController.h>
#import <notify.h>
#import <UIKit/UIKit.h>

@interface NSRootListController : PSListController
@end
@implementation NSRootListController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    UIImage *image = [UIImage imageNamed:@"icon" inBundle:[NSBundle bundleForClass:self.class] compatibleWithTraitCollection:nil];
    UIImageView *icon = [[UIImageView alloc] initWithImage:image];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [icon.widthAnchor constraintEqualToConstant:29].active = YES;
    [icon.heightAnchor constraintEqualToConstant:29].active = YES;
    UILabel *name = [UILabel new];
    name.text = @"NetShield";
    name.font = [UIFont boldSystemFontOfSize:17];
    UIStackView *title = [[UIStackView alloc] initWithArrangedSubviews:@[icon, name]];
    title.axis = UILayoutConstraintAxisHorizontal;
    title.alignment = UIStackViewAlignmentCenter;
    title.spacing = 8;
    self.navigationItem.titleView = title;
}
- (void)openGitHub {
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://github.com/EolnMsuk/NetShield"] options:@{} completionHandler:nil];
}
- (void)openSupport {
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://venmo.com/user/RustOnRails"] options:@{} completionHandler:nil];
}
- (void)openDashboard { notify_post("com.netshield.show-dashboard"); }
@end
