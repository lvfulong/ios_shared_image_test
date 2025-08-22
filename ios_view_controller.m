#import "ios_view_controller.h"

@implementation IOSViewControllerDirect

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 设置视图背景色
    self.view.backgroundColor = [UIColor blackColor];
    
    // 创建Metal视图
    _metalView = [[MTKView alloc] initWithFrame:self.view.bounds];
    _metalView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_metalView];
    
    // 创建主渲染器
    _mainRenderer = [[IOSMainRenderer alloc] initWithMetalView:_metalView];
    
    // 初始化渲染器
    if (![_mainRenderer initialize]) {
        NSLog(@"Failed to initialize main renderer");
        return;
    }
    
    NSLog(@"Direct rendering view controller loaded successfully");
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // 开始渲染
    [_mainRenderer startRendering];
    NSLog(@"Started direct rendering in view controller");
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // 停止渲染
    [_mainRenderer stopRendering];
    NSLog(@"Stopped direct rendering in view controller");
}

@end
