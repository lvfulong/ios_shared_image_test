#import "ios_renderer.h"
#import <OpenGLES/EAGL.h>
#import <OpenGLES/EAGLDrawable.h>

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
    // 确保在主线程中初始化
    if (![NSThread isMainThread]) {
        __block BOOL result = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            result = [self initialize];
        });
        return result;
    }
    
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
    
    // 初始化OpenGL ES上下文
    if (![self initializeOpenGLES]) {
        NSLog(@"Failed to initialize OpenGL ES");
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
    // 创建IOSurface属性
    NSDictionary* surfaceProperties = @{
        (NSString*)kIOSurfaceWidth: @(_renderWidth),
        (NSString*)kIOSurfaceHeight: @(_renderHeight),
        (NSString*)kIOSurfaceBytesPerElement: @4,
        (NSString*)kIOSurfaceBytesPerRow: @(_renderWidth * 4),
        (NSString*)kIOSurfacePixelFormat: @(kCVPixelFormatType_32BGRA)
    };
    
    // 创建IOSurface
    _ioSurface = IOSurfaceCreate((__bridge CFDictionaryRef)surfaceProperties);
    if (!_ioSurface) {
        NSLog(@"Failed to create IOSurface");
        return NO;
    }
    
    return YES;
}

- (BOOL)initializeOpenGLES {
    // 确保在主线程中创建EAGL上下文
    if (![NSThread isMainThread]) {
        NSLog(@"OpenGL ES context must be created on main thread");
        return NO;
    }
    
    // 创建EAGL上下文
    _glContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (!_glContext) {
        NSLog(@"Failed to create EAGL context");
        return NO;
    }
    
    // 设置当前上下文
    if (![EAGLContext setCurrentContext:_glContext]) {
        NSLog(@"Failed to set current EAGL context");
        return NO;
    }
    
    // 编译着色器
    if (![self compileShaders]) {
        NSLog(@"Failed to compile shaders");
        return NO;
    }
    
    // 创建顶点缓冲区
    glGenBuffers(1, &_glVBO);
    glBindBuffer(GL_ARRAY_BUFFER, _glVBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(triangleVertices), triangleVertices, GL_STATIC_DRAW);
    
    // 创建Core Video纹理缓存
    if (![self createTextureCache]) {
        NSLog(@"Failed to create texture cache");
        return NO;
    }
    
    // 创建直接渲染到IOSurface的帧缓冲区
    if (![self createDirectIOSurfaceFramebuffer]) {
        NSLog(@"Failed to create direct IOSurface framebuffer");
        return NO;
    }
    
    return YES;
}

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
    // 创建Core Video纹理缓存
    CVReturn result = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault,
                                                   NULL,
                                                   _glContext,
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
    
    // 关键优化：使用Core Video纹理缓存直接从IOSurface创建OpenGL ES纹理
    CVReturn result = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                   _textureCache,
                                                                   _ioSurface,
                                                                   NULL,
                                                                   GL_TEXTURE_2D,
                                                                   GL_RGBA,
                                                                   (GLsizei)_renderWidth,
                                                                   (GLsizei)_renderHeight,
                                                                   GL_BGRA,
                                                                   GL_UNSIGNED_BYTE,
                                                                   0,
                                                                   &_renderTexture);
    
    if (result != kCVReturnSuccess) {
        NSLog(@"Failed to create texture from IOSurface: %d", result);
        return NO;
    }
    
    // 获取OpenGL ES纹理名称
    GLuint textureName = CVOpenGLESTextureGetName(_renderTexture);
    
    // 将纹理附加到帧缓冲区
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, textureName, 0);
    
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"Framebuffer is not complete");
        return NO;
    }
    
    NSLog(@"Successfully created direct IOSurface framebuffer");
    return YES;
}

- (void)startRendering {
    if (_isRendering) return;
    
    _isRendering = YES;
    
    // 确保在主线程中创建共享上下文
    if ([NSThread isMainThread]) {
        [self startRenderThread];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self startRenderThread];
        });
    }
    
    NSLog(@"iOS direct rendering started");
}

- (void)startRenderThread {
    // 创建共享上下文
    EAGLContext* sharedContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2 
                                                       sharegroup:_glContext.sharegroup];
    if (!sharedContext) {
        NSLog(@"Failed to create shared EAGL context");
        return;
    }
    
    // 在后台线程中启动渲染
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [self renderLoopWithContext:sharedContext];
    });
}

- (void)stopRendering {
    _isRendering = NO;
    NSLog(@"iOS direct rendering stopped");
}

- (void)renderLoopWithContext:(EAGLContext*)context {
    // 确保在当前线程中设置EAGL上下文
    if (![EAGLContext setCurrentContext:context]) {
        NSLog(@"Failed to set current EAGL context in render thread");
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
    
    // 清理上下文
    [EAGLContext setCurrentContext:nil];
}

- (void)renderTriangle {
    // 绑定帧缓冲区
    glBindFramebuffer(GL_FRAMEBUFFER, _glFBO);
    
    // 设置视口
    glViewport(0, 0, (GLsizei)_renderWidth, (GLsizei)_renderHeight);
    
    // 清除颜色缓冲区
    glClearColor(0.2f, 0.3f, 0.3f, 1.0f);
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
    
    // 关键优化：数据已经直接渲染到IOSurface中，无需额外拷贝！
    // 这就是零拷贝渲染的核心优势
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

- (void)cleanup {
    // 停止渲染
    [self stopRendering];
    
    // 清理OpenGL ES资源
    if (_glContext) {
        [EAGLContext setCurrentContext:_glContext];
        
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
    }
    
    // 清理Core Video资源
    if (_renderTexture) {
        CFRelease(_renderTexture);
        _renderTexture = NULL;
    }
    
    if (_textureCache) {
        CVOpenGLESTextureCacheFlush(_textureCache, 0);
        CFRelease(_textureCache);
        _textureCache = NULL;
    }
    
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
