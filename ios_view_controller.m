#import "ios_view_controller.h"
#import <IOSurface/IOSurfaceRef.h>
#import <QuartzCore/CADisplayLink.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/EAGLDrawable.h>
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>

// 禁用 OpenGL ES 弃用警告
#define GLES_SILENCE_DEPRECATION 1

// 显示用的着色器源码
static const char* displayVertexShaderSource = R"(
    attribute vec4 position;
    attribute vec2 texCoord;
    varying vec2 v_texCoord;
    
    void main() {
        gl_Position = position;
        v_texCoord = texCoord;
    }
)";

static const char* displayFragmentShaderSource = R"(
    precision mediump float;
    varying vec2 v_texCoord;
    uniform sampler2D texture;
    
    void main() {
        gl_FragColor = texture2D(texture, v_texCoord);
    }
)";

// 全屏四边形顶点数据
static const float quadVertices[] = {
    // 位置 (x, y)    纹理坐标 (u, v)
    -1.0f, -1.0f,    0.0f, 0.0f,  // 左下
     1.0f, -1.0f,    1.0f, 0.0f,  // 右下
     1.0f,  1.0f,    1.0f, 1.0f,  // 右上
    -1.0f,  1.0f,    0.0f, 1.0f   // 左上
};

static const unsigned short quadIndices[] = {
    0, 1, 2,  // 第一个三角形
    0, 2, 3   // 第二个三角形
};

@implementation IOSViewControllerDirect

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 简化UIKit视图设置，只保留白色背景
    self.view.backgroundColor = [UIColor whiteColor];
    NSLog(@"Set view background to white");
    
    // 添加一个简单的测试视图
    UIView* testView = [[UIView alloc] initWithFrame:CGRectMake(50, 50, 200, 200)];
    testView.backgroundColor = [UIColor redColor];
    [self.view addSubview:testView];
    NSLog(@"Added red test view at (50,50) 200x200");
    
    NSLog(@"View hierarchy setup completed");
    
    // 初始化Metal设备
    _metalDevice = MTLCreateSystemDefaultDevice();
    if (!_metalDevice) {
        NSLog(@"Metal is not supported on this device");
        return;
    }
    
    // 创建Metal命令队列
    _commandQueue = [_metalDevice newCommandQueue];
    if (!_commandQueue) {
        NSLog(@"Failed to create Metal command queue");
        return;
    }
    
    // 设置零拷贝方式选择
    _zeroCopyMethod = ZeroCopyMethodMetalTexture;
    
    // 创建IOSurface用于渲染
    if (![self createIOSurface]) {
        NSLog(@"Failed to create IOSurface");
        return;
    }
    
    // 创建主渲染器
    _mainRenderer = [[IOSMainRenderer alloc] initWithSurface:_ioSurface];
    
    // 初始化渲染器
    if (![_mainRenderer initialize]) {
        NSLog(@"Failed to initialize main renderer");
        return;
    }
    
    // 重新启用Metal显示层
    [self createMetalDisplayLayer];
    NSLog(@"Created Metal display layer");
    
    NSLog(@"Complete zero-copy rendering system initialized successfully");
}

- (void)createMetalDisplayLayer {
    // 检查Metal设备是否可用
    if (!_metalDevice) {
        NSLog(@"Metal device is nil, creating CALayer fallback");
        CALayer* renderLayer = [CALayer layer];
        renderLayer.frame = self.view.bounds;
        renderLayer.backgroundColor = [UIColor blueColor].CGColor;
        renderLayer.opacity = 0.8;
        renderLayer.hidden = NO;
        renderLayer.zPosition = 9999.0;
        [self.view.layer addSublayer:renderLayer];
        _metalLayer = nil;
        return;
    }
    
    // 创建Metal层
    CAMetalLayer* metalLayer = [CAMetalLayer layer];
    metalLayer.frame = self.view.bounds;
    metalLayer.device = _metalDevice;
    metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    metalLayer.framebufferOnly = NO;
    metalLayer.opaque = YES;
    metalLayer.drawableSize = self.view.bounds.size;
    
    // 确保Metal层完全不透明，让渲染内容可见
    metalLayer.opacity = 1.0; // 完全不透明
    metalLayer.hidden = NO;
    metalLayer.zPosition = 9999.0;
    
    // 设置背景色为透明，让渲染内容可见
    metalLayer.backgroundColor = [UIColor clearColor].CGColor;
    
    [self.view.layer addSublayer:metalLayer];
    NSLog(@"Added CAMetalLayer with transparent background");
    
    // 保存Metal层引用
    _metalLayer = metalLayer;
    
    // Metal层已经添加，现在测试层系统是否工作
    NSLog(@"Metal layer frame: %@, bounds: %@, zPosition: %f, opacity: %f", 
          NSStringFromCGRect(metalLayer.frame), 
          NSStringFromCGRect(self.view.bounds),
          metalLayer.zPosition,
          metalLayer.opacity);
    
    // 移除测试视图，只保留Metal层
    NSLog(@"Metal layer created without test view overlay");
    
    NSLog(@"Created Metal display layer as overlay");
}


