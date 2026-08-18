#import <Cocoa/Cocoa.h>

static NSString *const kFanCtlPath = @"/usr/local/bin/fanctl";

@interface FanRow : NSObject
@property NSInteger index;
@property NSInteger actualRPM;
@property NSInteger minRPM;
@property NSInteger maxRPM;
@property NSInteger targetRPM;
@end

@implementation FanRow
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic) NSStatusItem *statusItem;
@property(nonatomic) NSPanel *panel;
@property(nonatomic) NSTextField *modeLabel;
@property(nonatomic) NSTextField *fan0Label;
@property(nonatomic) NSTextField *fan1Label;
@property(nonatomic) NSTextField *statusLabel;
@property(nonatomic) NSButton *maxButton;
@property(nonatomic) NSButton *autoButton;
@property(nonatomic) NSTimer *refreshTimer;
@property(nonatomic) BOOL busy;
@property(nonatomic, copy) NSString *mode;
@property(nonatomic) id rightClickMonitor;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.mode = @"…";
    [self buildStatusItem];
    [self buildPanel];
    [self refresh];
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
                                                         target:self
                                                       selector:@selector(refresh)
                                                       userInfo:nil
                                                        repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.refreshTimer forMode:NSRunLoopCommonModes];
}

- (void)buildStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSStatusBarButton *button = self.statusItem.button;
    if (@available(macOS 11.0, *)) {
        button.image = [NSImage imageWithSystemSymbolName:@"fanblades"
                                 accessibilityDescription:@"Fan Control"];
        button.image.template = YES;
    } else {
        button.title = @"Fan";
    }
    button.toolTip = @"Left click toggles Max/Auto. Right click opens the panel.";
    button.target = self;
    button.action = @selector(toggleModeFromStatusItem);
    [button sendActionOn:NSEventMaskLeftMouseUp];

    __weak AppDelegate *weakSelf = self;
    self.rightClickMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:(NSEventMaskRightMouseDown | NSEventMaskRightMouseUp)
                                                                   handler:^NSEvent *(NSEvent *event) {
        AppDelegate *strongSelf = weakSelf;
        if (event.window == strongSelf.statusItem.button.window) {
            if (event.type == NSEventTypeRightMouseDown) {
                [strongSelf showPanel];
            }
            return nil;
        }
        return event;
    }];
}

- (void)buildPanel {
    NSRect frame = NSMakeRect(0, 0, 320, 292);
    self.panel = [[NSPanel alloc] initWithContentRect:frame
                                            styleMask:(NSWindowStyleMaskTitled |
                                                       NSWindowStyleMaskClosable |
                                                       NSWindowStyleMaskFullSizeContentView |
                                                       NSWindowStyleMaskNonactivatingPanel)
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
    self.panel.title = @"Fan Control";
    self.panel.titlebarAppearsTransparent = YES;
    self.panel.titleVisibility = NSWindowTitleHidden;
    self.panel.level = NSFloatingWindowLevel;
    self.panel.hidesOnDeactivate = NO;
    self.panel.releasedWhenClosed = NO;
    self.panel.becomesKeyOnlyIfNeeded = YES;
    [self.panel setFrameAutosaveName:@"FanControlPanel"];

    NSVisualEffectView *fx = [[NSVisualEffectView alloc] initWithFrame:self.panel.contentView.bounds];
    fx.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    fx.material = NSVisualEffectMaterialSidebar;
    fx.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    fx.state = NSVisualEffectStateActive;
    self.panel.contentView = fx;

    NSTextField *title = [self labelWithString:@"Mac fans" size:20 weight:NSFontWeightSemibold];
    title.alignment = NSTextAlignmentCenter;

    self.modeLabel = [self labelWithString:@"Reading…" size:13 weight:NSFontWeightMedium];
    self.modeLabel.alignment = NSTextAlignmentCenter;
    self.modeLabel.textColor = [NSColor secondaryLabelColor];

    self.maxButton = [self actionButton:@"Max" action:@selector(setMax)];
    self.autoButton = [self actionButton:@"Auto" action:@selector(setAuto)];

    self.fan0Label = [self labelWithString:@"Fan 0" size:13 weight:NSFontWeightRegular];
    self.fan0Label.alignment = NSTextAlignmentCenter;
    self.fan0Label.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular];
    self.fan1Label = [self labelWithString:@"Fan 1" size:13 weight:NSFontWeightRegular];
    self.fan1Label.alignment = NSTextAlignmentCenter;
    self.fan1Label.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular];

    self.statusLabel = [self labelWithString:@"Max pins the fans until Auto, sleep, or reboot."
                                        size:11
                                      weight:NSFontWeightRegular];
    self.statusLabel.alignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = [NSColor tertiaryLabelColor];
    self.statusLabel.usesSingleLineMode = NO;
    [self.statusLabel setPreferredMaxLayoutWidth:240];
    self.statusLabel.lineBreakMode = NSLineBreakByWordWrapping;

    NSButton *quitButton = [NSButton buttonWithTitle:@"Quit" target:NSApp action:@selector(terminate:)];
    quitButton.bezelStyle = NSBezelStyleAccessoryBarAction;
    quitButton.controlSize = NSControlSizeSmall;
    quitButton.font = [NSFont systemFontOfSize:11];

    NSStackView *stack = [NSStackView stackViewWithViews:@[
        title,
        self.modeLabel,
        self.maxButton,
        self.autoButton,
        self.fan0Label,
        self.fan1Label,
        self.statusLabel,
        quitButton
    ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.edgeInsets = NSEdgeInsetsMake(36, 20, 16, 20);
    [stack setCustomSpacing:14 afterView:self.modeLabel];
    [stack setCustomSpacing:16 afterView:self.autoButton];
    [stack setCustomSpacing:4 afterView:self.fan0Label];
    [stack setCustomSpacing:12 afterView:self.fan1Label];
    [fx addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:fx.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:fx.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:fx.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:fx.bottomAnchor],
        [self.maxButton.widthAnchor constraintEqualToConstant:240],
        [self.autoButton.widthAnchor constraintEqualToConstant:240],
        [self.maxButton.heightAnchor constraintEqualToConstant:34],
        [self.autoButton.heightAnchor constraintEqualToConstant:34],
    ]];
}

