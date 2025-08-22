#pragma once

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#ifdef __APPLE__
#import <IOSurface/IOSurfaceRef.h>
#endif

@interface IOSTextureManager : NSObject

@property (nonatomic, strong) id<MTLDevice> metalDevice;
@property (nonatomic, strong) id<MTLTexture> renderTexture;

- (instancetype)initWithMetalDevice:(id<MTLDevice>)device;
- (BOOL)initialize;
- (BOOL)updateTextureFromIOSurface:(IOSurfaceRef)ioSurface;
- (id<MTLTexture>)getCurrentTexture;

@end
