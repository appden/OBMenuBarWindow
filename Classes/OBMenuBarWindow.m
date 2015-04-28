//
//  OBMenuBarWindow.m
//
//  Copyright (c) 2013, Oliver Bolton (http://oliverbolton.com/)
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//      * Redistributions of source code must retain the above copyright
//        notice, this list of conditions and the following disclaimer.
//      * Redistributions in binary form must reproduce the above copyright
//        notice, this list of conditions and the following disclaimer in the
//        documentation and/or other materials provided with the distribution.
//      * Neither the name of the <organization> nor the
//        names of its contributors may be used to endorse or promote products
//        derived from this software without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL OLIVER BOLTON BE LIABLE FOR ANY DIRECT,
//  INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
//  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
//  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
//  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
//  THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import "OBMenuBarWindow.h"
#import <objc/runtime.h>

#ifndef NSAppKitVersionNumber10_9
#define NSAppKitVersionNumber10_9 1265
#endif

NSString * const OBMenuBarWindowDidAttachToMenuBar = @"OBMenuBarWindowDidAttachToMenuBar";
NSString * const OBMenuBarWindowDidDetachFromMenuBar = @"OBMenuBarWindowDidDetachFromMenuBar";

@interface OBMenuBarWindowIconView : NSView

@property (nonatomic, assign) OBMenuBarWindow *menuBarWindow;
@property (nonatomic, assign) BOOL highlighted;

@end

@interface OBMenuBarWindowToolbarView : NSView
@end

@interface OBMenuBarWindow ()

@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, assign) BOOL resizeRight;
@property (nonatomic, assign) BOOL hideControls;
@property (nonatomic, assign) BOOL preventFrameChange;
@property (nonatomic, assign) NSPoint dragStartLocation;
@property (nonatomic, assign) NSPoint resizeStartLocation;
@property (nonatomic, assign) NSRect dragStartFrame;
@property (nonatomic, assign) NSRect resizeStartFrame;
@property (nonatomic, strong) NSImage *noiseImage;
@property (nonatomic, strong) OBMenuBarWindowIconView *statusItemView;

- (void)initialSetup;
- (NSRect)titleBarRect;
- (NSRect)toolbarRect;
- (NSPoint)originForAttachedState;
- (void)applicationDidChangeActiveStatus:(NSNotification *)aNotification;
- (void)windowDidBecomeKey:(NSNotification *)aNotification;
- (void)windowDidResignKey:(NSNotification *)aNotification;
- (void)windowDidResize:(NSNotification *)aNotification;
- (void)windowWillStartLiveResize:(NSNotification *)aNotification;
- (void)windowDidMove:(NSNotification *)aNotification;
- (void)statusItemViewDidMove:(NSNotification *)aNotification;
- (NSWindow *)window;
- (NSImage *)noiseImage;
- (void)drawRectOriginal:(NSRect)dirtyRect;

@end

@implementation OBMenuBarWindow

