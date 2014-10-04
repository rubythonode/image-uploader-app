//
//  BBUImageViewController.m
//  image-uploader
//
//  Created by Boris Bügling on 14/08/14.
//  Copyright (c) 2014 Contentful GmbH. All rights reserved.
//

#import <JNWCollectionView/JNWCollectionView.h>

#import "BBUAppStyle.h"
#import "BBUCollectionView.h"
#import "BBUDraggedFile.h"
#import "BBUDraggedFileFormatter.h"
#import "BBUDragHintView.h"
#import "BBUEmptyViewController.h"
#import "BBUHeaderView.h"
#import "BBUImageCell.h"
#import "BBUImageViewController.h"
#import "BBUS3Uploader+SharedSettings.h"
#import "CMAClient+SharedClient.h"
#import "NSView+Geometry.h"

@interface BBUImageViewController () <BBUCollectionViewDelegate, JNWCollectionViewDataSource, JNWCollectionViewDelegate, JNWCollectionViewGridLayoutDelegate, NSUserNotificationCenterDelegate>

@property (nonatomic, readonly) BBUCollectionView* collectionView;
@property (nonatomic) NSString* currentSpaceId;
@property (nonatomic, readonly) BBUDragHintView* dragHintView;
@property (nonatomic, readonly) NSArray* filteredFiles;
@property (nonatomic) NSMutableArray* files;
@property (weak) IBOutlet NSSegmentedControl *filterSelection;
@property (nonatomic) BBUHeaderView* headerView;
@property (nonatomic, readonly) BBUEmptyViewController* helpViewController;
@property (nonatomic) NSUInteger lastNumberOfUploads;
@property (nonatomic) NSUInteger numberOfUploads;
@property (weak) IBOutlet NSMenu *sortingMenu;
@property (nonatomic) NSInteger sortingType;
@property (nonatomic) NSUInteger totalNumberOfUploads;
@property (nonatomic) NSOperationQueue* uploadQueue;

@end

#pragma mark -

@implementation BBUImageViewController

@synthesize dragHintView = _dragHintView;
@synthesize helpViewController = _helpViewController;

#pragma mark -

- (void)allowResizing:(BOOL)resizing {
    NSWindow* window = [NSApp windows][0];

    if (resizing) {
        [window setStyleMask:[window styleMask] | NSResizableWindowMask];
    } else {
        [window setStyleMask:[window styleMask] & ~NSResizableWindowMask];
    }
}

- (void)awakeFromNib {
    [super awakeFromNib];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowResize)
                                                 name:NSWindowDidResizeNotification
                                               object:nil];


    self.filterSelection.enabled = NO;
    self.filterSelection.action = @selector(filterChanged);
    self.filterSelection.target = self;

    self.uploadQueue = [NSOperationQueue new];
    self.uploadQueue.maxConcurrentOperationCount = 3;

    self.files = [@[] mutableCopy];

    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.draggingDelegate = self;

    JNWCollectionViewGridLayout *gridLayout = [JNWCollectionViewGridLayout new];
    gridLayout.delegate = self;
    gridLayout.itemPaddingEnabled = NO;
    gridLayout.itemSize = CGSizeMake(300, 290);
    self.collectionView.collectionViewLayout = gridLayout;

    [self.collectionView registerClass:BBUImageCell.class
            forCellWithReuseIdentifier:NSStringFromClass(self.class)];
    [self.collectionView registerClass:BBUHeaderView.class
            forSupplementaryViewOfKind:JNWCollectionViewGridLayoutHeaderKind
                   withReuseIdentifier:NSStringFromClass(self.class)];
    [self.collectionView reloadData];

    self.helpViewController.view.hidden = [self collectionView:self.collectionView
                                        numberOfItemsInSection:0] > 0;
    self.helpViewController.view.y = 0.0;
    self.helpViewController.view.width = self.view.window.frame.size.width;

    self.dragHintView.hidden = !self.helpViewController.view.isHidden;
    self.dragHintView.width = self.view.width;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       self.collectionView.backgroundColor = [BBUAppStyle defaultStyle].backgroundColor;
                       self.collectionView.borderType = NSNoBorder;
                   });
}