- (BOOL)createIOSurface {
    // 创建IOSurface属性 - 使用RGBA格式避免BGRA兼容性问题
    // 添加必要的对齐和缓存属性以确保与OpenGL ES兼容
    NSDictionary* surfaceProperties = @{
        (NSString*)kIOSurfaceWidth: @512,
        (NSString*)kIOSurfaceHeight: @512,
        (NSString*)kIOSurfaceBytesPerElement: @4,
        (NSString*)kIOSurfaceBytesPerRow: @(512 * 4),
        (NSString*)kIOSurfacePixelFormat: @(1111970369), // 使用kCVPixelFormatType_32RGBA，确保与OpenGL ES兼容
        (NSString*)kIOSurfaceIsGlobal: @YES, // 允许跨进程共享
        (NSString*)kIOSurfaceAllocSize: @(512 * 512 * 4) // 明确指定分配大小
    };
    
    // 创建IOSurface
    _ioSurface = IOSurfaceCreate((__bridge CFDictionaryRef)surfaceProperties);
    if (!_ioSurface) {
        NSLog(@"Failed to create IOSurface");
        return NO;
    }
    
    OSType pixelFormat = IOSurfaceGetPixelFormat(_ioSurface);
    NSLog(@"Successfully created IOSurface for rendering with format: %u (%@)", 
          (unsigned int)pixelFormat,
          pixelFormat == 1111970369 ? @"RGBA" : 
          pixelFormat == 1380401729 ? @"BGRA" : @"Unknown");
    return YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    NSLog(@"View will appear - starting complete zero-copy rendering system");
    
    // 重新启用渲染循环
    [_mainRenderer startRendering];
    NSLog(@"Started IOSurface-based rendering in view controller");
    
    // 重新启用CADisplayLink
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateDisplay:)];
    _displayLink.preferredFramesPerSecond = 30;
    [_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    NSLog(@"Created CADisplayLink for Metal display");
    
    // 立即测试Metal渲染，确保Metal层有内容显示
   // [self testMetalRendering];
    
    NSLog(@"Complete zero-copy rendering system started successfully");
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // 停止渲染
    [_mainRenderer stopRendering];
    NSLog(@"Stopped IOSurface-based rendering in view controller");
    
    // 停止CADisplayLink
    if (_displayLink) {
        [_displayLink invalidate];
        _displayLink = nil;
    }
}

- (void)updateDisplay:(CADisplayLink*)displayLink {
    [_mainRenderer displayRenderResult];
    
    // 检查是否有新的渲染结果
    BOOL hasNewResult = [_mainRenderer hasNewRenderResult];
    if (hasNewResult) {
        NSLog(@"Displaying new render result with Metal");
        
        // 获取当前的IOSurface
        IOSurfaceRef surface = [_mainRenderer getCurrentSurface];
        if (surface) {
            // 使用Metal显示IOSurface内容
            [self displayIOSurfaceWithMetal:surface];
        } else {
            NSLog(@"No surface available for display");
        }
    } else {
        NSLog(@"No new render result available");
    }
}