- (id)initWithContentRect:(NSRect)contentRect
                styleMask:(NSUInteger)aStyle
                  backing:(NSBackingStoreType)bufferingType
                    defer:(BOOL)flag
{
    self = [super initWithContentRect:contentRect
                            styleMask:aStyle
                              backing:bufferingType
                                defer:flag];
    if (self)
    {
        _snapDistance = 30.0;
        _distanceFromMenuBar = 0;
        _hideWindowControlsWhenAttached = YES;
        _isDetachable = YES;
        _arrowSize = NSMakeSize(20.0, 10.0);
        _titleBarHeight = 22.0;
        [self initialSetup];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)initialSetup
{
    // Set up the window drawing
    [self setBackgroundColor:[NSColor clearColor]];
    [self setOpaque:YES];
    [self setMovable:NO];
    
    // Observe window and application state notifications
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(windowDidMove:)
                   name:NSWindowDidMoveNotification
                 object:self];
    [center addObserver:self
               selector:@selector(windowDidResize:)
                   name:NSWindowDidResizeNotification
                 object:self];
    [center addObserver:self
               selector:@selector(windowWillStartLiveResize:)
                   name:NSWindowWillStartLiveResizeNotification
                 object:self];
    [center addObserver:self
               selector:@selector(windowDidBecomeKey:)
                   name:NSWindowDidBecomeKeyNotification
                 object:self];
    [center addObserver:self
               selector:@selector(windowDidResignKey:)
                   name:NSWindowDidResignKeyNotification
                 object:self];
    [center addObserver:self
               selector:@selector(applicationDidChangeActiveStatus:)
                   name:NSApplicationDidBecomeActiveNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(applicationDidChangeActiveStatus:)
                   name:NSApplicationDidResignActiveNotification
                 object:nil];
    
    // Get window's frame view class
    NSView *frameView = [self.contentView superview];
    Class class = [frameView class];
    
    // Add the new drawRect: to the frame class
    Method m0 = class_getInstanceMethod([self class], @selector(drawRect:));
    class_addMethod(class, @selector(drawRectOriginal:), method_getImplementation(m0), method_getTypeEncoding(m0));
    
    // Exchange methods
    Method m1 = class_getInstanceMethod(class, @selector(drawRect:));
    Method m2 = class_getInstanceMethod(class, @selector(drawRectOriginal:));
    method_exchangeImplementations(m1, m2);
    
    // Create the toolbar view
    NSRect toolbarRect = [self toolbarRect];
    _toolbarView = [[OBMenuBarWindowToolbarView alloc] initWithFrame:toolbarRect];
    [_toolbarView setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    
    // Create the title text field
    NSRect titleRect = NSMakeRect(70,
                                  (toolbarRect.size.height - 17) / 2,
                                  toolbarRect.size.width - 140,
                                  17);
    _titleTextField = [[NSTextField alloc] initWithFrame:titleRect];
    [_titleTextField setEditable:NO];
    [_titleTextField setBezeled:NO];
    [_titleTextField setDrawsBackground:NO];
    [_titleTextField setAlignment:NSCenterTextAlignment];
    [_titleTextField setFont:[NSFont titleBarFontOfSize:13.0]];
    [[_titleTextField cell] setLineBreakMode:NSLineBreakByTruncatingTail];
    [[_titleTextField cell] setBackgroundStyle:NSBackgroundStyleRaised];
    [_titleTextField setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin)];
    [_toolbarView addSubview:_titleTextField];
    
    // Lay out the content
    [frameView addSubview:_toolbarView];
    [self layoutContent];
}

- (void)setContentView:(id)contentView
{
    [super setContentView:contentView];
    [self layoutContent];
}

#pragma mark - Positioning controls

- (void)layoutContent
{
    // Position the close/minimise/zoom buttons
    NSButton *closeButton = [self standardWindowButton:NSWindowCloseButton];
    NSButton *minimiseButton = [self standardWindowButton:NSWindowMiniaturizeButton];
    NSButton *zoomButton = [self standardWindowButton:NSWindowZoomButton];
    CGFloat buttonWidth = closeButton.frame.size.width;
    CGFloat buttonHeight = closeButton.frame.size.height;
    NSRect toolbarRect = [self toolbarRect];
    CGFloat buttonOriginY = floor(toolbarRect.origin.y + (toolbarRect.size.height - buttonHeight) / 2.0);
    
    [closeButton setFrame:NSMakeRect(7, buttonOriginY, buttonWidth, buttonHeight)];
    [minimiseButton setFrame:NSMakeRect(27, buttonOriginY, buttonWidth, buttonHeight)];
    [zoomButton setFrame:NSMakeRect(47, buttonOriginY, buttonWidth, buttonHeight)];
    
    NSView *contentView = self.contentView;
    NSView *frameView = [contentView superview];
    
    [frameView viewWillStartLiveResize];
    [frameView viewDidEndLiveResize];
    
    // Position the toolbar view
    [self.toolbarView setFrame:toolbarRect];
    
    // Position the content view
    NSRect contentViewFrame = contentView.frame;
    CGFloat currentTopMargin = NSHeight(self.frame) - NSHeight(contentViewFrame);
    CGFloat titleBarHeight = self.titleBarHeight + (self.attachedToMenuBar ? self.arrowSize.height : 0);
    CGFloat delta = titleBarHeight - currentTopMargin;
    contentViewFrame.size.height -= delta;
    [contentView setFrame:contentViewFrame];
    
    // Redraw the theme frame
    [frameView setNeedsDisplayInRect:[self titleBarRect]];
}

