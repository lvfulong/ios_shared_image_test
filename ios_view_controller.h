#pragma once

#import <UIKit/UIKit.h>
#ifdef __APPLE__
#import <IOSurface/IOSurfaceRef.h>
#endif
#import "ios_main_renderer.h"

@interface IOSViewControllerDirect : UIViewController

@property (nonatomic, assign) IOSurfaceRef ioSurface;
@property (nonatomic, strong) IOSMainRenderer* mainRenderer;

@end
