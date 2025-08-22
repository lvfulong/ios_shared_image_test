#pragma once

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import "ios_renderer.h"
#import "ios_texture_manager_direct.h"

@interface IOSMainRendererDirect : NSObject <MTKViewDelegate>

@property (nonatomic, strong) MTKView* metalView;
@property (nonatomic, strong) id<MTLDevice> metalDevice;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id<MTLBuffer> vertexBuffer;

@property (nonatomic, strong) IOSRendererDirect* renderer;
@property (nonatomic, strong) IOSTextureManagerDirect* textureManager;

- (instancetype)initWithMetalView:(MTKView*)view;
- (BOOL)initialize;
- (void)startRendering;
- (void)stopRendering;

@end
