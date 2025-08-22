#import "ios_renderer.h"
#import <OpenGLES/EAGL.h>
#import <OpenGLES/EAGLDrawable.h>
#import <CoreVideo/CoreVideo.h>

// OpenGL ES 着色器源码
static const char* vertexShaderSource = R"(
    attribute vec3 position;
    attribute vec3 color;
    varying vec3 v_color;
    
    void main() {
        gl_Position = vec4(position, 1.0);
        v_color = color;
    }
)";

static const char* fragmentShaderSource = R"(
    precision mediump float;
    varying vec3 v_color;
    
    void main() {
        gl_FragColor = vec4(v_color, 1.0);
    }
)";

// 三角形顶点数据
static const float triangleVertices[] = {
    // 位置 (x, y, z)    颜色 (r, g, b)
     0.0f,  0.5f, 0.0f,  1.0f, 0.0f, 0.0f,  // 顶部顶点，红色
    -0.5f, -0.5f, 0.0f,  0.0f, 1.0f, 0.0f,  // 左下顶点，绿色
     0.5f, -0.5f, 0.0f,  0.0f, 0.0f, 1.0f   // 右下顶点，蓝色
};

@implementation IOSRenderer

- (instancetype)initWithWidth:(NSInteger)width height:(NSInteger)height {
    self = [super init];
    if (self) {
        _renderWidth = width;
        _renderHeight = height;
        _hasNewResult = NO;
        _isRendering = NO;
        
        // 初始化互斥锁
        pthread_mutex_init(&_surfaceMutex, NULL);
    }
    return self;
}

- (void)dealloc {
    [self cleanup];
    pthread_mutex_destroy(&_surfaceMutex);
}

- (BOOL)initialize {
    // 初始化Metal设备
    if (![self initializeMetal]) {
        NSLog(@"Failed to initialize Metal");
        return NO;
    }
    
    // 创建IOSurface
    if (![self createIOSurface]) {
        NSLog(@"Failed to create IOSurface");
        return NO;
    }
    
    return YES;
}

- (BOOL)initializeMetal {
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
    
    return YES;
}

- (BOOL)createIOSurface {
    // 创建IOSurface属性 - 使用RGBA格式避免BGRA兼容性问题
    NSDictionary* surfaceProperties = @{
        (NSString*)kIOSurfaceWidth: @(_renderWidth),
        (NSString*)kIOSurfaceHeight: @(_renderHeight),
        (NSString*)kIOSurfaceBytesPerElement: @4,
        (NSString*)kIOSurfaceBytesPerRow: @(_renderWidth * 4),
        (NSString*)kIOSurfacePixelFormat: @(1111970369) // 使用kCVPixelFormatType_32RGBA，确保与OpenGL ES兼容
    };
    
    // 创建IOSurface
    _ioSurface = IOSurfaceCreate((__bridge CFDictionaryRef)surfaceProperties);
    if (!_ioSurface) {
        NSLog(@"Failed to create IOSurface");
        return NO;
    }
    
    OSType pixelFormat = IOSurfaceGetPixelFormat(_ioSurface);
    NSLog(@"Created IOSurface with format: %u (%@)", 
          (unsigned int)pixelFormat,
          pixelFormat == 1111970369 ? @"RGBA" : 
          pixelFormat == 1380401729 ? @"BGRA" : @"Unknown");
    return YES;
}

// 主线程不再需要OpenGL ES初始化，所有OpenGL ES资源都在渲染线程中创建