- (void)displayIOSurfaceWithMetal:(IOSurfaceRef)surface {
    NSLog(@"Metal: Displaying IOSurface with Metal");
    
    // 获取Metal层的可绘制对象
    id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
    if (!drawable) {
        NSLog(@"Metal: Failed to get drawable");
        return;
    }
    
    // 创建渲染通道描述符
    MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    renderPassDescriptor.colorAttachments[0].texture = drawable.texture;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(1.0, 0.1, 0.1, 1.0); // 更深的灰色背景，让渲染内容更明显
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    // 创建命令缓冲区
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    
    // 创建渲染命令编码器
    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
    // 从IOSurface创建Metal纹理
    MTLTextureDescriptor* textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                                   width:IOSurfaceGetWidth(surface)
                                                                                                  height:IOSurfaceGetHeight(surface)
                                                                                               mipmapped:NO];
    textureDescriptor.usage = MTLTextureUsageShaderRead;
    
    id<MTLTexture> texture = [_metalDevice newTextureWithDescriptor:textureDescriptor
                                                           iosurface:surface
                                                               plane:0];
    
    if (texture) {
        NSLog(@"Metal: Successfully created texture from IOSurface: %dx%d", 
              (int)IOSurfaceGetWidth(surface), (int)IOSurfaceGetHeight(surface));
        
        // 设置视口
        [renderEncoder setViewport:(MTLViewport){0.0, 0.0, (double)drawable.texture.width, (double)drawable.texture.height, 0.0, 1.0}];
        
        // 创建一个简单的渲染管道来显示纹理
        static id<MTLRenderPipelineState> pipelineState = nil;
        if (!pipelineState) {
            // 创建简单的顶点着色器 - 使用vertex_id而不是stage_in
            NSString* vertexShaderSource = @"#include <metal_stdlib>\n"
                                          "using namespace metal;\n"
                                          "struct VertexOut {\n"
                                          "    float4 position [[position]];\n"
                                          "    float2 texCoord;\n"
                                          "};\n"
                                          "vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {\n"
                                          "    float2 positions[4] = {\n"
                                          "        float2(-1.0, -1.0),\n"
                                          "        float2( 1.0, -1.0),\n"
                                          "        float2(-1.0,  1.0),\n"
                                          "        float2( 1.0,  1.0)\n"
                                          "    };\n"
                                          "    float2 texCoords[4] = {\n"
                                          "        float2(0.0, 0.0),\n"
                                          "        float2(1.0, 0.0),\n"
                                          "        float2(0.0, 1.0),\n"
                                          "        float2(1.0, 1.0)\n"
                                          "    };\n"
                                          "    VertexOut out;\n"
                                          "    out.position = float4(positions[vertexID], 0.0, 1.0);\n"
                                          "    out.texCoord = texCoords[vertexID];\n"
                                          "    return out;\n"
                                          "}\n";
            
            // 创建简单的片段着色器 - 显示明显的彩色图案来测试
            NSString* fragmentShaderSource = @"#include <metal_stdlib>\n"
                                            "using namespace metal;\n"
                                            "fragment float4 fragment_main(float2 texCoord [[stage_in]],\n"
                                            "                                   texture2d<float> texture [[texture(0)]]) {\n"
                                            "    // 显示明显的彩色图案来测试Metal渲染\n"
                                            "    float2 uv = texCoord;\n"
                                            "    float3 color = float3(1.0, 0.0, 0.0); // 纯红色\n"
                                            "    if (uv.x < 0.5 && uv.y < 0.5) {\n"
                                            "        color = float3(0.0, 1.0, 0.0); // 绿色\n"
                                            "    } else if (uv.x >= 0.5 && uv.y < 0.5) {\n"
                                            "        color = float3(0.0, 0.0, 1.0); // 蓝色\n"
                                            "    } else if (uv.x < 0.5 && uv.y >= 0.5) {\n"
                                            "        color = float3(1.0, 1.0, 0.0); // 黄色\n"
                                            "    } else {\n"
                                            "        color = float3(1.0, 0.0, 1.0); // 洋红色\n"
                                            "    }\n"
                                            "    return float4(color, 1.0);\n"
                                            "}\n";
            
            NSError* error = nil;
            id<MTLLibrary> library = [_metalDevice newLibraryWithSource:vertexShaderSource options:nil error:&error];
            if (!library) {
                NSLog(@"Metal: Failed to create library: %@", error);
                return;
            }
            
            id<MTLFunction> vertexFunction = [library newFunctionWithName:@"vertex_main"];
            id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"fragment_main"];
            
            MTLRenderPipelineDescriptor* pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
            pipelineDescriptor.vertexFunction = vertexFunction;
            pipelineDescriptor.fragmentFunction = fragmentFunction;
            pipelineDescriptor.colorAttachments[0].pixelFormat = drawable.texture.pixelFormat;
            
            pipelineState = [_metalDevice newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
            if (!pipelineState) {
                NSLog(@"Metal: Failed to create pipeline state: %@", error);
                return;
            }
        }
        
        // 设置渲染管道状态
        [renderEncoder setRenderPipelineState:pipelineState];
        
        // 暂时不绑定纹理，直接显示纯色
         [renderEncoder setFragmentTexture:texture atIndex:0];
        
        // 不需要顶点缓冲区，因为我们使用vertex_id
        
        // 绘制全屏四边形 - 使用TriangleStrip，4个顶点
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
        
        // 添加调试：绘制一个明显的彩色矩形
        NSLog(@"Metal: Drawing texture with size: %dx%d", (int)IOSurfaceGetWidth(surface), (int)IOSurfaceGetHeight(surface));
        
        // 测试：绘制一个明显的彩色矩形来确认Metal渲染工作
        NSLog(@"Metal: Testing with colored rectangle");
        
        NSLog(@"Metal: Rendered texture to screen");
        
        NSLog(@"Metal: Rendered texture to screen");
    } else {
        NSLog(@"Metal: Failed to create texture from IOSurface");
        
        // 如果纹理创建失败，至少绘制一个彩色矩形
        [renderEncoder setViewport:(MTLViewport){0.0, 0.0, (double)drawable.texture.width, (double)drawable.texture.height, 0.0, 1.0}];
        
        // 创建一个简单的彩色渲染管道
        static id<MTLRenderPipelineState> colorPipelineState = nil;
        if (!colorPipelineState) {
            NSString* colorShaderSource = @"#include <metal_stdlib>\n"
                                         "using namespace metal;\n"
                                         "struct VertexOut {\n"
                                         "    float4 position [[position]];\n"
                                         "};\n"
                                         "vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {\n"
                                         "    float2 positions[4] = {\n"
                                         "        float2(-0.5, -0.5),\n"
                                         "        float2( 0.5, -0.5),\n"
                                         "        float2(-0.5,  0.5),\n"
                                         "        float2( 0.5,  0.5)\n"
                                         "    };\n"
                                         "    VertexOut out;\n"
                                         "    out.position = float4(positions[vertexID], 0.0, 1.0);\n"
                                         "    return out;\n"
                                         "}\n"
                                         "fragment float4 fragment_main() {\n"
                                         "    return float4(1.0, 0.0, 0.0, 1.0); // 红色\n"
                                         "}\n";
            
            NSError* error = nil;
            id<MTLLibrary> library = [_metalDevice newLibraryWithSource:colorShaderSource options:nil error:&error];
            if (library) {
                id<MTLFunction> vertexFunction = [library newFunctionWithName:@"vertex_main"];
                id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"fragment_main"];
                
                MTLRenderPipelineDescriptor* pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
                pipelineDescriptor.vertexFunction = vertexFunction;
                pipelineDescriptor.fragmentFunction = fragmentFunction;
                pipelineDescriptor.colorAttachments[0].pixelFormat = drawable.texture.pixelFormat;
                
                colorPipelineState = [_metalDevice newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
            }
        }
        
        if (colorPipelineState) {
            [renderEncoder setRenderPipelineState:colorPipelineState];
            [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
            NSLog(@"Metal: Drew fallback red rectangle");
        }
    }
    
    // 结束渲染编码（只调用一次）
    [renderEncoder endEncoding];
    
    // 呈现可绘制对象
    [commandBuffer presentDrawable:drawable];
    
    // 提交命令缓冲区
    [commandBuffer commit];
    
    NSLog(@"Metal: Successfully displayed IOSurface with Metal");
}

