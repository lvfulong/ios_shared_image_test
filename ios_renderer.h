#pragma once

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#ifdef __APPLE__
#import <IOSurface/IOSurfaceRef.h>
#endif
#import <CoreVideo/CoreVideo.h>
#import <pthread.h>

@interface IOSRenderer : NSObject

@property (nonatomic, strong) id<MTLDevice> metalDevice;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;

@property (nonatomic, assign) EAGLContext* glContext;
@property (nonatomic, assign) GLuint glProgram;
@property (nonatomic, assign) GLuint glVBO;
@property (nonatomic, assign) GLuint glFBO;

@property (nonatomic, assign) IOSurfaceRef ioSurface;
@property (nonatomic, assign) CVOpenGLESTextureCacheRef textureCache;
@property (nonatomic, assign) CVOpenGLESTextureRef renderTexture;
@property (nonatomic, assign) pthread_mutex_t surfaceMutex;
@property (nonatomic, assign) BOOL hasNewResult;
@property (nonatomic, assign) BOOL isRendering;

@property (nonatomic, assign) NSInteger renderWidth;
@property (nonatomic, assign) NSInteger renderHeight;

- (instancetype)initWithWidth:(NSInteger)width height:(NSInteger)height;
- (BOOL)initialize;
- (void)startRendering;
- (void)stopRendering;
- (IOSurfaceRef)getCurrentSurface;
- (BOOL)hasNewRenderResult;

@end
