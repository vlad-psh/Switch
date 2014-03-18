//
//  SWWindowContentsService.m
//  Switch
//
//  Created by Scott Perry on 01/02/14.
//  Copyright © 2014 Scott Perry.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

#import "SWWindowContentsService.h"

#import <NNKit/NNService+Protected.h>

#import "SWWindowListService.h"
#import "SWWindowGroup.h"
#import "SWWindowWorker.h"



@interface _SWWindowContentContainer : NSObject

@property (nonatomic, strong) NSImage *content;
@property (nonatomic, strong) SWWindow *window;
@property (nonatomic, strong, readonly) SWWindowWorker *worker;

@end
@implementation _SWWindowContentContainer
- (void)setWindow:(SWWindow *)window;
{
    if (!_window) {
        self->_worker = [[SWWindowWorker alloc] initWithModelObject:window];
    } else {
        Check(_window.windowID == window.windowID);
    }
    _window = window;
}
@end



@interface SWWindowContentsService () <SWWindowListSubscriber>

@property (nonatomic, strong, readonly) NSMutableDictionary *contentContainers;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end


@implementation SWWindowContentsService

#pragma mark Initialization

- (id)init;
{
    if (!(self = [super init])) { return nil; }
    
    _contentContainers = [NSMutableDictionary new];
    _queue = dispatch_queue_create([[NSString stringWithFormat:@""] UTF8String], DISPATCH_QUEUE_SERIAL);
    
    [[NSNotificationCenter defaultCenter] addWeakObserver:self selector:NNSelfSelector1(_windowUpdateNotification:) name:[SWWindowWorker notificationName] object:nil];
    
    return self;
}

#pragma mark NNService

+ (NNServiceType)serviceType;
{
    return NNServiceTypeOnDemand;
}

+ (NSSet *)dependencies;
{
    return [NSSet setWithArray:@[[SWWindowListService class]]];
}

+ (Protocol *)subscriberProtocol;
{
    return @protocol(SWWindowContentsSubscriber);
}

- (void)startService;
{
    [super startService];
    
    NSOrderedSet *windows = [SWWindowListService sharedService].windows;
    if (windows) {
        [self windowListService:nil updatedList:windows];
    }
    
    [[NNServiceManager sharedManager] addObserver:self forService:[SWWindowListService class]];
}

- (void)stopService;
{
    dispatch_async(self.queue, ^{
        [self.contentContainers removeAllObjects];
    });
    
    [[NNServiceManager sharedManager] removeObserver:self forService:[SWWindowListService class]];
    
    [super stopService];
}

#pragma mark SWWindowContentsService

- (NSImage *)contentForWindow:(SWWindow *)window;
{
    _SWWindowContentContainer *contentObject = [self.contentContainers objectForKey:@(window.windowID)];
    return contentObject.content;
}

#pragma mark SWWindowListSubscriber

- (oneway void)windowListService:(SWWindowListService *)service updatedList:(NSOrderedSet *)windowList;
{
    dispatch_async(self.queue, ^{
        // Flatten the window group hierarchy into an unordered set of windows.
        NSMutableSet *existingWindows = [NSMutableSet new];
        for (SWWindowGroup *windowGroup in windowList) {
            for (SWWindow *window in windowGroup.windows) {
                [existingWindows addObject:window];
            }
        }

        // Update/create content containers for all windows that exist.
        for (SWWindow *window in existingWindows) {
            _SWWindowContentContainer *contentContainer = [self.contentContainers objectForKey:@(window.windowID)];
            if (!contentContainer) {
                contentContainer = [_SWWindowContentContainer new];
                [self.contentContainers setObject:contentContainer forKey:@(window.windowID)];
            }
            
            contentContainer.window = window;
        }
        
        // Remove content containers for windows that don't exist.
        for (_SWWindowContentContainer *contentContainer in [self.contentContainers allValues]) {
            if (![existingWindows containsObject:contentContainer.window]) {
                [self.contentContainers removeObjectForKey:@(contentContainer.window.windowID)];
            }
        }
    });
}

#pragma mark Internal

- (void)_windowUpdateNotification:(NSNotification *)notification;
{
    dispatch_async(self.queue, ^{
        SWWindowWorker *worker = notification.object;
        _SWWindowContentContainer *contentContainer = [self.contentContainers objectForKey:@(worker.windowID)];
        if (!contentContainer) {
            return;
        }
        
        NSImage *content = notification.userInfo[@"content"];
        if (!Check(content)) {
            return;
        }   
        
        contentContainer.content = content;
        
        [(id<SWWindowContentsSubscriber>)self.subscriberDispatcher windowContentService:self updatedContent:contentContainer.content forWindow:contentContainer.window];
    });
}

@end