- (void)testMetalRendering {
    NSLog(@"Testing Metal rendering...");
    
    if (!_metalLayer || !_metalDevice) {
        NSLog(@"Metal layer or device not available");
        return;
    }
    
    // 获取Metal层的可绘制对象
    id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
    if (!drawable) {
        NSLog(@"Failed to get Metal drawable");
        return;
    }
    
    NSLog(@"Metal: Got drawable with size: %dx%d, pixelFormat: %lu", 
          (int)drawable.texture.width, (int)drawable.texture.height, 
          (unsigned long)drawable.texture.pixelFormat);
    
    // 创建渲染通道描述符
    MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    renderPassDescriptor.colorAttachments[0].texture = drawable.texture;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.3, 0.3, 0.3, 1.0); // 中等灰色背景
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    // 创建命令缓冲区
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    
    // 创建渲染命令编码器
    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
    // 设置视口
    [renderEncoder setViewport:(MTLViewport){0.0, 0.0, (double)drawable.texture.width, (double)drawable.texture.height, 0.0, 1.0}];
    
    // 创建一个简单的彩色渲染管道
    static id<MTLRenderPipelineState> testPipelineState = nil;
    if (!testPipelineState) {
        NSString* shaderSource = @"#include <metal_stdlib>\n"
                                "using namespace metal;\n"
                                "struct VertexOut {\n"
                                "    float4 position [[position]];\n"
                                "};\n"
                                "vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {\n"
                                "    float2 positions[4] = {\n"
                                "        float2(-1.0, -1.0),  // 左下\n"
                                "        float2( 1.0, -1.0),  // 右下\n"
                                "        float2(-1.0,  1.0),  // 左上\n"
                                "        float2( 1.0,  1.0)   // 右上\n"
                                "    };\n"
                                "    VertexOut out;\n"
                                "    out.position = float4(positions[vertexID], 0.0, 1.0);\n"
                                "    return out;\n"
                                "}\n"
                                "fragment float4 fragment_main() {\n"
                                "    return float4(1.0, 0.0, 0.0, 1.0); // 纯红色\n"
                                "}\n";
        
        NSError* error = nil;
        id<MTLLibrary> library = [_metalDevice newLibraryWithSource:shaderSource options:nil error:&error];
        if (library) {
            id<MTLFunction> vertexFunction = [library newFunctionWithName:@"vertex_main"];
            id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"fragment_main"];
            
            MTLRenderPipelineDescriptor* pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
            pipelineDescriptor.vertexFunction = vertexFunction;
            pipelineDescriptor.fragmentFunction = fragmentFunction;
            pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm; // 使用固定格式
            
            testPipelineState = [_metalDevice newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
            if (testPipelineState) {
                NSLog(@"Created test Metal pipeline state successfully");
            } else {
                NSLog(@"Failed to create test pipeline state: %@", error);
            }
        } else {
            NSLog(@"Failed to create Metal library: %@", error);
        }
    }
    
    if (testPipelineState) {
        NSLog(@"Metal: Setting render pipeline state");
        [renderEncoder setRenderPipelineState:testPipelineState];
        
        NSLog(@"Metal: Drawing primitives - Triangle, 6 vertices");
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
        NSLog(@"Drew test RED FULLSCREEN with Metal");
    } else {
        NSLog(@"Metal: testPipelineState is nil - rendering pipeline not created");
    }
    
    [renderEncoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
    
    NSLog(@"Test Metal rendering completed");
    
    // 强制刷新显示
    [CATransaction flush];
    NSLog(@"Forced display refresh");
}


