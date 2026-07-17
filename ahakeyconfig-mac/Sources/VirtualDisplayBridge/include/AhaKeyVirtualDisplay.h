#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Wrapper around Apple's private CGVirtualDisplay API.
///
/// This class dynamically discovers CGVirtualDisplay, CGVirtualDisplayDescriptor,
/// and CGVirtualDisplayMode at runtime so the project can compile against the
/// public SDK while still using the private symbols on macOS 14+.
@interface AhaKeyVirtualDisplay : NSObject

/// Returns YES if the private CGVirtualDisplay classes are present at runtime.
+ (BOOL)isAvailable;

/// Create and start a small virtual display. Returns nil if the API is unavailable
/// or creation fails.
- (nullable instancetype)initWithName:(NSString *)name
                                width:(NSInteger)width
                               height:(NSInteger)height
                          refreshRate:(double)refreshRate;

/// Stop and release the virtual display.
- (void)stop;

@end

NS_ASSUME_NONNULL_END
