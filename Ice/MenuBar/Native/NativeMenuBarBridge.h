//
//  NativeMenuBarBridge.h
//  Ice
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
BOOL ICENativeMenuBarAvailable(void);
id _Nullable ICENativeMenuBarActivate(NSArray<NSNumber *> *systemItems,
                                    NSArray<NSString *> *bundles,
                                    void (^completion)(NSError * _Nullable));
void ICENativeMenuBarInvalidate(id _Nullable assertion);
NSArray<NSDictionary<NSString *, NSString *> *> *ICENativeMenuBarSnapshot(void);
/// Frames of every item slot in the macOS 27 menu bar, in global display
/// (top-left origin) coordinates. Empty when unavailable.
NSArray<NSValue *> *ICENativeMenuBarItemFrames(void);
NS_ASSUME_NONNULL_END