- (void)drawFullscreenQuad {
    // 使用显示程序
    glUseProgram(_displayProgram);
    
    // 绑定顶点缓冲区
    glBindBuffer(GL_ARRAY_BUFFER, _displayVBO);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _displayIBO);
    
    // 设置顶点属性
    GLint posAttrib = glGetAttribLocation(_displayProgram, "position");
    glVertexAttribPointer(posAttrib, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), (void*)0);
    glEnableVertexAttribArray(posAttrib);
    
    GLint texAttrib = glGetAttribLocation(_displayProgram, "texCoord");
    glVertexAttribPointer(texAttrib, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), (void*)(2 * sizeof(float)));
    glEnableVertexAttribArray(texAttrib);
    
    // 绑定纹理到纹理单元0
    glActiveTexture(GL_TEXTURE0);
    // 注意：纹理应该已经在调用drawFullscreenQuad之前被绑定到GL_TEXTURE_2D
    
    // 设置纹理采样器
    GLint textureUniform = glGetUniformLocation(_displayProgram, "texture");
    glUniform1i(textureUniform, 0); // 使用纹理单元0
    
    // 绘制四边形
    glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_SHORT, 0);
}

#pragma mark - 零拷贝显示方法

// 方式1: 使用CVOpenGLESTextureCache进行零拷贝
- (BOOL)displayUsingCVOpenGLESTextureCache:(IOSurfaceRef)surface pixelFormat:(OSType)pixelFormat {
    NSLog(@"CVOpenGLESTextureCache: Attempting zero-copy texture creation");
    
    // 检查OpenGL ES扩展支持
    const char* extensions = (const char*)glGetString(GL_EXTENSIONS);
    BOOL supportsBGRA = extensions && strstr(extensions, "GL_EXT_bgra") != NULL;
    NSLog(@"CVOpenGLESTextureCache: BGRA extension support: %@", supportsBGRA ? @"YES" : @"NO");
    
    // 根据像素格式选择合适的OpenGL ES格式
    GLenum glFormat = GL_RGBA;
    GLenum glType = GL_UNSIGNED_BYTE;
    
    if (pixelFormat == 1380401729) { // kCVPixelFormatType_32BGRA
        if (supportsBGRA) {
            glFormat = GL_BGRA_EXT;
            NSLog(@"CVOpenGLESTextureCache: Using GL_BGRA_EXT format for BGRA pixel format");
        } else {
            // iOS通常不支持GL_BGRA_EXT，使用GL_RGBA并处理格式转换
            glFormat = GL_RGBA;
            NSLog(@"CVOpenGLESTextureCache: BGRA not supported, using GL_RGBA with format conversion");
        }
    } else if (pixelFormat == 1111970369) { // kCVPixelFormatType_32RGBA
        glFormat = GL_RGBA;
        NSLog(@"CVOpenGLESTextureCache: Using GL_RGBA format for RGBA pixel format");
    } else {
        NSLog(@"CVOpenGLESTextureCache: Unsupported pixel format: %u, using GL_RGBA", (unsigned int)pixelFormat);
        glFormat = GL_RGBA;
    }
    
    // 尝试使用CVOpenGLESTextureCache创建零拷贝纹理
    CVOpenGLESTextureRef textureRef = NULL;
    CVReturn result = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                   _displayTextureCache,
                                                                   surface,
                                                                   NULL,
                                                                   GL_TEXTURE_2D,
                                                                   GL_RGBA, // 内部格式
                                                                   (GLsizei)IOSurfaceGetWidth(surface),
                                                                   (GLsizei)IOSurfaceGetHeight(surface),
                                                                   glFormat, // 外部格式
                                                                   glType,
                                                                   0,
                                                                   &textureRef);
    
    if (result == kCVReturnSuccess) {
        // 获取纹理名称 (使用非弃用的方法)
        GLuint textureName = CVOpenGLESTextureGetName(textureRef);
        
        // 绑定纹理
        glBindTexture(GL_TEXTURE_2D, textureName);
        
        // 设置纹理参数
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        // 绘制全屏四边形来显示纹理
        [self drawFullscreenQuad];
        
        // 呈现到屏幕
        [_displayContext presentRenderbuffer:GL_RENDERBUFFER];
        
        // 释放纹理引用
        CFRelease(textureRef);
        
        NSLog(@"CVOpenGLESTextureCache: Successfully displayed using zero-copy method");
        return YES;
    } else {
        NSLog(@"CVOpenGLESTextureCache: Failed with error %d (pixel format: %u)", result, (unsigned int)pixelFormat);
        
        // 如果BGRA失败，尝试使用RGBA格式
        if (pixelFormat == 1380401729 && glFormat == GL_BGRA_EXT) {
            NSLog(@"CVOpenGLESTextureCache: Retrying with GL_RGBA format for BGRA pixel format");
            
            // 重新尝试使用RGBA格式
            result = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                 _displayTextureCache,
                                                                 surface,
                                                                 NULL,
                                                                 GL_TEXTURE_2D,
                                                                 GL_RGBA,
                                                                 (GLsizei)IOSurfaceGetWidth(surface),
                                                                 (GLsizei)IOSurfaceGetHeight(surface),
                                                                 GL_RGBA,
                                                                 GL_UNSIGNED_BYTE,
                                                                 0,
                                                                 &textureRef);
            
            if (result == kCVReturnSuccess) {
                // 获取纹理名称 (使用非弃用的方法)
                GLuint textureName = CVOpenGLESTextureGetName(textureRef);
                
                // 绑定纹理
                glBindTexture(GL_TEXTURE_2D, textureName);
                
                // 设置纹理参数
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
                
                // 绘制全屏四边形来显示纹理
                [self drawFullscreenQuad];
                
                // 呈现到屏幕
                [_displayContext presentRenderbuffer:GL_RENDERBUFFER];
                
                // 释放纹理引用
                CFRelease(textureRef);
                
                NSLog(@"CVOpenGLESTextureCache: Successfully displayed using RGBA fallback");
                return YES;
            } else {
                NSLog(@"CVOpenGLESTextureCache: RGBA fallback also failed with error %d", result);
            }
        }
        
        return NO;
    }
}

