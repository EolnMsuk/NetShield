#import "Shared.h"

@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isUILocked;
@end

static UIWindow *overlay;
static BOOL dashboardOpen;
static BOOL alertOpen;

BOOL NSDeviceLocked(void) {
    Class cls = NSClassFromString(@"SBLockScreenManager");
    id manager = [cls respondsToSelector:@selector(sharedInstance)] ? [cls sharedInstance] : nil;
    return ![manager respondsToSelector:@selector(isUILocked)] || [manager isUILocked];
}

static UIViewController *NSOverlayRoot(void) {
    if (!overlay) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class]) {
                overlay = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
                break;
            }
        }
        if (!overlay) overlay = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        overlay.windowLevel = UIWindowLevelAlert + 1;
        overlay.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        overlay.rootViewController = [UIViewController new];
        overlay.rootViewController.view.backgroundColor = UIColor.clearColor;
    }
    [overlay makeKeyAndVisible];
    return overlay.rootViewController;
}

static void NSHideIfIdle(void) {
    if (!dashboardOpen && !alertOpen) {
        overlay.hidden = YES;
        [overlay resignKeyWindow];
    }
}

static NSString *NSRuleLabel(NSInteger mask) {
    switch (mask) {
        case NSInbound: return @"Allow in · block out";
        case NSOutbound: return @"Allow out · block in";
        case NSBoth: return @"Allow both";
        default: return @"Block both";
    }
}

static void NSChoose(UIViewController *presenter, NSDictionary *item, BOOL editing, void (^done)(void)) {
    if (NSDeviceLocked()) return;
    NSString *identity = item[@"identity"];
    NSString *body = [NSString stringWithFormat:@"%@\n%@\n\nIntercepted traffic is blocked until allowed. In = receive; out = send. Most apps need both. Retry the app after choosing. Applies to Wi-Fi and cellular.",
                      item[@"name"] ?: identity, identity];
    if ([item[@"host"] length]) body = [body stringByAppendingFormat:@"\nDestination: %@:%@", item[@"host"], item[@"port"]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:editing ? @"NetShield · Edit rule" : @"NetShield · Network access" message:body preferredStyle:UIAlertControllerStyleAlert];
    NSArray *labels = @[@"Keep Blocking", @"Allow In Only", @"Allow Out Only", @"Allow Both"];
    for (NSInteger value = 0; value <= 3; value++) {
        [alert addAction:[UIAlertAction actionWithTitle:labels[value] style:value == 0 ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            if (!NSDeviceLocked()) [NSBroker.shared setRule:value identity:identity];
            done();
        }]];
    }
    if (editing) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Delete Rule (Ask Again)" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            if (!NSDeviceLocked()) [NSBroker.shared removeRule:identity];
            done();
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Later (Remain Blocked)" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { done(); }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

@interface NSDashboard : UITableViewController
@property(nonatomic) NSInteger page;
@property(nonatomic, strong) NSArray *rows;
@property(nonatomic, strong) NSTimer *refreshTimer;
@end

