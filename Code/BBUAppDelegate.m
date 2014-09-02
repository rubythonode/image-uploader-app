//
//  BBUAppDelegate.m
//  image-uploader
//
//  Created by Boris Bügling on 13/08/14.
//  Copyright (c) 2014 Contentful GmbH. All rights reserved.
//

#import <DJProgressHUD/DJProgressHUD.h>
#import <SSKeychain/SSKeychain.h>

#import "BBUAppDelegate.h"
#import "BBUHelpView.h"
#import "CMAClient+SharedClient.h"

static NSString* const kClientID = @"Your-OAuth-Client-Id";

@interface BBUAppDelegate ()

@property (nonatomic, readonly) BBUHelpView* helpView;
@property (nonatomic, readonly) NSView* mainView;

@end

#pragma mark -

@implementation BBUAppDelegate

@synthesize helpView = _helpView;

#pragma mark -

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self andSelector:@selector(getUrl:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];

    if ([SSKeychain passwordForService:kContentfulServiceType account:kContentfulServiceType].length == 0) {
        [self startOAuthFlow];
    } else {
        [self fetchSpaces];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    return YES;
}

- (void)fetchSpaces {
    [DJProgressHUD showStatus:NSLocalizedString(@"Fetching Spaces...", nil)
                     FromView:self.mainView];

    [[CMAClient sharedClient] fetchAllSpacesWithSuccess:^(CDAResponse *response, CDAArray *array) {
        [self fillMenuWithSpaces:array.items];

        self.logoutButton.action = @selector(logoutClicked:);
        self.logoutButton.enabled = YES;
        self.logoutButton.target = self;

        [DJProgressHUD dismiss];
    } failure:^(CDAResponse *response, NSError *error) {
        [DJProgressHUD dismiss];

        NSAlert* alert = [NSAlert alertWithError:error];
        [alert runModal];
    }];
}

- (void)fillMenuWithSpaces:(NSArray*)spaces {
    self.spaceSelection.enabled = YES;

    while ([self.spaceSelectionMenu.itemArray count] > 1) {
        [self.spaceSelectionMenu removeItemAtIndex:1];
    }

    spaces = [spaces sortedArrayUsingComparator:^NSComparisonResult(CMASpace* space1, CMASpace* space2) {
        return [space1.name localizedStandardCompare:space2.name];
    }];
    [self selectSpace:spaces[0]];

    [spaces enumerateObjectsUsingBlock:^(CMASpace* space, NSUInteger idx, BOOL *stop) {
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:space.name
                                                          action:@selector(spaceSelected:)
                                                   keyEquivalent:@""];
        menuItem.representedObject = space;
        [self.spaceSelectionMenu addItem:menuItem];
    }];
}

- (void)getUrl:(NSAppleEventDescriptor*)event withReplyEvent:(NSAppleEventDescriptor*)replyEvent {
    [self.helpView removeFromSuperview];
    [DJProgressHUD dismiss];

    NSString* url = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];

    NSArray* components = [url componentsSeparatedByString:@"#"];
    if (components.count == 2 && [components[1] hasPrefix:@"access_token"]) {
        components = [components[1] componentsSeparatedByString:@"&"];
        if (components.count < 1) {
            return;
        }

        components = [components[0] componentsSeparatedByString:@"="];
        if (components.count != 2) {
            return;
        }

        [SSKeychain setPassword:components[1]
                     forService:kContentfulServiceType
                        account:kContentfulServiceType];

        [self fetchSpaces];
    }
}

- (BBUHelpView *)helpView {
    if (!_helpView) {
        _helpView = [[BBUHelpView alloc] initWithFrame:self.mainView.bounds];
    }

    return _helpView;
}

- (void)logoutClicked:(id)sender {
    [SSKeychain deletePasswordForService:kContentfulServiceType account:kContentfulServiceType];
    [self startOAuthFlow];
}

- (NSView*)mainView {
    return [[NSApp windows][0] contentView];
}

- (void)selectSpace:(CMASpace*)space {
    self.spaceSelection.label = space.name;
    [CMAClient sharedClient].sharedSpaceKey = space.identifier;
}

- (void)spaceSelected:(NSMenuItem*)menuItem {
    [self selectSpace:menuItem.representedObject];
}

- (void)startOAuthFlow {
    self.helpView.helpText = NSLocalizedString(@"Please log into Contentful with your browser.", nil);
    [self.mainView addSubview:self.helpView];

    [DJProgressHUD showStatus:NSLocalizedString(@"Waiting for authentication...", nil)
                     FromView:self.helpView];

    NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"https://be.contentful.com/oauth/authorize?response_type=token&client_id=%@&redirect_uri=contentful-uploader%%3a%%2f%%2ftoken&token&scope=content_management_manage", kClientID]];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

@end