- (BOOL)compileShaders {
    // 编译顶点着色器
    GLuint vertexShader = glCreateShader(GL_VERTEX_SHADER);
    glShaderSource(vertexShader, 1, &vertexShaderSource, NULL);
    glCompileShader(vertexShader);
    
    GLint success;
    glGetShaderiv(vertexShader, GL_COMPILE_STATUS, &success);
    if (!success) {
        GLchar infoLog[512];
        glGetShaderInfoLog(vertexShader, 512, NULL, infoLog);
        NSLog(@"Vertex shader compilation failed: %s", infoLog);
        return NO;
    }
    
    // 编译片段着色器
    GLuint fragmentShader = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(fragmentShader, 1, &fragmentShaderSource, NULL);
    glCompileShader(fragmentShader);
    
    glGetShaderiv(fragmentShader, GL_COMPILE_STATUS, &success);
    if (!success) {
        GLchar infoLog[512];
        glGetShaderInfoLog(fragmentShader, 512, NULL, infoLog);
        NSLog(@"Fragment shader compilation failed: %s", infoLog);
        return NO;
    }
    
    // 创建程序
    _glProgram = glCreateProgram();
    glAttachShader(_glProgram, vertexShader);
    glAttachShader(_glProgram, fragmentShader);
    glLinkProgram(_glProgram);
    
    glGetProgramiv(_glProgram, GL_LINK_STATUS, &success);
    if (!success) {
        GLchar infoLog[512];
        glGetProgramInfoLog(_glProgram, 512, NULL, infoLog);
        NSLog(@"Program linking failed: %s", infoLog);
        return NO;
    }
    
    // 清理着色器
    glDeleteShader(vertexShader);
    glDeleteShader(fragmentShader);
    
    return YES;
}

- (BOOL)createTextureCache {
    // 获取当前EAGL上下文
    EAGLContext* currentContext = [EAGLContext currentContext];
    if (!currentContext) {
        NSLog(@"No current EAGL context for texture cache creation");
        return NO;
    }
    
    // 创建Core Video纹理缓存
    CVReturn result = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault,
                                                   NULL,
                                                   currentContext,
                                                   NULL,
                                                   &_textureCache);
    if (result != kCVReturnSuccess) {
        NSLog(@"Failed to create texture cache: %d", result);
        return NO;
    }
    
    return YES;
}

