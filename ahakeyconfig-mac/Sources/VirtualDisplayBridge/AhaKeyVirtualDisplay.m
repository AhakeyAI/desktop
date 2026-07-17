#import "AhaKeyVirtualDisplay.h"
#import <CoreGraphics/CoreGraphics.h>

@implementation AhaKeyVirtualDisplay {
    id _virtualDisplay;
}

+ (BOOL)isAvailable {
    return (NSClassFromString(@"CGVirtualDisplay") != nil
            && NSClassFromString(@"CGVirtualDisplayDescriptor") != nil
            && NSClassFromString(@"CGVirtualDisplayMode") != nil);
}

- (nullable instancetype)initWithName:(NSString *)name
                                width:(NSInteger)width
                               height:(NSInteger)height
                          refreshRate:(double)refreshRate {
    self = [super init];
    if (!self) return nil;

    if (![AhaKeyVirtualDisplay isAvailable]) {
        return nil;
    }

    Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");

    if (!descriptorClass || !modeClass || !displayClass) {
        return nil;
    }

    // Descriptor
    id descriptor = [[descriptorClass alloc] init];
    if (!descriptor) return nil;

    [descriptor setValue:name forKey:@"name"];
    [descriptor setValue:[NSValue valueWithSize:CGSizeMake(width, height)]
                  forKey:@"sizeInMillimeters"];
    [descriptor setValue:dispatch_get_main_queue() forKey:@"queue"];

    // Mode: try common factory method names used by the private API.
    id mode = nil;
    NSArray<NSString *> *modeSelectors = @[
        @"modeWithWidth:height:refreshRate:",
        @"modeForWidth:height:refreshRate:",
    ];
    for (NSString *selName in modeSelectors) {
        SEL sel = NSSelectorFromString(selName);
        if ([modeClass respondsToSelector:sel]) {
            typedef id (*ModeFactory)(Class, SEL, NSInteger, NSInteger, double);
            IMP imp = [modeClass methodForSelector:sel];
            ModeFactory factory = (ModeFactory)imp;
            mode = factory(modeClass, sel, width, height, refreshRate);
            break;
        }
    }

    if (!mode) {
        return nil;
    }
    [descriptor setValue:@[mode] forKey:@"modes"];

    // Display: try common factory/init names.
    id display = nil;
    NSArray<NSString *> *displaySelectors = @[
        @"displayWithDescriptor:",
        @"virtualDisplayWithDescriptor:",
    ];
    for (NSString *selName in displaySelectors) {
        SEL sel = NSSelectorFromString(selName);
        if ([displayClass respondsToSelector:sel]) {
            typedef id (*DisplayFactory)(Class, SEL, id);
            IMP imp = [displayClass methodForSelector:sel];
            DisplayFactory factory = (DisplayFactory)imp;
            display = factory(displayClass, sel, descriptor);
            break;
        }
    }

    // If no class factory method worked, try -initWithDescriptor:.
    if (!display) {
        SEL initSel = NSSelectorFromString(@"initWithDescriptor:");
        if ([displayClass instancesRespondToSelector:initSel]) {
            id allocDisplay = [displayClass alloc];
            typedef id (*InitFunc)(id, SEL, id);
            IMP imp = [allocDisplay methodForSelector:initSel];
            InitFunc initFn = (InitFunc)imp;
            display = initFn(allocDisplay, initSel, descriptor);
        }
    }

    if (!display) {
        return nil;
    }

    _virtualDisplay = display;
    return self;
}

- (void)stop {
    if (_virtualDisplay) {
        SEL stopSel = NSSelectorFromString(@"stop");
        if ([_virtualDisplay respondsToSelector:stopSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [_virtualDisplay performSelector:stopSel];
#pragma clang diagnostic pop
        }
        _virtualDisplay = nil;
    }
}

- (void)dealloc {
    [self stop];
}

@end