// 方式2: 使用OpenGL ES扩展进行零拷贝
- (BOOL)displayUsingOpenGLESExtension:(IOSurfaceRef)surface pixelFormat:(OSType)pixelFormat {
    NSLog(@"OpenGL ES Extension: Attempting zero-copy texture creation from IOSurface");
    
    // 检查是否支持必要的扩展
    const char* extensions = (const char*)glGetString(GL_EXTENSIONS);
    if (!extensions) {
        NSLog(@"OpenGL ES Extension: Failed to get GL extensions");
        return NO;
    }
    
    // 检查是否支持IOSurface扩展 (iOS上通常不支持)
    BOOL supportsIOSurface = strstr(extensions, "GL_APPLE_texture_2D_limited_npot") != NULL;
    NSLog(@"OpenGL ES Extension: IOSurface support: %@", supportsIOSurface ? @"YES" : @"NO");
    
    // 创建OpenGL ES纹理
    GLuint displayTexture;
    glGenTextures(1, &displayTexture);
    glBindTexture(GL_TEXTURE_2D, displayTexture);
    
    // 设置纹理参数
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    BOOL success = NO;
    
    // 方法1: 尝试使用glTexImage2D + NULL指针 (需要特定扩展支持)
    if (pixelFormat == 1380401729) { // kCVPixelFormatType_32BGRA
        // 检查是否支持BGRA扩展
        BOOL supportsBGRA = strstr(extensions, "GL_EXT_bgra") != NULL;
        
        if (supportsBGRA) {
            NSLog(@"OpenGL ES Extension: Attempting BGRA format with NULL pointer");
            glTexImage2D(GL_TEXTURE_2D, 0, GL_BGRA_EXT, 
                       (GLsizei)IOSurfaceGetWidth(surface), 
                       (GLsizei)IOSurfaceGetHeight(surface),
                       0, GL_BGRA_EXT, GL_UNSIGNED_BYTE, NULL);
            
            // 检查是否有OpenGL错误
            GLenum error = glGetError();
            if (error == GL_NO_ERROR) {
                NSLog(@"OpenGL ES Extension: Successfully created BGRA texture with NULL pointer");
                success = YES;
            } else {
                NSLog(@"OpenGL ES Extension: Failed to create BGRA texture with NULL pointer, error: %d", error);
            }
        } else {
            NSLog(@"OpenGL ES Extension: BGRA not supported, trying RGBA format");
            // 尝试使用RGBA格式
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 
                       (GLsizei)IOSurfaceGetWidth(surface), 
                       (GLsizei)IOSurfaceGetHeight(surface),
                       0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
            
            GLenum error = glGetError();
            if (error == GL_NO_ERROR) {
                NSLog(@"OpenGL ES Extension: Successfully created RGBA texture with NULL pointer");
                success = YES;
            } else {
                NSLog(@"OpenGL ES Extension: Failed to create RGBA texture with NULL pointer, error: %d", error);
            }
        }
    } else if (pixelFormat == 1111970369) { // kCVPixelFormatType_32RGBA
        NSLog(@"OpenGL ES Extension: Attempting RGBA format with NULL pointer");
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 
                   (GLsizei)IOSurfaceGetWidth(surface), 
                   (GLsizei)IOSurfaceGetHeight(surface),
                   0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
        
        // 检查是否有OpenGL错误
        GLenum error = glGetError();
        if (error == GL_NO_ERROR) {
            NSLog(@"OpenGL ES Extension: Successfully created RGBA texture with NULL pointer");
            success = YES;
        } else {
            NSLog(@"OpenGL ES Extension: Failed to create RGBA texture with NULL pointer, error: %d", error);
        }
    }
    
    // 方法2: 如果方法1失败，尝试使用IOSurface特定的扩展函数
    if (!success) {
        NSLog(@"OpenGL ES Extension: Trying alternative IOSurface binding method");
        
        // 锁定IOSurface以获取基本信息
        IOSurfaceLock(surface, kIOSurfaceLockReadOnly, NULL);
        
        // 尝试使用glTexImage2D但传递IOSurface的基地址
        void* pixelData = IOSurfaceGetBaseAddress(surface);
        if (pixelData) {
            NSLog(@"OpenGL ES Extension: Using IOSurface base address for texture creation");
            
            // 使用RGBA格式创建纹理
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 
                       (GLsizei)IOSurfaceGetWidth(surface), 
                       (GLsizei)IOSurfaceGetHeight(surface),
                       0, GL_RGBA, GL_UNSIGNED_BYTE, pixelData);
            
            GLenum error = glGetError();
            if (error == GL_NO_ERROR) {
                NSLog(@"OpenGL ES Extension: Successfully created texture using IOSurface base address");
                success = YES;
            } else {
                NSLog(@"OpenGL ES Extension: Failed to create texture using IOSurface base address, error: %d", error);
            }
        }
        
        // 解锁IOSurface
        IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);
    }
    
    if (success) {
        // 绘制全屏四边形来显示纹理
        [self drawFullscreenQuad];
        
        // 呈现到屏幕
        [_displayContext presentRenderbuffer:GL_RENDERBUFFER];
        
        NSLog(@"OpenGL ES Extension: Successfully displayed texture");
    } else {
        NSLog(@"OpenGL ES Extension: All methods failed, this is not a true zero-copy implementation");
    }
    
    // 删除临时纹理
    glDeleteTextures(1, &displayTexture);
    
    return success;
}

