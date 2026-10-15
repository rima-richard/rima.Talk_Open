/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCAppBranding.h"
#import "RimaReleaseConfiguration.h"

#import "TalkAccount.h"
#import "TalkCapabilities.h"
#import "ServerCapabilities.h"
#import "FederatedCapabilities.h"

#import "NextcloudTalk-Swift.h"

typedef enum NCTextColorStyle {
    NCTextColorStyleLight = 0,
    NCTextColorStyleDark
} NCTextColorStyle;

@implementation NCAppBranding

#pragma mark - App configuration

NSString * const talkAppName = @"rima.Chat";
NSString * const filesAppName = @"Nextcloud";
NSString * const copyright = @"© 2026 Nextcloud GmbH";
NSString * const bundleIdentifier = @"de.rima-pflege.chat";
NSString * const groupIdentifier = @"group.de.rima-pflege.chat";
NSString * const appsGroupIdentifier = @"group.de.rima-pflege.chat.apps";
#if DEBUG
NSString * const pushNotificationServer = @"https://talk.rima-pflege.de/push/dev";
#else
#if !RIMA_PRODUCTION_PUSH_CONFIGURATION_VERIFIED
#error rima.Chat production push configuration must be confirmed before a Release build
#endif
NSString * const pushNotificationServer = RIMA_PRODUCTION_PUSH_SERVER_URL;
#endif
NSString * const privacyURL = @"https://rima-pflege.de/rima-chat/datenschutz";
NSString * const supportURL = @"https://rima-pflege.de/rima-chat";
BOOL const isBrandedApp = YES;
BOOL const multiAccountEnabled = YES;
BOOL const useAppsGroup = NO;
BOOL const forceDomain = YES;
NSString * const domain = @"https://talk.rima-pflege.de";
#if DEBUG
NSString * const appAlternateVersion = @"25.0.2 · rima.Chat Entwurf 13";
#else
NSString * const appAlternateVersion = @"";
#endif

+ (NSString *)getAppVersionString
{
    if ([appAlternateVersion length] > 0) {
        return appAlternateVersion;
    }

    NSString *appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return appVersion;
}

#pragma mark - Theming

NSString * const brandColorHex = @"#006873";
NSString * const brandTextColorHex = @"#FFFFFF";
BOOL const customNavigationLogo = NO;
BOOL const useServerThemimg = NO;

+ (UIColor *)brandColor
{
    return [NCUtils colorFromHexString:brandColorHex];
}

+ (UIColor *)brandTextColor
{
    return [NCUtils colorFromHexString:brandTextColorHex];
}

+ (UIColor *)themeColor
{
    UIColor *color = [NCUtils colorFromHexString:brandColorHex];
    if (useServerThemimg) {
        TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
        ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
        if (serverCapabilities && serverCapabilities.color) {
            UIColor *themeColor = [NCUtils colorFromHexString:serverCapabilities.color];
            if (themeColor) {
                color = themeColor;
            }
        }
    }
    return color;
}

+ (UIColor *)themeTextColor
{
    UIColor *textColor = [NCUtils colorFromHexString:brandTextColorHex];
    if (useServerThemimg) {
        TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
        ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
        if (serverCapabilities && serverCapabilities.colorText) {
            UIColor *themeTextColor = [NCUtils colorFromHexString:serverCapabilities.colorText];
            if (themeTextColor) {
                textColor = themeTextColor;
            }
        }
    }
    return textColor;
}

+ (UIColor *)elementColor
{
    // Do not check if using server theming or not for now
    // We could check it once we calculate color element locally
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
    if (serverCapabilities) {
        UIColor *elementColorBright = [NCUtils colorFromHexString:serverCapabilities.colorElementBright];
        UIColor *elementColorDark = [NCUtils colorFromHexString:serverCapabilities.colorElementDark];

        if (elementColorBright && elementColorDark) {
            return [self getDynamicColor:elementColorBright withDarkMode:elementColorDark];
        }

        UIColor *color = [NCUtils colorFromHexString:serverCapabilities.colorElement];
        if (color) {
            return color;
        }
    }
    
    UIColor *elementColor = [NCUtils colorFromHexString:brandColorHex];
    return elementColor;
}

+ (UIColor *)getDynamicColor:(UIColor *)lightModeColor withDarkMode:(UIColor *)darkModeColor
{
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traits) {
        if (traits.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return darkModeColor;
        }
        
        return lightModeColor;
    }];
}