#pragma mark - Menu bar icon

- (void)setHasMenuBarIcon:(BOOL)flag
{
    if (self.hasMenuBarIcon == flag)
    {
        return;
    }
    _hasMenuBarIcon = flag;
    if (flag)
    {
        // Create the status item
        _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
        CGFloat thickness = [[NSStatusBar systemStatusBar] thickness];
        self.statusItemView = [[OBMenuBarWindowIconView alloc] initWithFrame:NSMakeRect(0, 0, (self.menuBarIcon ? self.menuBarIcon.size.width : thickness) + 6, thickness)];
        self.statusItemView.menuBarWindow = self;
        _statusItem.view = self.statusItemView;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusItemViewDidMove:) name:NSWindowDidMoveNotification object:_statusItem.view.window];
    }
    else
    {
        if (self.statusItemView)
        {
            [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidMoveNotification object:self.statusItemView];
        }
        self.statusItemView = nil;
        _statusItem = nil;
        self.attachedToMenuBar = NO;
    }
}

- (void)setMenuBarIcon:(NSImage *)image
{
    _menuBarIcon = image;
    if (self.statusItemView)
    {
        [self.statusItemView setFrameSize:NSMakeSize(image.size.width + 6, self.statusItemView.frame.size.height)];
        [self.statusItemView setNeedsDisplay:YES];
    }
}

- (void)setHighlightedMenuBarIcon:(NSImage *)image
{
    _highlightedMenuBarIcon = image;
    if (self.statusItemView)
    {
        [self.statusItemView setNeedsDisplay:YES];
    }
}

- (void)setAttachedToMenuBar:(BOOL)isAttached
{
    if (self.attachedToMenuBar == isAttached)
    {
        return;
    }
    _attachedToMenuBar = isAttached;
    
    if (isAttached)
    {
        NSRect newFrame = self.frame;
        newFrame.size.height += self.arrowSize.height;
        [self setFrame:newFrame display:YES];
    }
    else
    {
        NSRect newFrame = self.frame;
        newFrame.size.height -= self.arrowSize.height;
        [self setFrame:newFrame display:YES];
    }
    
    if (self.isVisible)
    {
        self.statusItemView.highlighted = isAttached;
    }
    
    // Set whether the window is opaque (this affects the shadow)
    [self setOpaque:!isAttached];
    
    // Reposition the content
    [self layoutContent];
    
    // Animate the window controls
    NSButton *closeButton = [self standardWindowButton:NSWindowCloseButton];
    NSButton *minimiseButton = [self standardWindowButton:NSWindowMiniaturizeButton];
    NSButton *zoomButton = [self standardWindowButton:NSWindowZoomButton];
    if (isAttached)
    {
        if (self.hideWindowControlsWhenAttached)
        {
            self.hideControls = YES;
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                [context setDuration:(self.isVisible ? 0.15 : 0.0)];
                [[closeButton animator] setAlphaValue:0.0];
                [[minimiseButton animator] setAlphaValue:0.0];
                [[zoomButton animator] setAlphaValue:0.0];
            } completionHandler:^{
                if (self.hideControls)
                {
                    [closeButton setHidden:YES];
                    [minimiseButton setHidden:YES];
                    [zoomButton setHidden:YES];
                    [closeButton setAlphaValue:1.0];
                    [minimiseButton setAlphaValue:1.0];
                    [zoomButton setAlphaValue:1.0];
                    self.hideControls = NO;
                }
            }];
        }
        if (!self.isDragging)
        {
            [self setFrameOrigin:[self originForAttachedState]];
        }
    }
    else
    {
        if (self.hideWindowControlsWhenAttached)
        {
            self.hideControls = NO;
            [closeButton setAlphaValue:0.0];
            [minimiseButton setAlphaValue:0.0];
            [zoomButton setAlphaValue:0.0];
            [closeButton setHidden:NO];
            [minimiseButton setHidden:NO];
            [zoomButton setHidden:NO];
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                [context setDuration:(self.isVisible ? 0.15 : 0.0)];
                [[closeButton animator] setAlphaValue:1.0];
                [[minimiseButton animator] setAlphaValue:1.0];
                [[zoomButton animator] setAlphaValue:1.0];
            } completionHandler:nil];
        }
    }
    
    [self setLevel:(isAttached ? NSPopUpMenuWindowLevel : NSNormalWindowLevel)];
    if (self.delegate != nil)
    {
        if (isAttached && [self.delegate respondsToSelector:@selector(windowDidAttachToMenuBar:)])
        {
            [self.delegate performSelector:@selector(windowDidAttachToMenuBar:)
                                withObject:self];
            [[NSNotificationCenter defaultCenter] postNotificationName:OBMenuBarWindowDidAttachToMenuBar
                                                                object:self];
        }
        else if (!isAttached && [self.delegate respondsToSelector:@selector(windowDidDetachFromMenuBar:)])
        {
            [self.delegate performSelector:@selector(windowDidDetachFromMenuBar:)
                                withObject:self];
            [[NSNotificationCenter defaultCenter] postNotificationName:OBMenuBarWindowDidDetachFromMenuBar
                                                                object:self];
        }
    }
    [self layoutContent];
    [[self.contentView superview] setNeedsDisplay:YES];
    [self invalidateShadow];
}