- (BBUCollectionView *)collectionView {
    return (BBUCollectionView*)self.view;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSWindowDidResizeNotification
                                                  object:nil];
}

- (BBUDraggedFile*)draggedFileAtIndexPath:(NSIndexPath*)indexPath {
    return self.filteredFiles[[indexPath indexAtPosition:1]];
}

- (BBUDragHintView *)dragHintView {
    if (!_dragHintView) {
        _dragHintView = [[BBUDragHintView alloc] initWithFrame:NSMakeRect(0.0, 0.0,
                                                                          self.view.width, 60.0)];
        [self.view.superview addSubview:self.dragHintView];
    }

    return _dragHintView;
}

- (NSArray *)filteredFiles {
    NSPredicate* predicate = nil;

    switch (self.filterSelection.selectedSegment) {
        case 1:
            predicate = [NSPredicate predicateWithBlock:^BOOL(BBUDraggedFile* file,
                                                              NSDictionary *bindings) {
                return file.asset.URL != nil;
            }];
            break;

        case 2:
            predicate = [NSPredicate predicateWithBlock:^BOOL(BBUDraggedFile* file,
                                                              NSDictionary *bindings) {
                return file.error != nil;
            }];
            break;
    }

    NSArray *files = predicate ? [self.files filteredArrayUsingPredicate:predicate] : self.files;

    return [files sortedArrayUsingComparator:^NSComparisonResult(BBUDraggedFile* file1,
                                                                 BBUDraggedFile* file2) {
        switch (self.sortingType) {
            case 2:
                return file1.numberOfBytes > file2.numberOfBytes;

            case 3:
                return [file1.fileType compare:file2.fileType options:NSCaseInsensitiveSearch];

            case 4:
                return [file1.mtime compare:file2.mtime];

            default:
                break;
        }

        return [file1.title compare:file2.title options:NSCaseInsensitiveSearch];
    }];
}

- (BBUEmptyViewController *)helpViewController {
    if (!_helpViewController) {
        _helpViewController = [BBUEmptyViewController new];
        _helpViewController.view.y = self.view.y;
        _helpViewController.view.hidden = YES;
        [self.view.superview addSubview:_helpViewController.view];

        __weak typeof(self) welf = self;
        _helpViewController.browseAction = ^(NSButton* button) {
            NSOpenPanel* openPanel = [NSOpenPanel openPanel];
            openPanel.allowedFileTypes = @[ @"png", @"jpg", @"jpeg", @"bmp", @"tiff" ];
            openPanel.allowsMultipleSelection = YES;
            openPanel.canChooseFiles = YES;
            openPanel.canChooseDirectories = NO;
            [openPanel runModal];

            if (openPanel.URLs.count > 0) {
                NSMutableArray* files = [@[] mutableCopy];
                for (NSURL* url in openPanel.URLs) {
                    [files addObject:[[BBUDraggedFile alloc] initWithURL:url]];
                }

                [welf collectionView:welf.collectionView didDragFiles:[files copy]];
            }
        };
    }

    return _helpViewController;
}

- (void)postSuccessNotificationIfNeeded {
    if (self.uploadQueue.operationCount == 0) {
        NSUserNotification* note = [NSUserNotification new];
        note.actionButtonTitle = NSLocalizedString(@"View on Contentful", nil);
        note.title = NSLocalizedString(@"Upload completed", nil);
        note.informativeText = [NSString stringWithFormat:NSLocalizedString(@"%d of %d file(s) successfully uploaded.", nil), self.numberOfUploads, self.totalNumberOfUploads];

        [NSUserNotificationCenter defaultUserNotificationCenter].delegate = self;
        [[NSUserNotificationCenter defaultUserNotificationCenter] scheduleNotification:note];

        self.lastNumberOfUploads = self.numberOfUploads;
        self.numberOfUploads = 0;
        self.totalNumberOfUploads = 0;
    }
}

