#pragma once

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#ifdef __APPLE__
#import <IOSurface/IOSurfaceRef.h>
#endif
#import "ios_renderer.h"
#import "ios_texture_manager.h"

@interface IOSMainRenderer : NSObject

@property (nonatomic, assign) IOSurfaceRef surfaceRef;
@property (nonatomic, strong) id<MTLDevice> metalDevice;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id<MTLBuffer> vertexBuffer;

@property (nonatomic, strong) IOSRendererDirect* renderer;
@property (nonatomic, strong) IOSTextureManagerDirect* textureManager;

- (instancetype)initWithSurface:(IOSurfaceRef)surface;
- (BOOL)initialize;
- (void)startRendering;
- (void)stopRendering;

@end