- (void)setHideWindowControlsWhenAttached:(BOOL)flag
{
    if (self.hideWindowControlsWhenAttached == flag)
    {
        return;
    }
    _hideWindowControlsWhenAttached = flag;
    if (!flag)
    {
        NSButton *closeButton = [self standardWindowButton:NSWindowCloseButton];
        NSButton *minimiseButton = [self standardWindowButton:NSWindowMiniaturizeButton];
        NSButton *zoomButton = [self standardWindowButton:NSWindowZoomButton];
        [closeButton setAlphaValue:1.0];
        [minimiseButton setAlphaValue:1.0];
        [zoomButton setAlphaValue:1.0];
        [closeButton setHidden:NO];
        [minimiseButton setHidden:NO];
        [zoomButton setHidden:NO];
    }
    else if (self.attachedToMenuBar)
    {
        NSButton *closeButton = [self standardWindowButton:NSWindowCloseButton];
        NSButton *minimiseButton = [self standardWindowButton:NSWindowMiniaturizeButton];
        NSButton *zoomButton = [self standardWindowButton:NSWindowZoomButton];
        [closeButton setAlphaValue:1.0];
        [minimiseButton setAlphaValue:1.0];
        [zoomButton setAlphaValue:1.0];
        [closeButton setHidden:YES];
        [minimiseButton setHidden:YES];
        [zoomButton setHidden:YES];
    }
}

- (void)setArrowSize:(NSSize)size
{
    _arrowSize = size;
    [self layoutContent];
}

#pragma mark - Title bar

- (void)setTitleBarHeight:(CGFloat)height
{
    _titleBarHeight = height;
    [self layoutContent];
}

- (void)setTitle:(NSString *)aString
{
    [super setTitle:aString];
    self.titleTextField.stringValue = aString;
    [self layoutContent];
}

- (NSRect)titleBarRect
{
    return NSMakeRect(0,
                      self.frame.size.height - self.titleBarHeight - (self.attachedToMenuBar ? self.arrowSize.height : 0),
                      self.frame.size.width,
                      self.titleBarHeight + (self.attachedToMenuBar ? self.arrowSize.height : 0));
}

- (NSRect)toolbarRect
{
    if (self.attachedToMenuBar)
    {
        return NSMakeRect(0,
                          self.frame.size.height - self.titleBarHeight - self.arrowSize.height,
                          self.frame.size.width,
                          self.titleBarHeight);
    }
    else
    {
        return [self titleBarRect];
    }
}

#pragma mark - Active/key events

- (BOOL)canBecomeKeyWindow
{
    return YES;
}

- (BOOL)canHide
{
    return !self.attachedToMenuBar;
}

- (void)applicationDidChangeActiveStatus:(NSNotification *)aNotification
{
    [[self.contentView superview] setNeedsDisplayInRect:[self titleBarRect]];
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
    [[self.contentView superview] setNeedsDisplayInRect:[self titleBarRect]];
}

