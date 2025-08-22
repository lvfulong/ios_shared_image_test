#pragma once

#import <UIKit/UIKit.h>
#ifdef __APPLE__
#import <IOSurface/IOSurfaceRef.h>
#endif
#import "ios_main_renderer.h"

@interface IOSViewControllerDirect : UIViewController

@property (nonatomic, assign) IOSurfaceRef ioSurface;
@property (nonatomic, strong) IOSMainRenderer* mainRenderer;
@property (nonatomic, strong) CADisplayLink* displayLink;

// OpenGL ES 显示相关
@property (nonatomic, strong) EAGLContext* displayContext;
@property (nonatomic, strong) CAEAGLLayer* eaglLayer;
@property (nonatomic, assign) GLuint displayFramebuffer;
@property (nonatomic, assign) GLuint displayRenderbuffer;
@property (nonatomic, assign) CVOpenGLESTextureCacheRef displayTextureCache;
@property (nonatomic, assign) GLuint displayProgram;
@property (nonatomic, assign) GLuint displayVBO;
@property (nonatomic, assign) GLuint displayIBO;

@end