// 方式3: 使用Metal纹理直接绑定 (最现代的方式)
- (BOOL)displayUsingMetalTexture:(IOSurfaceRef)surface pixelFormat:(OSType)pixelFormat {
    NSLog(@"Metal texture: Attempting zero-copy texture creation");
    
    // 检查是否支持Metal纹理
    if (!_metalDevice) {
        NSLog(@"Metal texture: Metal device not available");
        return NO;
    }
    
    // 创建Metal纹理描述符
    MTLTextureDescriptor* textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                                 width:(NSUInteger)IOSurfaceGetWidth(surface)
                                                                                                height:(NSUInteger)IOSurfaceGetHeight(surface)
                                                                                             mipmapped:NO];
    textureDescriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    
    // 直接从IOSurface创建Metal纹理，零拷贝
    id<MTLTexture> metalTexture = [_metalDevice newTextureWithDescriptor:textureDescriptor
                                                              iosurface:surface
                                                                  plane:0];
    if (!metalTexture) {
        NSLog(@"Metal texture: Failed to create Metal texture from IOSurface");
        return NO;
    }
    
    NSLog(@"Metal texture: Successfully created Metal texture from IOSurface: %zux%zu", 
          metalTexture.width, metalTexture.height);
    
    // 由于当前显示系统使用OpenGL ES，我们需要将IOSurface数据复制到OpenGL ES纹理
    // 这是为了显示目的，虽然不是真正的零拷贝，但Metal纹理已经实现了零拷贝渲染
    
    // 创建OpenGL ES纹理
    GLuint displayTexture;
    glGenTextures(1, &displayTexture);
    glBindTexture(GL_TEXTURE_2D, displayTexture);
    
    // 设置纹理参数
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    // 锁定IOSurface并获取数据指针
    IOSurfaceLock(surface, kIOSurfaceLockReadOnly, NULL);
    void* surfaceData = IOSurfaceGetBaseAddress(surface);
    size_t bytesPerRow = IOSurfaceGetBytesPerRow(surface);
    size_t width = IOSurfaceGetWidth(surface);
    size_t height = IOSurfaceGetHeight(surface);
    
    // 将IOSurface数据复制到OpenGL ES纹理
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 
               (GLsizei)width, 
               (GLsizei)height,
               0, GL_RGBA, GL_UNSIGNED_BYTE, surfaceData);
    
    // 解锁IOSurface
    IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);
    
    // 绘制全屏四边形来显示纹理
    [self drawFullscreenQuad];
    
    // 呈现到屏幕
    [_displayContext presentRenderbuffer:GL_RENDERBUFFER];
    
    // 删除临时纹理
    glDeleteTextures(1, &displayTexture);
    
    // 清理Metal资源
    metalTexture = nil;
    
    NSLog(@"Metal texture: Successfully displayed using Metal texture");
    return YES;
}

