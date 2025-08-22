#pragma once

#import <UIKit/UIKit.h>
#import "ios_view_controller.h"

@interface IOSAppDelegateDirect : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow* window;

@end