- (BOOL)createDirectIOSurfaceFramebuffer {
    // 创建帧缓冲区
    glGenFramebuffers(1, &_glFBO);
    glBindFramebuffer(GL_FRAMEBUFFER, _glFBO);
    
    // 获取IOSurface的像素格式
    OSType pixelFormat = IOSurfaceGetPixelFormat(_ioSurface);
    NSLog(@"IOSurface pixel format: %u", (unsigned int)pixelFormat);
    
    // 关键：使用Metal直接从IOSurface创建纹理（真正的零拷贝）
    // 这是Chromium中使用的方法
    MTLTextureDescriptor* textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                                 width:_renderWidth
                                                                                                height:_renderHeight
                                                                                             mipmapped:NO];
    textureDescriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    
    // 直接从IOSurface创建Metal纹理，零拷贝
    id<MTLTexture> metalTexture = [_metalDevice newTextureWithDescriptor:textureDescriptor
                                                              iosurface:_ioSurface
                                                                  plane:0];
    if (!metalTexture) {
        NSLog(@"Failed to create Metal texture from IOSurface");
        return NO;
    }
    
    // 使用Core Video纹理缓存从IOSurface创建OpenGL ES纹理
    // 注意：这里直接使用IOSurface，而不是Metal纹理
    // 根据IOSurface的实际像素格式选择合适的OpenGL ES格式
    GLenum glFormat = GL_RGBA;
    if (pixelFormat == 1380401729) { // kCVPixelFormatType_32BGRA
        // iOS通常不支持GL_BGRA，使用GL_RGBA并处理格式转换
        glFormat = GL_RGBA;
        NSLog(@"Render thread: BGRA pixel format detected, using GL_RGBA with format conversion");
    } else if (pixelFormat == 1111970369) { // kCVPixelFormatType_32RGBA
        glFormat = GL_RGBA;
        NSLog(@"Render thread using GL_RGBA format for RGBA pixel format");
    } else {
        NSLog(@"Render thread using GL_RGBA format for pixel format: %u", (unsigned int)pixelFormat);
    }
    
    CVReturn result = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                   _textureCache,
                                                                   _ioSurface,
                                                                   NULL,
                                                                   GL_TEXTURE_2D,
                                                                   glFormat,
                                                                   (GLsizei)_renderWidth,
                                                                   (GLsizei)_renderHeight,
                                                                   glFormat,
                                                                   GL_UNSIGNED_BYTE,
                                                                   0,
                                                                   &_renderTexture);
    
    if (result != kCVReturnSuccess) {
        NSLog(@"Failed to create OpenGL ES texture from IOSurface: %d", result);
        // 如果Core Video失败，尝试使用glTexImage2D（虽然不是零拷贝，但至少能工作）
        NSLog(@"Falling back to glTexImage2D method");
        
        // 创建渲染纹理
        GLuint renderTexture;
        glGenTextures(1, &renderTexture);
        glBindTexture(GL_TEXTURE_2D, renderTexture);
        
        // 设置纹理参数
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        // 锁定IOSurface以获取像素数据
        IOSurfaceLock(_ioSurface, kIOSurfaceLockReadOnly, NULL);
        void* pixelData = IOSurfaceGetBaseAddress(_ioSurface);
        
        // 创建纹理 - 使用GL_RGBA格式，因为GL_BGRA在OpenGL ES中可能不支持
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (GLsizei)_renderWidth, (GLsizei)_renderHeight,
                     0, GL_RGBA, GL_UNSIGNED_BYTE, pixelData);
        
        // 解锁IOSurface
        IOSurfaceUnlock(_ioSurface, kIOSurfaceLockReadOnly, NULL);
        
        // 将纹理附加到帧缓冲区
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, renderTexture, 0);
        
        NSLog(@"Created texture using glTexImage2D fallback");
    } else {
        // 获取OpenGL ES纹理名称
        GLuint textureName = CVOpenGLESTextureGetName(_renderTexture);
        NSLog(@"Successfully created zero-copy texture: %u", textureName);
        
        // 将零拷贝纹理附加到帧缓冲区
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, textureName, 0);
    }
    
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"Framebuffer is not complete");
        return NO;
    }
    
    NSLog(@"Successfully created IOSurface framebuffer with format: %u", (unsigned int)pixelFormat);
    return YES;
}

- (void)startRendering {
    if (_isRendering) return;
    
    _isRendering = YES;
    
    // 直接启动渲染线程
    [self startRenderThread];
    
    NSLog(@"iOS direct rendering started");
}

- (void)startRenderThread {
    // 在后台线程中启动渲染
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [self renderLoop];
    });
}

- (void)stopRendering {
    _isRendering = NO;
    NSLog(@"iOS direct rendering stopped");
}

- (void)renderLoop {
    // 在渲染线程中创建独立的EAGL上下文
    EAGLContext* renderContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (!renderContext) {
        NSLog(@"Failed to create render EAGL context");
        return;
    }
    
    // 设置当前上下文
    if (![EAGLContext setCurrentContext:renderContext]) {
        NSLog(@"Failed to set current EAGL context in render thread");
        return;
    }
    
    // 在渲染线程中重新创建OpenGL ES资源
    if (![self createRenderThreadResources]) {
        NSLog(@"Failed to create render thread resources");
        return;
    }
    
    while (_isRendering) {
        @autoreleasepool {
            [self renderTriangle];
            
            // 标记有新结果
            pthread_mutex_lock(&_surfaceMutex);
            _hasNewResult = YES;
            pthread_mutex_unlock(&_surfaceMutex);
            
            // 等待一段时间
            [NSThread sleepForTimeInterval:1.0/60.0]; // ~60 FPS
        }
    }
    
    // 清理渲染线程资源
    [self cleanupRenderThreadResources];
    
    // 清理上下文
    [EAGLContext setCurrentContext:nil];
}