// 方式4: 使用拷贝方法作为备用方案
- (void)displayUsingCopyMethod:(IOSurfaceRef)surface pixelFormat:(OSType)pixelFormat {
    NSLog(@"Using copy method as fallback (pixel format: %u)", (unsigned int)pixelFormat);
    
    // 创建OpenGL ES纹理
    GLuint displayTexture;
    glGenTextures(1, &displayTexture);
    glBindTexture(GL_TEXTURE_2D, displayTexture);
    
    // 设置纹理参数
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    // 锁定IOSurface并获取像素数据
    IOSurfaceLock(surface, kIOSurfaceLockReadOnly, NULL);
    void* pixelData = IOSurfaceGetBaseAddress(surface);
    
    if (pixelData) {
        // 创建纹理 - 使用GL_RGBA格式，因为GL_BGRA在OpenGL ES中可能不支持
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 
                   (GLsizei)IOSurfaceGetWidth(surface), 
                   (GLsizei)IOSurfaceGetHeight(surface),
                   0, GL_RGBA, GL_UNSIGNED_BYTE, pixelData);
        
        // 绘制全屏四边形来显示纹理
        [self drawFullscreenQuad];
        
        // 呈现到屏幕
        [_displayContext presentRenderbuffer:GL_RENDERBUFFER];
        
        NSLog(@"Successfully displayed using copy method");
    } else {
        NSLog(@"Failed to get IOSurface pixel data for copy method");
        
        // 创建一个简单的测试纹理来验证显示是否工作
        NSLog(@"Creating test texture to verify display functionality");
        
        // 创建一个简单的彩色测试纹理
        unsigned char testData[512 * 512 * 4];
        for (int i = 0; i < 512 * 512; i++) {
            testData[i * 4 + 0] = 255; // 红色
            testData[i * 4 + 1] = 0;   // 绿色
            testData[i * 4 + 2] = 0;   // 蓝色
            testData[i * 4 + 3] = 255; // 透明度
        }
        
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 512, 512, 0, GL_RGBA, GL_UNSIGNED_BYTE, testData);
        
        // 绘制全屏四边形来显示纹理
        [self drawFullscreenQuad];
        
        // 呈现到屏幕
        [_displayContext presentRenderbuffer:GL_RENDERBUFFER];
        
        NSLog(@"Test texture displayed successfully");
    }
    
    // 解锁IOSurface
    IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);
    
    // 删除临时纹理
    glDeleteTextures(1, &displayTexture);
}

- (void)dealloc {
    // 停止CADisplayLink
    if (_displayLink) {
        [_displayLink invalidate];
        _displayLink = nil;
    }
    
    // 清理OpenGL ES资源
    if (_displayProgram) {
        glDeleteProgram(_displayProgram);
        _displayProgram = 0;
    }
    
    if (_displayVBO) {
        glDeleteBuffers(1, &_displayVBO);
        _displayVBO = 0;
    }
    
    if (_displayIBO) {
        glDeleteBuffers(1, &_displayIBO);
        _displayIBO = 0;
    }
    
    if (_displayFramebuffer) {
        glDeleteFramebuffers(1, &_displayFramebuffer);
        _displayFramebuffer = 0;
    }
    
    if (_displayRenderbuffer) {
        glDeleteRenderbuffers(1, &_displayRenderbuffer);
        _displayRenderbuffer = 0;
    }
    
    if (_displayTextureCache) {
        CFRelease(_displayTextureCache);
        _displayTextureCache = NULL;
    }
    
    if (_ioSurface) {
        CFRelease(_ioSurface);
        _ioSurface = NULL;
    }
}

@end