- (void)windowDidResignKey:(NSNotification *)aNotification
{
    if (self.attachedToMenuBar)
    {
        [self orderOut:self];
    }
    [[self.contentView superview] setNeedsDisplayInRect:[self titleBarRect]];
}

#pragma mark - Showing the window

- (NSPoint)originForAttachedState
{
    if (self.statusItemView)
    {
        NSRect statusItemFrame = [[self.statusItemView window] frame];
        NSPoint midPoint = NSMakePoint(NSMidX(statusItemFrame),
                                       NSMinY(statusItemFrame));
        return NSMakePoint(midPoint.x - (self.frame.size.width / 2),
                           midPoint.y - MAX(self.distanceFromMenuBar, 0) - self.frame.size.height);
    }
    else
    {
        return NSZeroPoint;
    }
}

- (void)makeKeyAndOrderFront:(id)sender
{
    if (!(self.styleMask & NSNonactivatingPanelMask))
    {
        [NSApp activateIgnoringOtherApps:YES];
    }
    if (self.attachedToMenuBar)
    {
        self.statusItemView.highlighted = YES;
        [self setFrameOrigin:[self originForAttachedState]];
    }
    [super makeKeyAndOrderFront:sender];
}

- (void)orderOut:(id)sender
{
    self.statusItemView.highlighted = NO;
    
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [context setDuration:0.1];
        [self.animator setAlphaValue:0];
    } completionHandler:^{
        [super orderOut:self];
        [self setAlphaValue:1.0];
    }];
}

#pragma mark - Mouse events

- (void)mouseDown:(NSEvent *)theEvent
{
    self.dragStartLocation = [NSEvent mouseLocation];
    self.dragStartFrame = self.frame;
    NSPoint mouseLocationInWindow = [theEvent locationInWindow];
    self.isDragging = NSPointInRect(mouseLocationInWindow, [self toolbarRect]);
}

- (void)mouseUp:(NSEvent *)theEvent
{
    if (!self.attachedToMenuBar && [theEvent clickCount] == 2 && self.isDragging)
    {
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        [userDefaults addSuiteNamed:NSGlobalDomain];
        BOOL shouldMiniaturize = [[userDefaults objectForKey:@"AppleMiniaturizeOnDoubleClick"] boolValue];
        if (shouldMiniaturize)
        {
            [self miniaturize:self];
        }
    }
    else if (self.isDragging)
    {
        NSRect visibleRect = [[self screen] visibleFrame];
        CGFloat minY = NSMinY(visibleRect);
        if (NSMaxY(self.frame) - self.arrowSize.height - 23 < minY)
        {
            [self setFrameOrigin:NSMakePoint(self.frame.origin.x, minY - self.frame.size.height + self.arrowSize.height + 23)];
        }
    }
    self.isDragging = NO;
}

- (void)mouseDragged:(NSEvent *)theEvent
{
    if ([theEvent type] == NSLeftMouseDragged && self.isDragging)
    {
        NSPoint newLocation = [NSEvent mouseLocation];
        CGFloat originX = self.dragStartFrame.origin.x + newLocation.x - self.dragStartLocation.x;
        CGFloat originY = self.dragStartFrame.origin.y + newLocation.y - self.dragStartLocation.y;
        [self setFrameOrigin:NSMakePoint(originX, originY)];
    }
}

#pragma mark - Resizing events

- (void)windowDidResize:(NSNotification *)aNotification
{
    [self layoutContent];
}

- (void)windowWillStartLiveResize:(NSNotification *)aNotification
{
    self.resizeStartFrame = self.frame;
    self.resizeStartLocation = [self convertBaseToScreen:[self mouseLocationOutsideOfEventStream]];
    self.resizeRight = ([self mouseLocationOutsideOfEventStream].x > self.frame.size.width / 2.0);
}

#pragma mark - Positioning events

- (void)setDistanceFromMenuBar:(CGFloat)distance
{
    _distanceFromMenuBar = distance;
    if (self.attachedToMenuBar)
    {
        [self setFrameOrigin:[self originForAttachedState]];
    }
}