- (NSTextField *)labelWithString:(NSString *)string size:(CGFloat)size weight:(NSFontWeight)weight {
    NSTextField *field = [NSTextField labelWithString:string];
    field.font = [NSFont systemFontOfSize:size weight:weight];
    field.selectable = NO;
    return field;
}

- (NSButton *)actionButton:(NSString *)title action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.controlSize = NSControlSizeLarge;
    button.font = [NSFont systemFontOfSize:15 weight:NSFontWeightMedium];
    return button;
}

- (void)toggleModeFromStatusItem {
    if ([self.mode isEqualToString:@"max"]) {
        [self setAuto];
        return;
    }
    [self setMax];
}

- (void)showPanel {
    NSStatusBarButton *itemButton = self.statusItem.button;
    NSRect itemRect = [itemButton.window convertRectToScreen:itemButton.frame];
    NSRect panelRect = self.panel.frame;
    CGFloat x = NSMidX(itemRect) - panelRect.size.width / 2.0;
    CGFloat y = NSMinY(itemRect) - panelRect.size.height - 8;
    [self.panel setFrameOrigin:NSMakePoint(floor(x), floor(y))];
    [self.panel makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)refresh {
    if (self.busy) {
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *error = nil;
        NSArray<FanRow *> *fans = [self readFans:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                self.modeLabel.stringValue = @"Helper missing";
                self.fan0Label.stringValue = @"";
                self.fan1Label.stringValue = @"";
                self.statusLabel.stringValue = error;
                self.statusLabel.textColor = [NSColor systemRedColor];
                return;
            }
            [self applyFans:fans];
        });
    });
}

- (void)applyFans:(NSArray<FanRow *> *)fans {
    if (fans.count == 0) {
        self.modeLabel.stringValue = @"No fans";
        self.fan0Label.stringValue = @"";
        self.fan1Label.stringValue = @"";
        return;
    }

    BOOL allMax = YES;
    NSArray<NSTextField *> *labels = @[self.fan0Label, self.fan1Label];
    for (NSUInteger i = 0; i < labels.count; i++) {
        if (i >= fans.count) {
            labels[i].stringValue = @"";
            continue;
        }
        FanRow *fan = fans[i];
        if (fan.maxRPM <= 0 || fan.targetRPM < fan.maxRPM - 40) {
            allMax = NO;
        }
        labels[i].stringValue = [NSString stringWithFormat:@"Fan %ld   %ld rpm  (target %ld)",
                                 (long)fan.index,
                                 (long)fan.actualRPM,
                                 (long)fan.targetRPM];
    }

    self.mode = allMax ? @"max" : @"auto";
    if (allMax) {
        self.modeLabel.stringValue = @"Mode  ·  Max";
        self.statusLabel.stringValue = @"Pinned at hardware max until Auto, sleep, or reboot.";
    } else {
        self.modeLabel.stringValue = @"Mode  ·  Auto";
        self.statusLabel.stringValue = @"Apple is controlling the fans.";
    }
    self.statusLabel.textColor = [NSColor tertiaryLabelColor];
    [self updateButtonStates];
    [self updateStatusIcon:allMax];
}