- (void)updateHeaderView {
    if (self.uploadQueue.operationCount == 0) {
        self.headerView.titleLabel.stringValue = [NSString stringWithFormat:NSLocalizedString(@"%d file(s) successfully uploaded", nil), self.lastNumberOfUploads];
        return;
    }

    NSUInteger percentage = self.totalNumberOfUploads == 0 ? 0 : ((float)self.numberOfUploads / self.totalNumberOfUploads) * 100;

    self.headerView.titleLabel.stringValue = [NSString stringWithFormat:NSLocalizedString(@"Uploaded %d of %d file(s) %d%% done.", nil), self.numberOfUploads, self.totalNumberOfUploads, percentage];
}

- (void)windowResize {
    self.helpViewController.view.width = self.view.window.frame.size.width;
    self.helpViewController.view.height = self.view.height;

    self.dragHintView.width = MAX(self.view.width, 20.0);
}

#pragma mark - Actions

-(void)copyURLClicked:(NSMenuItem*)menuItem {
    BBUDraggedFile* draggedFile = menuItem.representedObject;
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:draggedFile.asset.URL.absoluteString forType:NSStringPboardType];

}

-(void)filterChanged {
    [self.collectionView reloadData];
}

- (IBAction)sortingOptionSelected:(NSMenuItem*)menuItem {
    for (NSMenuItem* item in self.sortingMenu.itemArray) {
        item.state = NSOffState;
    }

    menuItem.state = NSOnState;
    self.sortingType = menuItem.tag;

    [self.collectionView reloadData];
}

#pragma mark - BBUCollectionViewDelegate

-(void)collectionView:(BBUCollectionView *)collectionView didDragFiles:(NSArray *)draggedFiles {
    if (![BBUS3Uploader hasValidCredentials]) {
        NSAlert* alert = [NSAlert alertWithMessageText:NSLocalizedString(@"Please provide your Amazon S3 credentials in the Preferences before uploading files.", nil) defaultButton:NSLocalizedString(@"OK", nil) alternateButton:nil otherButton:nil informativeTextWithFormat:@""];
        [alert runModal];
        return;
    }

    self.filterSelection.enabled = draggedFiles.count > 0;
    self.headerView.hidden = draggedFiles.count == 0;
    self.helpViewController.view.hidden = draggedFiles.count > 0;

    self.dragHintView.hidden = !self.helpViewController.view.isHidden;

    [self.files addObjectsFromArray:draggedFiles];
    [collectionView reloadData];

    [[CMAClient sharedClient] fetchSharedSpaceWithSuccess:^(CDAResponse *response, CMASpace *space) {
        self.currentSpaceId = space.identifier;

        for (BBUDraggedFile* draggedFile in draggedFiles) {
            if (!draggedFile.image) {
                continue;
            }

            self.totalNumberOfUploads++;

            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateHeaderView];
            });

            NSOperation* operation = [draggedFile creationOperationForSpace:space];

            operation.completionBlock = ^{
                NSError* error = draggedFile.error;

                if (!error) {
                    self.numberOfUploads++;
                }

                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.collectionView reloadData];
                    [self postSuccessNotificationIfNeeded];
                    [self updateHeaderView];
                });
            };

            [self.uploadQueue addOperation:operation];
        }
    } failure:^(CDAResponse *response, NSError *error) {
        NSAlert* alert = [NSAlert alertWithError:error];
        [alert runModal];
    }];
}

#pragma mark - JNWCollectionViewDataSource

-(JNWCollectionViewCell *)collectionView:(JNWCollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    BBUImageCell* imageCell = (BBUImageCell*)[collectionView dequeueReusableCellWithIdentifier:NSStringFromClass(self.class)];

    BBUDraggedFile* draggedFile = [self draggedFileAtIndexPath:indexPath];
    imageCell.draggedFile = draggedFile;

    return imageCell;
}

