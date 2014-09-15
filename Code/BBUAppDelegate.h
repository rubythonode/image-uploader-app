//
//  BBUAppDelegate.h
//  image-uploader
//
//  Created by Boris Bügling on 13/08/14.
//  Copyright (c) 2014 Contentful GmbH. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class BBUUserInfoView;

@interface BBUAppDelegate : NSObject <NSApplicationDelegate>

@property (weak) IBOutlet NSButton *logoutButton;
@property (weak) IBOutlet NSPopUpButton *spaceSelection;
@property (weak) IBOutlet NSMenu *spaceSelectionMenu;
@property (weak) IBOutlet NSToolbarItem *userInfoItem;
@property (weak) IBOutlet BBUUserInfoView *userInfoView;
@property (weak) IBOutlet NSWindow *window;

@end