- (void)updateButtonStates {
    BOOL enabled = !self.busy;
    self.maxButton.enabled = enabled;
    self.autoButton.enabled = enabled;
}

- (void)updateStatusIcon:(BOOL)isMax {
    if (@available(macOS 11.0, *)) {
        NSString *name = isMax ? @"fanblades.fill" : @"fanblades";
        self.statusItem.button.image = [NSImage imageWithSystemSymbolName:name
                                                 accessibilityDescription:@"Fan Control"];
        self.statusItem.button.image.template = YES;
    }
}

- (void)setMax {
    [self runCommand:@"max" pending:@"Setting max…"];
}

- (void)setAuto {
    [self runCommand:@"auto" pending:@"Returning to auto…"];
}

- (void)runCommand:(NSString *)command pending:(NSString *)pending {
    if (self.busy) {
        return;
    }
    self.busy = YES;
    [self updateButtonStates];
    self.statusLabel.stringValue = pending;
    self.statusLabel.textColor = [NSColor secondaryLabelColor];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *error = nil;
        BOOL ok = [self runFanCtl:command error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO;
            if (!ok) {
                self.statusLabel.stringValue = error ?: @"Command failed.";
                self.statusLabel.textColor = [NSColor systemRedColor];
                [self updateButtonStates];
                return;
            }
            [self refresh];
        });
    });
}

- (NSArray<FanRow *> *)readFans:(NSString **)error {
    NSString *output = [self outputFromExecutable:kFanCtlPath arguments:@[@"list"] useSudo:NO error:error];
    if (!output) {
        return nil;
    }
    NSMutableArray<FanRow *> *fans = [NSMutableArray array];
    for (NSString *line in [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        FanRow *row = [self parseFanLine:line];
        if (row) {
            [fans addObject:row];
        }
    }
    return fans;
}

- (FanRow *)parseFanLine:(NSString *)line {
    int index = 0;
    int actual = 0;
    int min = 0;
    int max = 0;
    int target = 0;
    NSInteger matched = sscanf(
        line.UTF8String,
        "Fan %d: actual=%d min=%d max=%d target=%d",
        &index,
        &actual,
        &min,
        &max,
        &target
    );
    if (matched != 5) {
        return nil;
    }
    FanRow *row = [[FanRow alloc] init];
    row.index = index;
    row.actualRPM = actual;
    row.minRPM = min;
    row.maxRPM = max;
    row.targetRPM = target;
    return row;
}

- (BOOL)runFanCtl:(NSString *)command error:(NSString **)error {
    NSString *output = [self outputFromExecutable:kFanCtlPath arguments:@[command] useSudo:YES error:error];
    return output != nil;
}

- (NSString *)outputFromExecutable:(NSString *)path
                         arguments:(NSArray<NSString *> *)arguments
                           useSudo:(BOOL)useSudo
                             error:(NSString **)error {
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
        if (error) {
            *error = @"Install the helper at /usr/local/bin/fanctl.";
        }
        return nil;
    }

    NSTask *task = [[NSTask alloc] init];
    NSPipe *outPipe = [NSPipe pipe];
    NSPipe *errPipe = [NSPipe pipe];
    task.standardOutput = outPipe;
    task.standardError = errPipe;
    if (useSudo) {
        task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/sudo"];
        NSMutableArray<NSString *> *args = [NSMutableArray arrayWithObjects:@"-n", path, nil];
        [args addObjectsFromArray:arguments];
        task.arguments = args;
    } else {
        task.executableURL = [NSURL fileURLWithPath:path];
        task.arguments = arguments;
    }

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        if (error) {
            *error = launchError.localizedDescription;
        }
        return nil;
    }
    [task waitUntilExit];

    NSData *outData = [outPipe.fileHandleForReading readDataToEndOfFile];
    NSData *errData = [errPipe.fileHandleForReading readDataToEndOfFile];
    NSString *outText = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding] ?: @"";
    NSString *errText = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] ?: @"";

    if (task.terminationStatus != 0) {
        if (error) {
            NSString *combined = [errText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (combined.length == 0) {
                combined = [outText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
            if ([combined containsString:@"password"] || task.terminationStatus == 1) {
                *error = @"sudo needs a password. Run sudo -n true in a terminal, or add a NOPASSWD rule.";
            } else {
                *error = combined.length ? combined : @"fanctl failed.";
            }
        }
        return nil;
    }
    return outText;
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyAccessory;
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