@implementation NSDashboard
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"NetShield";
    self.tableView.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    UISegmentedControl *tabs = [[UISegmentedControl alloc] initWithItems:@[@"Requests", @"Activity", @"Rules", @"Settings"]];
    tabs.selectedSegmentIndex = 0;
    [tabs addTarget:self action:@selector(changePage:) forControlEvents:UIControlEventValueChanged];
    tabs.frame = CGRectMake(12, 10, self.view.bounds.size.width - 24, 36);
    tabs.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 56)];
    [header addSubview:tabs];
    self.tableView.tableHeaderView = header;
    [self refresh];
    __weak NSDashboard *weakSelf = self;
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { [weakSelf refresh]; }];
}
- (void)dealloc { [_refreshTimer invalidate]; }
- (void)close {
    [self.refreshTimer invalidate];
    [self dismissViewControllerAnimated:YES completion:^{ dashboardOpen = NO; NSHideIfIdle(); }];
}
- (void)changePage:(UISegmentedControl *)sender { self.page = sender.selectedSegmentIndex; [self refresh]; }
- (void)refresh {
    NSBroker *b = NSBroker.shared;
    if (self.page == 0) self.rows = [b.pending copy];
    else if (self.page == 1) self.rows = [b.events copy];
    else if (self.page == 2) {
        NSMutableArray *rows = [NSMutableArray new];
        for (NSString *key in [[b.rules allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)])
            [rows addObject:@{@"identity": key, @"name": b.names[key] ?: key, @"mask": b.rules[key]}];
        self.rows = rows;
    } else self.rows = @[@"Protection", @"Automatic prompts", @"Clear activity", @"About"];
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.rows.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSBroker *b = NSBroker.shared;
    return [NSString stringWithFormat:@"%@ · %lu pending", b.enabled ? @"Protection ON" : @"Protection OFF", (unsigned long)b.pending.count];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return [NSString stringWithFormat:@"%@\nExperimental socket hooks · third-party injected processes only. Apple processes are exempt. Activity is sampled access checks, not a packet capture. Wi-Fi + cellular share rules.", NSBroker.shared.status];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
    cell.detailTextLabel.numberOfLines = 0;
    cell.textLabel.numberOfLines = 2;
    if (self.page == 3) {
        cell.textLabel.text = self.rows[path.row];
        if (path.row < 2) {
            UISwitch *toggle = [UISwitch new];
            toggle.tag = path.row;
            toggle.on = path.row == 0 ? NSBroker.shared.enabled : NSBroker.shared.prompts;
            [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            cell.detailTextLabel.text = path.row == 0 ? @"Off permits intercepted traffic after the next policy refresh." : @"Off keeps unknown apps blocked; review Requests manually.";
        }
        return cell;
    }
    NSDictionary *item = self.rows[path.row];
    cell.textLabel.text = item[@"name"];
    NSString *detail = item[@"identity"];
    if (self.page == 2) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@", detail, NSRuleLabel([item[@"mask"] integerValue])];
        cell.textLabel.textColor = [item[@"mask"] intValue] == 0 ? UIColor.systemRedColor : UIColor.systemGreenColor;
    } else {
        NSString *time = [NSDateFormatter localizedStringFromDate:item[@"date"] dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@ · %@ · %@\n%@:%@", detail, time,
            [item[@"direction"] intValue] == NSInbound ? @"IN" : @"OUT", item[@"result"], [item[@"host"] length] ? item[@"host"] : @"Socket", item[@"port"]];
        cell.textLabel.textColor = [item[@"result"] isEqualToString:@"Allowed"] ? UIColor.systemGreenColor : UIColor.systemOrangeColor;
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)toggle:(UISwitch *)sender {
    if (NSDeviceLocked()) return;
    if (sender.tag == 0) NSBroker.shared.enabled = sender.on;
    else NSBroker.shared.prompts = sender.on;
    [NSBroker.shared save];
    [self refresh];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (self.presentedViewController || NSDeviceLocked()) return;
    if (self.page != 3) {
        NSDictionary *item = self.rows[path.row];
        NSChoose(self, item, NSBroker.shared.rules[item[@"identity"]] != nil, ^{ [self refresh]; });
    } else if (path.row == 2) {
        [NSBroker.shared.events removeAllObjects];
        [self refresh];
    } else if (path.row == 3) {
        UIAlertController *about = [UIAlertController alertControllerWithTitle:@"NetShield 0.1 · Experimental" message:@"Inspired by PyFirewall. Intercepts selected BSD socket functions in injected third-party processes. It is not a kernel firewall. Network.framework, WebKit helpers, background daemons, direct syscalls and injection-disabled apps may bypass it. Inbound permission controls delivery to the app, not arrival at the device.\n\nRules persist; pending requests and 250 sampled activity entries stay in memory. First attempts fail with EACCES; retry after allowing. Read README before testing." preferredStyle:UIAlertControllerStyleAlert];
        [about addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:about animated:YES completion:nil];
    }
}
@end

void NSShowDashboard(void) {
    if (NSDeviceLocked() || dashboardOpen || alertOpen) return;
    UIViewController *root = NSOverlayRoot();
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[NSDashboard alloc] initWithStyle:UITableViewStyleInsetGrouped]];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    dashboardOpen = YES;
    [root presentViewController:nav animated:YES completion:nil];
}

void NSPresentNext(void) {
    BOOL locked = NSDeviceLocked();
    if (overlay && (dashboardOpen || alertOpen)) overlay.hidden = locked;
    if (locked || dashboardOpen || alertOpen || !NSBroker.shared.enabled || !NSBroker.shared.prompts) return;
    for (NSMutableDictionary *item in NSBroker.shared.pending) {
        if ([item[@"offered"] boolValue]) continue;
        item[@"offered"] = @YES;
        alertOpen = YES;
        NSChoose(NSOverlayRoot(), item, NO, ^{
            // Allow UIKit to finish dismissing before hiding or presenting again.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                alertOpen = NO;
                NSHideIfIdle();
            });
        });
        break;
    }
}
