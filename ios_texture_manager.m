#import "ios_texture_manager.h"
#import <CoreVideo/CoreVideo.h>

@implementation IOSTextureManagerDirect

- (instancetype)initWithMetalDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _metalDevice = device;
    }
    return self;
}

- (BOOL)initialize {
    if (!_metalDevice) {
        NSLog(@"Metal device is not available");
        return NO;
    }
    
    // 初始状态下没有纹理，等待从IOSurface更新
    _renderTexture = nil;
    
    return YES;
}

- (BOOL)updateTextureFromIOSurface:(IOSurfaceRef)ioSurface {
    if (!ioSurface) {
        NSLog(@"IOSurface is nil");
        return NO;
    }
    
    if (!_metalDevice) {
        NSLog(@"Metal device is not available");
        return NO;
    }
    
    // 获取IOSurface的尺寸
    size_t width = IOSurfaceGetWidth(ioSurface);
    size_t height = IOSurfaceGetHeight(ioSurface);
    
    // 检查是否需要创建新纹理或更新现有纹理
    if (!_renderTexture || 
        _renderTexture.width != width || 
        _renderTexture.height != height) {
        
        // 创建新的Metal纹理描述符
        MTLTextureDescriptor* textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                                     width:width
                                                                                                    height:height
                                                                                                 mipmapped:NO];
        
        // 关键优化：直接从IOSurface创建Metal纹理，避免拷贝
        textureDescriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
        
        // 创建纹理
        _renderTexture = [_metalDevice newTextureWithDescriptor:textureDescriptor
                                                      iosurface:ioSurface
                                                          plane:0];
        
        if (!_renderTexture) {
            NSLog(@"Failed to create Metal texture from IOSurface");
            return NO;
        }
        
        NSLog(@"Created new Metal texture from IOSurface: %zux%zu", width, height);
    } else {
        // 纹理已存在且尺寸匹配，直接使用现有的
        // 由于IOSurface是共享内存，数据已经是最新的，无需额外更新
        NSLog(@"Using existing Metal texture from IOSurface");
    }
    
    return YES;
}

- (id<MTLTexture>)getCurrentTexture {
    return _renderTexture;
}

@end
