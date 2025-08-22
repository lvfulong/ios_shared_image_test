#import "ios_view_controller.h"
#import <IOSurface/IOSurface.h>

@implementation IOSViewControllerDirect

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 设置视图背景色
    self.view.backgroundColor = [UIColor blackColor];
    
    // 创建IOSurface用于渲染
    if (![self createIOSurface]) {
        NSLog(@"Failed to create IOSurface");
        return;
    }
    
    // 创建主渲染器
    _mainRenderer = [[IOSMainRenderer alloc] initWithSurface:_ioSurface];
    
    // 初始化渲染器
    if (![_mainRenderer initialize]) {
        NSLog(@"Failed to initialize main renderer");
        return;
    }
    
    NSLog(@"IOSurface-based rendering view controller loaded successfully");
}

- (BOOL)createIOSurface {
    // 创建IOSurface属性
    NSDictionary* surfaceProperties = @{
        (NSString*)kIOSurfaceWidth: @512,
        (NSString*)kIOSurfaceHeight: @512,
        (NSString*)kIOSurfaceBytesPerElement: @4,
        (NSString*)kIOSurfaceBytesPerRow: @(512 * 4),
        (NSString*)kIOSurfacePixelFormat: @(kCVPixelFormatType_32RGBA) // 使用RGBA格式，更兼容OpenGL ES
    };
    
    // 创建IOSurface
    _ioSurface = IOSurfaceCreate((__bridge CFDictionaryRef)surfaceProperties);
    if (!_ioSurface) {
        NSLog(@"Failed to create IOSurface");
        return NO;
    }
    
    NSLog(@"Successfully created IOSurface for rendering with format: %u", (unsigned int)IOSurfaceGetPixelFormat(_ioSurface));
    return YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // 开始渲染
    [_mainRenderer startRendering];
    NSLog(@"Started IOSurface-based rendering in view controller");
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // 停止渲染
    [_mainRenderer stopRendering];
    NSLog(@"Stopped IOSurface-based rendering in view controller");
}

- (void)dealloc {
    if (_ioSurface) {
        CFRelease(_ioSurface);
        _ioSurface = NULL;
    }
}

@end