- (void)windowDidMove:(NSNotification *)aNotification
{
    if (![self inLiveResize] && self.hasMenuBarIcon)
    {
        NSRect frame = [self frame];
        NSPoint arrowPoint = NSMakePoint(NSMidX(frame), NSMaxY(frame));
        NSRect statusItemFrame = [[self.statusItemView window] frame];
        NSPoint statusItemPoint = NSMakePoint(NSMidX(statusItemFrame), NSMinY(statusItemFrame));
        double distance = sqrt(pow(arrowPoint.x - statusItemPoint.x, 2) + pow(arrowPoint.y - statusItemPoint.y, 2));
        if (!self.isDetachable || distance <= self.snapDistance)
        {
            [self setFrameOrigin:[self originForAttachedState]];
            self.attachedToMenuBar = YES;
        }
        else
        {
            self.attachedToMenuBar = NO;
        }
    }
    [self layoutContent];
}

- (void)statusItemViewDidMove:(NSNotification *)aNotification
{
    if (self.attachedToMenuBar)
    {
        [self setFrameOrigin:[self originForAttachedState]];
    }
}

- (void)setStyleMask:(NSUInteger)styleMask
{
    self.preventFrameChange = YES;
    
    [super setStyleMask:styleMask];
    [self layoutContent];
    
    self.preventFrameChange = NO;
}

- (void)setFrame:(NSRect)frameRect display:(BOOL)flag
{
    if (self.preventFrameChange)
    {
        return;
    }
    if ([self inLiveResize] && self.attachedToMenuBar)
    {
        NSPoint mouseLocation = [self convertBaseToScreen:[self mouseLocationOutsideOfEventStream]];
        NSRect newFrame = self.resizeStartFrame;
        if (frameRect.size.width != self.resizeStartFrame.size.width)
        {
            CGFloat deltaWidth = (self.resizeRight ? mouseLocation.x - self.resizeStartLocation.x : self.resizeStartLocation.x - mouseLocation.x);
            newFrame.origin.x -= deltaWidth;
            newFrame.size.width += deltaWidth * 2;
            if (newFrame.size.width < self.minSize.width)
            {
                newFrame.size.width = self.minSize.width;
                newFrame.origin.x = NSMidX(self.resizeStartFrame) - (self.minSize.width) / 2.0;
            }
            if (newFrame.size.width > self.maxSize.width)
            {
                newFrame.size.width = self.maxSize.width;
                newFrame.origin.x = NSMidX(self.resizeStartFrame) - (self.maxSize.width) / 2.0;
            }
        }
        
        // Don't allow resizing upwards when attached to menu bar
        if (frameRect.origin.y != self.resizeStartFrame.origin.y)
        {
            newFrame.origin.y = frameRect.origin.y;
            newFrame.size.height = frameRect.size.height;
        }
        
        [super setFrame:newFrame display:YES];
    }
    else
    {
        [super setFrame:frameRect display:flag];
    }
}

#pragma mark - Drawing

- (NSWindow *)window
{
    return self;
}

