#pragma once

#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>
#import "ios_main_renderer_direct.h"

@interface IOSViewControllerDirect : UIViewController

@property (nonatomic, strong) MTKView* metalView;
@property (nonatomic, strong) IOSMainRenderer* mainRenderer;

@end