-(NSUInteger)collectionView:(JNWCollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section {
    return self.filteredFiles.count;
}

-(JNWCollectionViewReusableView *)collectionView:(JNWCollectionView *)collectionView viewForSupplementaryViewOfKind:(NSString *)kind inSection:(NSInteger)section {
    BBUHeaderView* headerView = (BBUHeaderView*)[collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifer:NSStringFromClass(self.class)];
    headerView.backgroundColor = [BBUAppStyle defaultStyle].lightBackgroundColor;
    headerView.hidden = self.headerView.isHidden;
    headerView.titleLabel.stringValue = self.headerView.titleLabel.stringValue ?: @"";

    self.headerView = headerView;
    self.headerView.closeButton.hidden = NO;
    
    return headerView;
}

-(NSInteger)numberOfSectionsInCollectionView:(JNWCollectionView *)collectionView {
    return 1;
}

-(void)updateSelectionForCellAtIndexPath:(NSIndexPath*)indexPath {
    NSMutableDictionary* info = [@{} mutableCopy];

    switch (self.collectionView.indexPathsForSelectedItems.count ) {
        case 0:
            break;

        case 1:
            info[NSLocalizedDescriptionKey] = [[BBUDraggedFileFormatter new] stringForObjectValue:[self draggedFileAtIndexPath:self.collectionView.indexPathsForSelectedItems.firstObject]];
            break;

        default: {
            NSMutableArray* selectedFiles = [@[] mutableCopy];
            for (NSIndexPath* indexPath in self.collectionView.indexPathsForSelectedItems) {
                [selectedFiles addObject:[self draggedFileAtIndexPath:indexPath]];
            }

            info[NSLocalizedDescriptionKey] = [[BBUDraggedFileFormatter new] stringForObjectValue:[selectedFiles copy]];
            break;
        }
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:NSTableViewSelectionDidChangeNotification
                                                        object:self.collectionView
                                                      userInfo:info];

    BBUImageCell* cell = (BBUImageCell*)[self.collectionView cellForItemAtIndexPath:indexPath];
    cell.backgroundColor = cell.selected ? [[BBUAppStyle defaultStyle] selectionColor] : [NSColor clearColor];
}

#pragma mark - JNWCollectionViewDelegate

-(void)collectionView:(JNWCollectionView *)colview didDeselectItemAtIndexPath:(NSIndexPath *)indexPath {
    [self updateSelectionForCellAtIndexPath:indexPath];
}

-(void)collectionView:(JNWCollectionView *)colview didRightClickItemAtIndexPath:(NSIndexPath *)indexPath {
    BBUDraggedFile* draggedFile = [self draggedFileAtIndexPath:indexPath];

    if (!draggedFile.asset.URL) {
        return;
    }

    NSMenu *theMenu = [[NSMenu alloc] initWithTitle:@""];
    theMenu.autoenablesItems = YES;

    NSMenuItem* menuItem = [theMenu insertItemWithTitle:NSLocalizedString(@"Copy URL", nil)
                                                 action:@selector(copyURLClicked:)
                                          keyEquivalent:@""
                                                atIndex:0];
    menuItem.representedObject = draggedFile;
    menuItem.target = self;

    [NSMenu popUpContextMenu:theMenu
                   withEvent:[NSApp currentEvent]
                     forView:[self.collectionView cellForItemAtIndexPath:indexPath]];
}

-(void)collectionView:(JNWCollectionView *)colview didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [self updateSelectionForCellAtIndexPath:indexPath];
}

#pragma mark - JNWCollectionViewGridLayoutDelegate

-(CGFloat)collectionView:(JNWCollectionView *)collectionView heightForHeaderInSection:(NSInteger)index {
    return self.headerView.isHidden ? 0.0 : 40.0;
}

#pragma mark - NSUserNotificationCenterDelegate

-(void)userNotificationCenter:(NSUserNotificationCenter *)center
      didActivateNotification:(NSUserNotification *)notification {
    NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"https://app.contentful.com/spaces/%@/assets", self.currentSpaceId]];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

@end
