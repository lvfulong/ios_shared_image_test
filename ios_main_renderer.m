#import "ios_main_renderer.h"

// Metal 着色器源码
static const char* metalVertexShaderSource = R"(
    #include <metal_stdlib>
    using namespace metal;
    
    struct VertexIn {
        float3 position [[attribute(0)]];
        float2 texCoord [[attribute(1)]];
    };
    
    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };
    
    vertex VertexOut vertex_main(VertexIn in [[stage_in]]) {
        VertexOut out;
        out.position = float4(in.position, 1.0);
        out.texCoord = in.texCoord;
        return out;
    }
)";

static const char* metalFragmentShaderSource = R"(
    #include <metal_stdlib>
    using namespace metal;
    
    struct FragmentIn {
        float2 texCoord;
    };
    
    fragment float4 fragment_main(FragmentIn in [[stage_in]],
                                  texture2d<float> renderTexture [[texture(0)]]) {
        constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
        return renderTexture.sample(textureSampler, in.texCoord);
    }
)";

// 全屏四边形顶点数据 (位置 + 纹理坐标)
static const float quadVertices[] = {
    // 位置 (x, y, z)    纹理坐标 (u, v)
    -1.0f, -1.0f, 0.0f,  0.0f, 1.0f,  // 左下
     1.0f, -1.0f, 0.0f,  1.0f, 1.0f,  // 右下
     1.0f,  1.0f, 0.0f,  1.0f, 0.0f,  // 右上
    -1.0f, -1.0f, 0.0f,  0.0f, 1.0f,  // 左下
     1.0f,  1.0f, 0.0f,  1.0f, 0.0f,  // 右上
    -1.0f,  1.0f, 0.0f,  0.0f, 0.0f   // 左上
};

@implementation IOSMainRenderer

- (instancetype)initWithSurface:(IOSurfaceRef)surface {
    self = [super init];
    if (self) {
        _surfaceRef = surface;
        if (_surfaceRef) {
            CFRetain(_surfaceRef);
        }
    }
    return self;
}

- (BOOL)initialize {
    // 获取Metal设备
    _metalDevice = MTLCreateSystemDefaultDevice();
    if (!_metalDevice) {
        NSLog(@"Metal is not supported on this device");
        return NO;
    }
    
    // 创建命令队列
    _commandQueue = [_metalDevice newCommandQueue];
    if (!_commandQueue) {
        NSLog(@"Failed to create Metal command queue");
        return NO;
    }
    
    // 编译Metal着色器
    if (![self compileMetalShaders]) {
        NSLog(@"Failed to compile Metal shaders");
        return NO;
    }
    
    // 创建顶点缓冲区
    _vertexBuffer = [_metalDevice newBufferWithBytes:quadVertices
                                              length:sizeof(quadVertices)
                                             options:MTLResourceStorageModeShared];
    
    // 初始化子线程渲染器
    _renderer = [[IOSRenderer alloc] initWithWidth:512 height:512];
    if (![_renderer initialize]) {
        NSLog(@"Failed to initialize IOSRenderer");
        return NO;
    }
    
    // 初始化纹理管理器
    _textureManager = [[IOSTextureManager alloc] initWithMetalDevice:_metalDevice];
    if (![_textureManager initialize]) {
        NSLog(@"Failed to initialize IOSTextureManager");
        return NO;
    }
    
    NSLog(@"IOSMainRenderer initialized successfully with IOSurface");
    return YES;
}

- (BOOL)compileMetalShaders {
    NSError* error = nil;
    
    // 创建Metal库
    id<MTLLibrary> library = [_metalDevice newLibraryWithSource:@(metalVertexShaderSource)
                                                         options:nil
                                                           error:&error];
    if (!library) {
        NSLog(@"Failed to create Metal library: %@", error);
        return NO;
    }
    
    // 获取顶点着色器
    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"vertex_main"];
    if (!vertexFunction) {
        NSLog(@"Failed to get vertex function");
        return NO;
    }
    
    // 创建片段着色器库
    id<MTLLibrary> fragmentLibrary = [_metalDevice newLibraryWithSource:@(metalFragmentShaderSource)
                                                                 options:nil
                                                                   error:&error];
    if (!fragmentLibrary) {
        NSLog(@"Failed to create fragment Metal library: %@", error);
        return NO;
    }
    
    // 获取片段着色器
    id<MTLFunction> fragmentFunction = [fragmentLibrary newFunctionWithName:@"fragment_main"];
    if (!fragmentFunction) {
        NSLog(@"Failed to get fragment function");
        return NO;
    }
    
    // 创建渲染管线描述符
    MTLRenderPipelineDescriptor* pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.vertexFunction = vertexFunction;
    pipelineDescriptor.fragmentFunction = fragmentFunction;
    pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    
    // 设置顶点描述符
    MTLVertexDescriptor* vertexDescriptor = [[MTLVertexDescriptor alloc] init];
    vertexDescriptor.attributes[0].format = MTLVertexFormatFloat3;
    vertexDescriptor.attributes[0].offset = 0;
    vertexDescriptor.attributes[0].bufferIndex = 0;
    
    vertexDescriptor.attributes[1].format = MTLVertexFormatFloat2;
    vertexDescriptor.attributes[1].offset = 3 * sizeof(float);
    vertexDescriptor.attributes[1].bufferIndex = 0;
    
    vertexDescriptor.layouts[0].stride = 5 * sizeof(float);
    vertexDescriptor.layouts[0].stepRate = 1;
    vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    pipelineDescriptor.vertexDescriptor = vertexDescriptor;
    
    // 创建渲染管线状态
    _pipelineState = [_metalDevice newRenderPipelineStateWithDescriptor:pipelineDescriptor
                                                                  error:&error];
    if (!_pipelineState) {
        NSLog(@"Failed to create render pipeline state: %@", error);
        return NO;
    }
    
    return YES;
}

- (void)startRendering {
    [_renderer startRendering];
    NSLog(@"Started IOSurface-based rendering");
}

- (void)stopRendering {
    [_renderer stopRendering];
    NSLog(@"Stopped IOSurface-based rendering");
}

- (void)renderToSurface {
    // 检查是否有新的渲染结果
    if ([_renderer hasNewRenderResult]) {
        // 获取当前的IOSurface
        IOSurfaceRef ioSurface = [_renderer getCurrentSurface];
        if (ioSurface) {
            // 关键优化：直接从IOSurface更新Metal纹理，零拷贝！
            if ([_textureManager updateTextureFromIOSurface:ioSurface]) {
                NSLog(@"Successfully updated texture from IOSurface (zero-copy)");
            }
            CFRelease(ioSurface);
        }
    }
    
    // 如果我们需要渲染到目标IOSurface
    if (_surfaceRef) {
        // 这里可以添加渲染到目标IOSurface的逻辑
        // 目前我们只是更新纹理，实际的渲染由外部控制
        NSLog(@"Rendering to target IOSurface");
    }
}

- (void)dealloc {
    if (_surfaceRef) {
        CFRelease(_surfaceRef);
        _surfaceRef = NULL;
    }
}

@end
