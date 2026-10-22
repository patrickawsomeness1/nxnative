// Native pre-launch graphics menu. Included automatically by project.yml's Sources folder.
// Game-specific patches, MetalFX and frame interpolation MUST NOT be represented as active
// until their rendering backends exist. This screen only sets validated host configuration.
#import <UIKit/UIKit.h>
#include <stdlib.h>
#include <stdio.h>

UIViewController *front_ios_game_root(void);
int front_ios_boot_ok(void);

static NSString *const kPreset = @"DmLaunchGraphicsPreset";
static NSString *const kAdaptive = @"DmLaunchAdaptiveResolution";

@interface DmLaunchViewController : UIViewController
@property(nonatomic, strong) UISegmentedControl *preset;
@property(nonatomic, strong) UISwitch *adaptive;
@property(nonatomic, strong) UILabel *presetDescription;
@end

@implementation DmLaunchViewController

static UILabel *dmLabel(NSString *text, CGFloat size, BOOL heavy, UIColor *color) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.textColor = color;
    label.font = heavy ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    label.numberOfLines = 0;
    return label;
}

- (void)addPlanned:(NSString *)feature detail:(NSString *)detail to:(UIStackView *)stack {
    UILabel *label = dmLabel([NSString stringWithFormat:@"%@ — not available yet\n%@", feature, detail],
                            13, NO, [UIColor colorWithWhite:0.66 alpha:1]);
    [stack addArrangedSubview:label];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.08 blue:0.10 alpha:1];

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor]
    ]];

    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 15;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:24],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:30],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-30],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-60]
    ]];

    [stack addArrangedSubview:dmLabel(@"Game graphics", 29, YES, UIColor.whiteColor)];
    [stack addArrangedSubview:dmLabel(@"Choose your settings before launching. Changes are saved for next time.",
                                       15, NO, [UIColor colorWithWhite:0.78 alpha:1])];
    [stack addArrangedSubview:dmLabel(@"Graphics preset", 18, YES, UIColor.whiteColor)];

    self.preset = [[UISegmentedControl alloc] initWithItems:@[@"Performance", @"Balanced", @"Quality"]];
    NSInteger saved = [NSUserDefaults.standardUserDefaults integerForKey:kPreset];
    self.preset.selectedSegmentIndex = MAX(0, MIN(2, saved));
    [self.preset addTarget:self action:@selector(presetChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:self.preset];

    self.presetDescription = dmLabel(@"", 14, NO, [UIColor colorWithWhite:0.78 alpha:1]);
    [stack addArrangedSubview:self.presetDescription];

    UIStackView *resolutionRow = [UIStackView new];
    resolutionRow.axis = UILayoutConstraintAxisHorizontal;
    resolutionRow.alignment = UIStackViewAlignmentCenter;
    resolutionRow.spacing = 12;
    UILabel *adaptTitle = dmLabel(@"Adaptive 3D resolution", 16, NO, UIColor.whiteColor);
    [resolutionRow addArrangedSubview:adaptTitle];
    self.adaptive = [UISwitch new];
    NSNumber *savedAdaptive = [NSUserDefaults.standardUserDefaults objectForKey:kAdaptive];
    self.adaptive.on = savedAdaptive ? savedAdaptive.boolValue : YES;
    [self.adaptive addTarget:self action:@selector(adaptiveChanged:) forControlEvents:UIControlEventValueChanged];
    [resolutionRow addArrangedSubview:self.adaptive];
    [stack addArrangedSubview:resolutionRow];

    [stack addArrangedSubview:dmLabel(@"The current renderer can lower its internal resolution when frames are slow. The performance preset also uses handheld mode.",
                                       13, NO, [UIColor colorWithWhite:0.67 alpha:1])];

    [stack addArrangedSubview:dmLabel(@"Upcoming rendering features", 18, YES, UIColor.whiteColor)];
    [self addPlanned:@"MetalFX Spatial Upscaling" detail:@"Needs a MetalFX scaler in the presentation pipeline." to:stack];
    [self addPlanned:@"MetalFX Temporal Upscaling" detail:@"Needs frame color, depth and motion-vector integration." to:stack];
    [self addPlanned:@"MetalFX Frame Generation" detail:@"Requires temporal rendering data and correct frame presentation." to:stack];
    [self addPlanned:@"Graphics packs" detail:@"Needs validated per-game patch loading; no patches are installed." to:stack];
    [self addPlanned:@"Outdoor 60 FPS" detail:@"A performance goal, not an unlocked gameplay rate. Requires a tested game-specific timing patch and device profiling." to:stack];

    UIButton *play = [UIButton buttonWithType:UIButtonTypeSystem];
    [play setTitle:front_ios_boot_ok() ? @"Start Game" : @"Game files not found" forState:UIControlStateNormal];
    play.titleLabel.font = [UIFont boldSystemFontOfSize:19];
    play.backgroundColor = [UIColor colorWithRed:0.20 green:0.57 blue:0.41 alpha:1];
    [play setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    play.layer.cornerRadius = 12;
    play.contentEdgeInsets = UIEdgeInsetsMake(14, 24, 14, 24);
    play.enabled = front_ios_boot_ok() != 0;
    if (play.enabled) [play addTarget:self action:@selector(startGame:) forControlEvents:UIControlEventTouchUpInside];
    else play.alpha = 0.5;
    [stack addArrangedSubview:play];
    if (!front_ios_boot_ok()) {
        [stack addArrangedSubview:dmLabel(@"The packaged game files are missing. Add the game's RomFS to the app's Documents/romfs folder before launching.",
                                           13, NO, [UIColor colorWithRed:1 green:0.72 blue:0.55 alpha:1])];
    }
    [self updatePresetDescription];
}

- (void)updatePresetDescription {
    switch (self.preset.selectedSegmentIndex) {
        case 0:
            self.presetDescription.text = @"Handheld mode • 50% maximum 3D scale • prioritize GPU headroom";
            break;
        case 2:
            self.presetDescription.text = @"Docked mode • 100% maximum 3D scale • highest GPU demand";
            break;
        default:
            self.presetDescription.text = @"Handheld mode • 75% maximum 3D scale • balanced clarity and speed";
            break;
    }
}

- (void)presetChanged:(UISegmentedControl *)sender {
    [NSUserDefaults.standardUserDefaults setInteger:sender.selectedSegmentIndex forKey:kPreset];
    [self updatePresetDescription];
}
- (void)adaptiveChanged:(UISwitch *)sender {
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:kAdaptive];
}
- (void)startGame:(UIButton *)sender {
    sender.enabled = NO;
    NSInteger mode = self.preset.selectedSegmentIndex;
    const char *scale = mode == 0 ? "0.5" : mode == 2 ? "1.0" : "0.75";
    const char *opmode = mode == 2 ? "1" : "0";
    // These three environment keys are implemented in dm/host/hle_oe.c.
    // Apply them before any guest or host preload thread is started.
    setenv("DM_OPMODE", opmode, 1);
    setenv("DM_3D_SCALE", scale, 1);
    setenv("DM_3D_SCALE_DYN", self.adaptive.on ? "1" : "0", 1);
    fprintf(stderr, "launcher: preset=%ld opmode=%s scale=%s adaptive=%d\n",
            (long)mode, opmode, scale, self.adaptive.on);
    UIWindow *window = self.view.window;
    if (window) window.rootViewController = front_ios_game_root();
    else sender.enabled = YES;
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}
@end

UIViewController *dm_launch_root(void) { return [DmLaunchViewController new]; }