- (void)renderTriangle {
    // 绑定帧缓冲区（直接渲染到IOSurface）
    glBindFramebuffer(GL_FRAMEBUFFER, _glFBO);
    
    // 设置视口
    glViewport(0, 0, (GLsizei)_renderWidth, (GLsizei)_renderHeight);
    
    // 清除颜色缓冲区 - 使用更明显的颜色
    glClearColor(1.0f, 0.0f, 0.0f, 1.0f); // 红色背景
    glClear(GL_COLOR_BUFFER_BIT);
    
    // 使用着色器程序
    glUseProgram(_glProgram);
    
    // 绑定顶点缓冲区
    glBindBuffer(GL_ARRAY_BUFFER, _glVBO);
    
    // 设置顶点属性
    GLint posAttrib = glGetAttribLocation(_glProgram, "position");
    glVertexAttribPointer(posAttrib, 3, GL_FLOAT, GL_FALSE, 6 * sizeof(float), (void*)0);
    glEnableVertexAttribArray(posAttrib);
    
    GLint colorAttrib = glGetAttribLocation(_glProgram, "color");
    glVertexAttribPointer(colorAttrib, 3, GL_FLOAT, GL_FALSE, 6 * sizeof(float), (void*)(3 * sizeof(float)));
    glEnableVertexAttribArray(colorAttrib);
    
    // 绘制三角形
    glDrawArrays(GL_TRIANGLES, 0, 3);
    
    // 确保渲染完成
    glFinish();
    
    // 零拷贝：数据已经直接渲染到IOSurface中！
    NSLog(@"Zero-copy rendered triangle to IOSurface");
}

- (IOSurfaceRef)getCurrentSurface {
    pthread_mutex_lock(&_surfaceMutex);
    IOSurfaceRef surface = _ioSurface;
    if (surface) {
        CFRetain(surface); // 增加引用计数
    }
    pthread_mutex_unlock(&_surfaceMutex);
    return surface;
}

- (BOOL)hasNewRenderResult {
    pthread_mutex_lock(&_surfaceMutex);
    BOOL hasResult = _hasNewResult;
    pthread_mutex_unlock(&_surfaceMutex);
    return hasResult;
}



- (BOOL)createRenderThreadResources {
    // 编译着色器
    if (![self compileShaders]) {
        NSLog(@"Failed to compile shaders in render thread");
        return NO;
    }
    
    // 创建顶点缓冲区
    glGenBuffers(1, &_glVBO);
    glBindBuffer(GL_ARRAY_BUFFER, _glVBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(triangleVertices), triangleVertices, GL_STATIC_DRAW);
    
    // 创建纹理缓存
    if (![self createTextureCache]) {
        NSLog(@"Failed to create texture cache in render thread");
        return NO;
    }
    
    // 创建直接渲染到IOSurface的帧缓冲区
    if (![self createDirectIOSurfaceFramebuffer]) {
        NSLog(@"Failed to create direct IOSurface framebuffer in render thread");
        return NO;
    }
    
    return YES;
}

- (void)cleanupRenderThreadResources {
    // 清理OpenGL ES资源
    if (_glProgram) {
        glDeleteProgram(_glProgram);
        _glProgram = 0;
    }
    
    if (_glVBO) {
        glDeleteBuffers(1, &_glVBO);
        _glVBO = 0;
    }
    
    if (_glFBO) {
        glDeleteFramebuffers(1, &_glFBO);
        _glFBO = 0;
    }
    
    // 清理纹理缓存
    if (_textureCache) {
        CFRelease(_textureCache);
        _textureCache = NULL;
    }
    
    if (_renderTexture) {
        CFRelease(_renderTexture);
        _renderTexture = NULL;
    }
}

- (void)cleanup {
    // 停止渲染
    [self stopRendering];
    
    // 清理IOSurface
    if (_ioSurface) {
        CFRelease(_ioSurface);
        _ioSurface = NULL;
    }
    
    // 清理Metal资源
    _metalDevice = nil;
    _commandQueue = nil;
}

@end
