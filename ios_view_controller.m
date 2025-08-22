#import "ios_view_controller.h"
#import <IOSurface/IOSurfaceRef.h>
#import <QuartzCore/CADisplayLink.h>

@implementation IOSViewControllerDirect

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 设置视图背景色
    self.view.backgroundColor = [UIColor blackColor];
    
    // 创建显示层来显示渲染结果
    [self createDisplayLayer];
    
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

- (void)createDisplayLayer {
    // 创建一个CALayer来显示渲染结果
    _displayLayer = [CALayer layer];
    _displayLayer.frame = self.view.bounds;
    _displayLayer.backgroundColor = [UIColor redColor].CGColor; // 临时红色背景
    [self.view.layer addSublayer:_displayLayer];
    
    NSLog(@"Created display layer");
}

- (BOOL)createIOSurface {
    // 创建IOSurface属性
    NSDictionary* surfaceProperties = @{
        (NSString*)kIOSurfaceWidth: @512,
        (NSString*)kIOSurfaceHeight: @512,
        (NSString*)kIOSurfaceBytesPerElement: @4,
        (NSString*)kIOSurfaceBytesPerRow: @(512 * 4),
        (NSString*)kIOSurfacePixelFormat: @(kCVPixelFormatType_32BGRA) // 使用BGRA格式，更兼容iOS
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
    
    // 创建CADisplayLink来同步显示刷新率
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateDisplay:)];
    _displayLink.preferredFramesPerSecond = 60; // 60 FPS
    [_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // 停止渲染
    [_mainRenderer stopRendering];
    NSLog(@"Stopped IOSurface-based rendering in view controller");
    
    // 停止CADisplayLink
    if (_displayLink) {
        [_displayLink invalidate];
        _displayLink = nil;
    }
}

- (void)updateDisplay:(CADisplayLink*)displayLink {
    [_mainRenderer displayRenderResult];
    
    // 更新显示层（临时方案）
    if (_displayLayer) {
        // 这里可以添加实际的显示更新逻辑
        // 目前只是简单地改变背景色来显示渲染正在工作
        static CGFloat hue = 0.0;
        hue += 0.01;
        if (hue > 1.0) hue = 0.0;
        
        _displayLayer.backgroundColor = [UIColor colorWithHue:hue saturation:1.0 brightness:1.0 alpha:1.0].CGColor;
    }
}

- (void)dealloc {
    // 停止CADisplayLink
    if (_displayLink) {
        [_displayLink invalidate];
        _displayLink = nil;
    }
    
    if (_ioSurface) {
        CFRelease(_ioSurface);
        _ioSurface = NULL;
    }
}

@end