- (NSImage *)noiseImage
{
    if (!_noiseImage)
    {
        size_t dimension = 100;
        size_t bytes = dimension * dimension * 4;
        CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
        unsigned char *data = malloc(bytes);
        unsigned char grey;
        for (NSUInteger i = 0; i < bytes; i += 4)
        {
            grey = (unsigned char)(rand() % 256);
            data[i] = grey;
            data[i + 1] = grey;
            data[i + 2] = grey;
            data[i + 3] = 6;
        }
        CGContextRef contextRef = CGBitmapContextCreate(data,
                                                        dimension,
                                                        dimension,
                                                        8,
                                                        dimension * 4,
                                                        colorSpaceRef,
                                                        (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
        CGImageRef imageRef = CGBitmapContextCreateImage(contextRef);
        _noiseImage = [[NSImage alloc] initWithCGImage:imageRef size:NSMakeSize(dimension, dimension)];
        CGImageRelease(imageRef);
        CGContextRelease(contextRef);
        free(data);
        CGColorSpaceRelease(colorSpaceRef);
    }
    return _noiseImage;
}

- (void)drawRectOriginal:(NSRect)dirtyRect
{
    // Do nothing
}

- (void)drawRect:(NSRect)dirtyRect
{
    // Only draw the custom window frame for a OBMenuBarWindow object
    if (![self respondsToSelector:@selector(window)] || ![[self window] isKindOfClass:[OBMenuBarWindow class]])
    {
        [self drawRectOriginal:dirtyRect];
        return;
    }
    
    OBMenuBarWindow *window = (OBMenuBarWindow *)[self window];
    NSRect bounds = [window.contentView superview].bounds;
    CGFloat originX = bounds.origin.x;
    CGFloat originY = bounds.origin.y;
    CGFloat width = bounds.size.width;
    CGFloat height = bounds.size.height;
    CGFloat titleBarHeight = round(window.titleBarHeight);
    CGFloat arrowWidth = round(window.arrowSize.width);
    CGFloat arrowHeight = round(window.arrowSize.height);
    CGFloat cornerRadius = 4.0;
    
    BOOL isAttached = window.attachedToMenuBar;
    BOOL isActive = isAttached || [window isKeyWindow];
    BOOL isYosemite = floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_9;
    
    // Draw the window background
    [[NSColor windowBackgroundColor] set];
    NSRectFill(dirtyRect);
    
    // Erase the standard title bar
    CGFloat titleBarHeightWithArrow = titleBarHeight + (isAttached ? arrowHeight : 0);
    [[NSColor clearColor] set];
    NSRectFillUsingOperation([window titleBarRect], NSCompositeClear);
    
    // Create the window shape
    NSPoint arrowPointLeft = NSMakePoint(originX + (width - arrowWidth) / 2.0,
                                         originY + height - (isAttached ? arrowHeight : 0));
    NSPoint arrowPointMiddle = NSMakePoint(originX + width / 2.0,
                                           originY + height);
    NSPoint arrowPointRight = NSMakePoint(originX + (width + arrowWidth) / 2.0,
                                          originY + height - (isAttached ? arrowHeight : 0));
    NSPoint topLeft = NSMakePoint(originX,
                                  originY + height - (isAttached ? arrowHeight : 0));
    NSPoint topRight = NSMakePoint(originX + width,
                                   originY + height - (isAttached ? arrowHeight : 0));
    NSPoint bottomLeft = NSMakePoint(originX,
                                     originY + height - arrowHeight - titleBarHeight);
    NSPoint bottomRight = NSMakePoint(originX + width,
                                      originY + height - arrowHeight - titleBarHeight);
    
    NSBezierPath *border = [NSBezierPath bezierPath];
    [border moveToPoint:arrowPointLeft];
    [border lineToPoint:arrowPointMiddle];
    [border lineToPoint:arrowPointRight];
    [border appendBezierPathWithArcFromPoint:topRight
                                     toPoint:bottomRight
                                      radius:cornerRadius];
    [border lineToPoint:bottomRight];
    [border lineToPoint:bottomLeft];
    [border appendBezierPathWithArcFromPoint:topLeft
                                     toPoint:arrowPointLeft
                                      radius:cornerRadius];
    [border closePath];
    
    // Draw the title bar
    [NSGraphicsContext saveGraphicsState];
    [border addClip];
    
    NSRect headingRect = NSMakeRect(originX,
                                    originY + height - titleBarHeightWithArrow,
                                    width,
                                    titleBarHeight);
    NSRect titleBarRect = NSMakeRect(originX,
                                     originY + height - titleBarHeightWithArrow,
                                     width,
                                     titleBarHeight + arrowHeight);
    
    // Colors
    NSColor *bottomColor, *topColor, *topColorTransparent, *separatorColor;
    
    if (isYosemite)
    {
        bottomColor = [NSColor colorWithDeviceWhite:(isActive ? 211.0 : 246.0) / 255.0 alpha:1.0];
        topColor = [NSColor colorWithDeviceWhite:(isActive ? 240.0 : 250.0) / 255.0 alpha:1.0];
        topColorTransparent = [NSColor colorWithDeviceWhite:(isActive ? 240.0 : 250.0) / 255.0 alpha:0.0];
        separatorColor = [NSColor colorWithDeviceWhite:(isActive ? 150.0 : 181.0) / 255.0 alpha:1.0];
    }
    else
    {
        bottomColor = [NSColor colorWithCalibratedWhite:(isActive ? 0.69 : 0.85) alpha:1.0];
        topColor = [NSColor colorWithCalibratedWhite:(isActive ? 0.91 : 0.93) alpha:1.0];
        topColorTransparent = [NSColor colorWithCalibratedWhite:(isActive ? 0.91 : 0.93) alpha:0.0];
        separatorColor = [NSColor colorWithCalibratedWhite:0.5 alpha:1.0];
    }
    
    // Fill the titlebar with the base colour
    [bottomColor set];
    NSRectFill(titleBarRect);
    
    // Draw some subtle noise to the titlebar if the window is the key window
    if (isActive && !isYosemite)
    {
        [[NSColor colorWithPatternImage:[window noiseImage]] set];
        NSRectFillUsingOperation(headingRect, NSCompositeSourceOver);
    }
    
    // Draw the highlight
    NSGradient *headingGradient = [[NSGradient alloc] initWithStartingColor:topColorTransparent
                                                                endingColor:topColor];
    [headingGradient drawInRect:headingRect angle:90.0];
    
    // Highlight the tip, too
    if (isAttached)
    {
        NSColor *tipColor = [NSColor whiteColor];
        NSGradient *tipGradient = [[NSGradient alloc] initWithStartingColor:topColor
                                                                endingColor:tipColor];
        NSRect tipRect = NSMakeRect(arrowPointLeft.x,
                                    arrowPointLeft.y,
                                    arrowWidth,
                                    arrowHeight);
        [tipGradient drawInRect:tipRect angle:90.0];
    }
    
    // Draw the title bar highlight
    NSBezierPath *highlightPath = [NSBezierPath bezierPath];
    [highlightPath moveToPoint:topLeft];
    if (isAttached)
    {
        [highlightPath lineToPoint:arrowPointLeft];
        [highlightPath lineToPoint:arrowPointMiddle];
        [highlightPath lineToPoint:arrowPointRight];
    }
    [highlightPath lineToPoint:topRight];
    [[NSColor colorWithCalibratedWhite:1.0 alpha:1.0] set];
    [highlightPath setLineWidth:1.0];
    [border addClip];
    [highlightPath stroke];
    
    [NSGraphicsContext restoreGraphicsState];
    
    // Draw separator line between the titlebar and the content view
    [separatorColor set];
    
    NSRect separatorRect = NSMakeRect(originX, originY + height - titleBarHeightWithArrow, width, 0.5);
    NSRectFill(separatorRect);
}

- (void)drawMenuBarIconInRect:(NSRect)rect highlighted:(BOOL)highlighted
{
    NSImage *icon = (highlighted && self.highlightedMenuBarIcon) ? self.highlightedMenuBarIcon : self.menuBarIcon;
    
    [icon drawInRect:rect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
}

@end

#pragma mark -

@implementation OBMenuBarWindowIconView

#pragma mark - Highlighting

- (void)setHighlighted:(BOOL)flag
{
    _highlighted = flag;
    [self setNeedsDisplay:YES];
}

#pragma mark - Mouse events

- (void)mouseDown:(NSEvent *)theEvent
{
    self.highlighted = YES;
    if ([self.menuBarWindow isMainWindow] || (self.menuBarWindow.isVisible && self.menuBarWindow.attachedToMenuBar))
    {
        [self.menuBarWindow orderOut:self];
    }
    else
    {
        [self.menuBarWindow makeKeyAndOrderFront:self];
    }
}

- (void)rightMouseDown:(NSEvent *)theEvent
{
    [self mouseDown:theEvent];
}

- (void)mouseUp:(NSEvent *)theEvent
{
    if (!self.menuBarWindow.attachedToMenuBar || !self.menuBarWindow.isVisible)
    {
        self.highlighted = NO;
    }
}

#pragma mark - Drawing

- (void)drawRect:(NSRect)dirtyRect
{
    [self.menuBarWindow.statusItem drawStatusBarBackgroundInRect:self.bounds withHighlight:self.highlighted];
    [self.menuBarWindow drawMenuBarIconInRect:NSInsetRect(self.bounds, 3, 0) highlighted:self.highlighted];
}

@end

#pragma mark -

@implementation OBMenuBarWindowToolbarView

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
    return YES;
}

@end
