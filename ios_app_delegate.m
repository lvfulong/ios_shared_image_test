#import "ios_app_delegate_direct.h"

@implementation IOSAppDelegateDirect

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
    // 创建窗口
    _window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    // 创建视图控制器
    IOSViewControllerDirect* viewController = [[IOSViewControllerDirect alloc] init];
    
    // 设置根视图控制器
    _window.rootViewController = viewController;
    
    // 显示窗口
    [_window makeKeyAndVisible];
    
    NSLog(@"Direct rendering iOS app launched successfully");
    return YES;
}

@end
