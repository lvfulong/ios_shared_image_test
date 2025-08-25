#pragma once

#define GLES_SILENCE_DEPRECATION 1
#define COREVIDEO_GL_SILENCE_DEPRECATION 1

#import <UIKit/UIKit.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/EAGLDrawable.h>
#import <CoreVideo/CoreVideo.h>
#ifdef __APPLE__
#import <IOSurface/IOSurfaceRef.h>
#endif
#import <Metal/Metal.h>
#import "ios_main_renderer.h"

@interface IOSViewControllerDirect : UIViewController

@property (nonatomic, assign) IOSurfaceRef ioSurface;
@property (nonatomic, strong) IOSMainRenderer* mainRenderer;
@property (nonatomic, strong) CADisplayLink* displayLink;

// Metal 显示相关
@property (nonatomic, strong) CAMetalLayer* metalLayer;

// OpenGL ES 显示相关
@property (nonatomic, strong) EAGLContext* displayContext;
@property (nonatomic, strong) CAEAGLLayer* eaglLayer;
@property (nonatomic, assign) GLuint displayFramebuffer;
@property (nonatomic, assign) GLuint displayRenderbuffer;
@property (nonatomic, assign) CVOpenGLESTextureCacheRef displayTextureCache;
@property (nonatomic, assign) GLuint displayProgram;
@property (nonatomic, assign) GLuint displayVBO;
@property (nonatomic, assign) GLuint displayIBO;

// Metal 相关
@property (nonatomic, strong) id<MTLDevice> metalDevice;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;

// 零拷贝方式选择
typedef NS_ENUM(NSInteger, ZeroCopyMethod) {
    ZeroCopyMethodCVOpenGLESTextureCache = 0,  // CVOpenGLESTextureCache (推荐) - 真正的零拷贝
    ZeroCopyMethodMetalTexture = 1,            // Metal纹理直接绑定 - 真正的零拷贝
    ZeroCopyMethodCopy = 2,                    // 拷贝方式 (备用) - 不是零拷贝
    ZeroCopyMethodOpenGLESExtension = 3        // OpenGL ES扩展 (iOS不支持真正的零拷贝)
};

@property (nonatomic, assign) ZeroCopyMethod zeroCopyMethod;

@end
