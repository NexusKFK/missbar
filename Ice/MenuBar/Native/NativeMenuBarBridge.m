//
//  NativeMenuBarBridge.m
//  Ice
//

#import "NativeMenuBarBridge.h"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <dlfcn.h>
#import <objc/message.h>

// Runtime selectors and AX tree shape verified by our standalone prototype on
// 27.0 (26A428). Research: https://github.com/fif7y/pelmet (GPL-3.0).
BOOL ICENativeMenuBarAvailable(void) {
    static void *framework;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        framework = dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_LAZY);
    });
    Class config = NSClassFromString(@"MBAssessmentModeConfiguration");
    Class assertion = NSClassFromString(@"MBAssessmentModeAssertion");
    return framework &&
        [config instancesRespondToSelector:NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:")] &&
        [assertion instancesRespondToSelector:NSSelectorFromString(@"activateWithConfiguration:completionHandler:")] &&
        [assertion instancesRespondToSelector:NSSelectorFromString(@"invalidate")];
}

void ICENativeMenuBarInvalidate(id assertion) {
    @try {
        SEL selector = NSSelectorFromString(@"invalidate");
        if ([assertion respondsToSelector:selector]) {
            ((void (*)(id, SEL))objc_msgSend)(assertion, selector);
        }
    } @catch (NSException *exception) {
        NSLog(@"Ice native menu bar invalidation failed: %@", exception.reason);
    }
}

id ICENativeMenuBarActivate(NSArray<NSNumber *> *systemItems, NSArray<NSString *> *bundles,
                          void (^completion)(NSError *)) {
    if (!ICENativeMenuBarAvailable()) return nil;
    id assertion = nil;
    @try {
        id configuration = ((id (*)(id, SEL, id, id))objc_msgSend)(
            [NSClassFromString(@"MBAssessmentModeConfiguration") alloc],
            NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:"), systemItems, bundles);
        assertion = [[NSClassFromString(@"MBAssessmentModeAssertion") alloc] init];
        if (!configuration || !assertion) return nil;
        ((void (*)(id, SEL, id, void (^)(NSError *)))objc_msgSend)(assertion,
            NSSelectorFromString(@"activateWithConfiguration:completionHandler:"), configuration, completion);
        return assertion;
    } @catch (NSException *exception) {
        ICENativeMenuBarInvalidate(assertion);
        NSLog(@"Ice native menu bar activation failed: %@", exception.reason);
        return nil;
    }
}

static id ICEAttribute(AXUIElementRef element, CFStringRef key) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, key, &value) != kAXErrorSuccess) return nil;
    return CFBridgingRelease(value);
}

static NSArray *ICEChildren(AXUIElementRef element) {
    id value = ICEAttribute(element, kAXChildrenAttribute);
    return [value isKindOfClass:NSArray.class] ? value : @[];
}

static void ICECollect(AXUIElementRef element, pid_t agentPID, NSUInteger depth,
                       NSMutableDictionary<NSString *, NSDictionary *> *items, NSUInteger *budget) {
    if (depth > 4 || *budget == 0) return;
    (*budget)--;
    pid_t pid = 0;
    AXUIElementGetPid(element, &pid);
    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    NSString *bundle = app.bundleIdentifier;
    if (pid != agentPID && bundle) {
        items[bundle] = @{@"bundle": bundle, @"name": app.localizedName ?: bundle};
        return;
    }
    id identifier = ICEAttribute(element, kAXIdentifierAttribute);
    if ([identifier isKindOfClass:NSString.class] && [identifier hasPrefix:@"com.apple.menuextra."]) {
        id title = ICEAttribute(element, kAXTitleAttribute);
        if (![title isKindOfClass:NSString.class] || ![title length]) {
            title = ICEAttribute(element, kAXDescriptionAttribute);
        }
        items[identifier] = @{@"identifier": identifier,
                             @"name": [title isKindOfClass:NSString.class] ? title : identifier};
        return;
    }
    for (id child in ICEChildren(element)) {
        ICECollect((__bridge AXUIElementRef)child, agentPID, depth + 1, items, budget);
    }
}

NSArray<NSDictionary<NSString *, NSString *> *> *ICENativeMenuBarSnapshot(void) {
    if (!AXIsProcessTrusted()) return @[];
    NSRunningApplication *agent = [NSRunningApplication
        runningApplicationsWithBundleIdentifier:@"com.apple.MenuBarAgent"].firstObject;
    if (!agent) return @[];
    AXUIElementRef root = AXUIElementCreateApplication(agent.processIdentifier);
    AXUIElementSetMessagingTimeout(root, 0.1);
    NSMutableDictionary *items = [NSMutableDictionary dictionary];
    NSUInteger budget = 256;
    for (id window in ICEChildren(root)) {
        AXUIElementRef element = (__bridge AXUIElementRef)window;
        if (![ICEAttribute(element, kAXRoleAttribute) isEqual:@"AXWindow"]) continue;
        for (id group in ICEChildren(element)) {
            ICECollect((__bridge AXUIElementRef)group, agent.processIdentifier, 0, items, &budget);
        }
    }
    CFRelease(root);
    return items.allValues;
}

static BOOL ICEFrame(AXUIElementRef element, CGRect *frame) {
    id position = ICEAttribute(element, kAXPositionAttribute);
    id size = ICEAttribute(element, kAXSizeAttribute);
    if (!position || !size) return NO;
    CGPoint origin;
    CGSize extent;
    if (!AXValueGetValue((__bridge AXValueRef)position, kAXValueTypeCGPoint, &origin) ||
        !AXValueGetValue((__bridge AXValueRef)size, kAXValueTypeCGSize, &extent)) {
        return NO;
    }
    *frame = (CGRect){origin, extent};
    return YES;
}

// On 27 the whole menu bar is one MenuBarAgent window per display, so the
// per-item CGWindow list is empty. Each direct child of that window is the
// host slot of one item (system extra or app status item) with a real frame.
NSArray<NSValue *> *ICENativeMenuBarItemFrames(void) {
    if (!AXIsProcessTrusted()) return @[];
    NSRunningApplication *agent = [NSRunningApplication
        runningApplicationsWithBundleIdentifier:@"com.apple.MenuBarAgent"].firstObject;
    if (!agent) return @[];
    AXUIElementRef root = AXUIElementCreateApplication(agent.processIdentifier);
    AXUIElementSetMessagingTimeout(root, 0.05);
    NSMutableArray<NSValue *> *frames = [NSMutableArray array];
    for (id window in ICEChildren(root)) {
        AXUIElementRef element = (__bridge AXUIElementRef)window;
        if (![ICEAttribute(element, kAXRoleAttribute) isEqual:@"AXWindow"]) continue;
        for (id slot in ICEChildren(element)) {
            CGRect frame;
            if (ICEFrame((__bridge AXUIElementRef)slot, &frame) && frame.size.width > 0 && frame.size.height > 0) {
                [frames addObject:[NSValue valueWithRect:NSRectFromCGRect(frame)]];
            }
        }
    }
    CFRelease(root);
    return frames;
}