+ (UIImage *)navigationLogoImage
{
    return [[UIImage systemImageNamed:@"bubble.left.and.bubble.right.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

+ (UIColor *)placeholderColor
{
    return [UIColor placeholderTextColor];
}

+ (UIColor *)backgroundColor
{
    return [UIColor systemBackgroundColor];
}

+ (UIColor *)avatarPlaceholderColor
{
    UIColor *light = [NCUtils colorFromHexString:@"#dbdbdb"];
    UIColor *dark = [NCUtils colorFromHexString:@"#3b3b3b"];

    return [self getDynamicColor:light withDarkMode:dark];
}

+ (UIStatusBarStyle)statusBarStyleForBrandColor
{
    return [self statusBarStyleForTextColorStyle:[self brandTextColorStyle]];
}

+ (UIStatusBarStyle)statusBarStyleForThemeColor
{
    if (useServerThemimg) {
        NCTextColorStyle style = [self textColorStyleForBackgroundColor:[self themeColor]];
        return [self statusBarStyleForTextColorStyle:style];
    }
    return [self statusBarStyleForBrandColor];
}

+ (UIStatusBarStyle)statusBarStyleForTextColorStyle:(NCTextColorStyle)style
{
    if (style == NCTextColorStyleDark) {
        return UIStatusBarStyleDarkContent;
    }

    return UIStatusBarStyleLightContent;
}

+ (NCTextColorStyle)brandTextColorStyle
{
    // Dark style when brand text color is black
    if ([brandTextColorHex isEqualToString:@"#000000"]) {
        return NCTextColorStyleDark;
    }
    
    // Light style when brand text color is white
    if ([brandTextColorHex isEqualToString:@"#FFFFFF"]) {
        return NCTextColorStyleLight;
    }
    
    // Check brand-color luma when brand-text-color is neither black nor white
    return [self textColorStyleForBackgroundColor:[self brandColor]];
}

+ (NCTextColorStyle)textColorStyleForBackgroundColor:(UIColor *)color
{
    CGFloat luma = [NCUtils calculateLumaFromColor:color];
    return (luma > 0.6) ? NCTextColorStyleDark : NCTextColorStyleLight;
}

+ (void)styleViewController:(UIViewController *)controller {
    UIColor *themeColor = [NCAppBranding themeColor];

    if (@available(iOS 26.0, *)) {
        controller.navigationController.navigationBar.translucent = YES;
        [controller.view setBackgroundColor:[UIColor systemBackgroundColor]];

        if ([controller isKindOfClass:[UITableViewController class]]) {
            UITableViewController *tableViewController = (UITableViewController *)controller;

            if (tableViewController.tableView.style == UITableViewStyleInsetGrouped) {
                [controller.view setBackgroundColor:[UIColor systemGroupedBackgroundColor]];
            }
        }

        return;
    }

    [controller.navigationController.navigationBar setTitleTextAttributes:@{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]}];
    controller.navigationController.navigationBar.barTintColor = [NCAppBranding themeColor];
    controller.navigationController.navigationBar.tintColor = [NCAppBranding themeTextColor];
    controller.navigationController.navigationBar.translucent = NO;
    controller.tabBarController.tabBar.tintColor = [NCAppBranding themeColor];

    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = themeColor;
    appearance.titleTextAttributes = @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]};
    controller.navigationItem.standardAppearance = appearance;
    controller.navigationItem.compactAppearance = appearance;
    controller.navigationItem.scrollEdgeAppearance = appearance;

    // Fix uisearchcontroller animation
    controller.extendedLayoutIncludesOpaqueBars = YES;

    UISearchController *searchController = controller.navigationItem.searchController;

    if (searchController) {
        searchController.searchBar.searchTextField.backgroundColor = [NCUtils searchbarBGColorForColor:themeColor];
        searchController.searchBar.tintColor = [NCAppBranding themeTextColor];
        [searchController.searchBar setScopeBarButtonTitleTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[NCAppBranding themeTextColor], NSForegroundColorAttributeName, nil] forState:UIControlStateNormal];
        [searchController.searchBar setScopeBarButtonTitleTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[NCAppBranding themeTextColor], NSForegroundColorAttributeName, nil] forState:UIControlStateSelected];
        searchController.searchBar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        controller.navigationItem.preferredSearchBarPlacement = UINavigationItemSearchBarPlacementStacked;

        UITextField *searchTextField = [searchController.searchBar valueForKey:@"searchField"];
        UIButton *clearButton = [searchTextField valueForKey:@"_clearButton"];
        searchTextField.tintColor = [NCAppBranding themeTextColor];
        searchTextField.textColor = [NCAppBranding themeTextColor];
        dispatch_async(dispatch_get_main_queue(), ^{
            // Search bar placeholder
            searchTextField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Search", nil)
                                                                                    attributes:@{NSForegroundColorAttributeName:[[NCAppBranding themeTextColor] colorWithAlphaComponent:0.5]}];
            // Search bar search icon
            UIImageView *searchImageView = (UIImageView *)searchTextField.leftView;
            searchImageView.image = [searchImageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            [searchImageView setTintColor:[[NCAppBranding themeTextColor] colorWithAlphaComponent:0.5]];
            // Search bar search clear button
            UIImage *clearButtonImage = [clearButton.imageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            [clearButton setImage:clearButtonImage forState:UIControlStateNormal];
            [clearButton setImage:clearButtonImage forState:UIControlStateHighlighted];
            [clearButton setTintColor:[NCAppBranding themeTextColor]];
        });

        [controller setNeedsStatusBarAppearanceUpdate];
    }
}

@end
