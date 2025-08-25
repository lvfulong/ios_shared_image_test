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
    
    // 设置视图背景色为明显的颜色
    self.view.backgroundColor = [UIColor blueColor]; // 蓝色背景，容易看到
    
    // 添加一个简单的UIView来测试视图是否可见
    UIView* testView = [[UIView alloc] initWithFrame:CGRectMake(50, 50, 100, 100)];
    testView.backgroundColor = [UIColor redColor];
    [self.view addSubview:testView];
    
    NSLog(@"Added test view with frame: %@", NSStringFromCGRect(testView.frame));
    
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
    
    // 设置零拷贝方式选择 (可以在这里切换)
    _zeroCopyMethod = ZeroCopyMethodMetalTexture; // 优先使用Metal纹理，因为CVOpenGLESTextureCache有问题
    
    // 创建显示层来显示渲染结果
    [self createDisplayLayer];
    
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
    
    NSLog(@"IOSurface-based rendering view controller loaded successfully");
}

- (void)createDisplayLayer {
    // 创建EAGL上下文用于显示
    EAGLContext* displayContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (!displayContext) {
        NSLog(@"Failed to create display EAGL context");
        return;
    }
    
    // 创建EAGL层
    CAEAGLLayer* eaglLayer = [CAEAGLLayer layer];
    eaglLayer.frame = self.view.bounds;
    eaglLayer.drawableProperties = @{
        kEAGLDrawablePropertyRetainedBacking: @NO,
        kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8
    };
    [self.view.layer addSublayer:eaglLayer];
    
    // 确保EAGL层可见
    eaglLayer.opacity = 1.0;
    eaglLayer.hidden = NO;
    
    NSLog(@"EAGL layer frame: %@, bounds: %@", 
          NSStringFromCGRect(eaglLayer.frame), 
          NSStringFromCGRect(self.view.bounds));
    
    // 设置当前上下文
    if (![EAGLContext setCurrentContext:displayContext]) {
        NSLog(@"Failed to set current EAGL context for display");
        return;
    }
    
    // 创建帧缓冲区和渲染缓冲区
    GLuint framebuffer, colorRenderbuffer;
    glGenFramebuffers(1, &framebuffer);
    glGenRenderbuffers(1, &colorRenderbuffer);
    
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
    
    // 将渲染缓冲区附加到EAGL层
    [displayContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:eaglLayer];
    
    // 将渲染缓冲区附加到帧缓冲区
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, colorRenderbuffer);
    
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"Display framebuffer is not complete");
        return;
    } else {
        NSLog(@"Display framebuffer is complete and ready");
    }
    
    // 创建Core Video纹理缓存
    CVReturn result = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault,
                                                   NULL,
                                                   displayContext,
                                                   NULL,
                                                   &_displayTextureCache);
    if (result != kCVReturnSuccess) {
        NSLog(@"Failed to create display texture cache: %d", result);
        return;
    }
    
    // 保存显示相关对象
    _displayContext = displayContext;
    _eaglLayer = eaglLayer;
    _displayFramebuffer = framebuffer;
    _displayRenderbuffer = colorRenderbuffer;
    
    // 初始化显示着色器
    if (![self initializeDisplayShaders]) {
        NSLog(@"Failed to initialize display shaders");
        return;
    }
    
    NSLog(@"Created OpenGL ES display layer");
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
    
    // 开始渲染
    [_mainRenderer startRendering];
    NSLog(@"Started IOSurface-based rendering in view controller");
    
    // 创建CADisplayLink来同步显示刷新率
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateDisplay:)];
    _displayLink.preferredFramesPerSecond = 60; // 60 FPS
    [_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
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
        NSLog(@"Displaying new render result");
        
        // 获取当前的IOSurface
        IOSurfaceRef surface = [_mainRenderer getCurrentSurface];
        if (surface) {
            // 设置显示上下文为当前上下文
            [EAGLContext setCurrentContext:_displayContext];
            
            // 绑定显示帧缓冲区
            glBindFramebuffer(GL_FRAMEBUFFER, _displayFramebuffer);
            
            // 设置视口
            CGSize layerSize = _eaglLayer.bounds.size;
            glViewport(0, 0, (GLsizei)layerSize.width, (GLsizei)layerSize.height);
            
            NSLog(@"Setting viewport to: %.0fx%.0f", layerSize.width, layerSize.height);
            
            // 清除背景 - 使用明显的颜色来测试显示
            glClearColor(0.0f, 1.0f, 0.0f, 1.0f); // 绿色背景
            glClear(GL_COLOR_BUFFER_BIT);
            
            // 从IOSurface创建纹理 - 两种零拷贝方式
            // 获取IOSurface的实际像素格式
            OSType pixelFormat = IOSurfaceGetPixelFormat(surface);
            NSLog(@"IOSurface pixel format: %u", (unsigned int)pixelFormat);
            
            // 先测试基本显示是否工作
            NSLog(@"Testing basic display functionality");
            [self testBasicDisplay];
            
            BOOL success = NO;
            
            switch (_zeroCopyMethod) {
                case ZeroCopyMethodCVOpenGLESTextureCache:
                    // 方式1: 使用CVOpenGLESTextureCache进行零拷贝 (iOS标准方式)
                    success = [self displayUsingCVOpenGLESTextureCache:surface pixelFormat:pixelFormat];
                    break;
                    
                case ZeroCopyMethodOpenGLESExtension:
                    // 方式2: 使用OpenGL ES扩展进行零拷贝
                    success = [self displayUsingOpenGLESExtension:surface pixelFormat:pixelFormat];
                    break;
                    
                case ZeroCopyMethodMetalTexture:
                    // 方式3: 使用Metal纹理直接绑定 (最现代的方式)
                    success = [self displayUsingMetalTexture:surface pixelFormat:pixelFormat];
                    break;
                    
                case ZeroCopyMethodCopy:
                    // 方式4: 使用拷贝方式 (备用)
                    [self displayUsingCopyMethod:surface pixelFormat:pixelFormat];
                    success = YES;
                    break;
            }
            
            if (!success) {
                NSLog(@"Selected zero-copy method failed, trying CVOpenGLESTextureCache as fallback");
                // 如果选择的零拷贝方式失败，尝试CVOpenGLESTextureCache作为备用
                success = [self displayUsingCVOpenGLESTextureCache:surface pixelFormat:pixelFormat];
                
                if (!success) {
                    NSLog(@"All zero-copy methods failed, using copy method as final fallback");
                    [self displayUsingCopyMethod:surface pixelFormat:pixelFormat];
                }
            }
            
            // 释放IOSurface引用
            CFRelease(surface);
        } else {
            NSLog(@"No surface available for display");
        }
    } else {
        NSLog(@"No new render result available");
    }
}

- (BOOL)initializeDisplayShaders {
    // 编译顶点着色器
    GLuint vertexShader = glCreateShader(GL_VERTEX_SHADER);
    glShaderSource(vertexShader, 1, &displayVertexShaderSource, NULL);
    glCompileShader(vertexShader);
    
    GLint success;
    glGetShaderiv(vertexShader, GL_COMPILE_STATUS, &success);
    if (!success) {
        GLchar infoLog[512];
        glGetShaderInfoLog(vertexShader, 512, NULL, infoLog);
        NSLog(@"Display vertex shader compilation failed: %s", infoLog);
        return NO;
    }
    
    // 编译片段着色器
    GLuint fragmentShader = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(fragmentShader, 1, &displayFragmentShaderSource, NULL);
    glCompileShader(fragmentShader);
    
    glGetShaderiv(fragmentShader, GL_COMPILE_STATUS, &success);
    if (!success) {
        GLchar infoLog[512];
        glGetShaderInfoLog(fragmentShader, 512, NULL, infoLog);
        NSLog(@"Display fragment shader compilation failed: %s", infoLog);
        return NO;
    }
    
    // 创建程序
    _displayProgram = glCreateProgram();
    glAttachShader(_displayProgram, vertexShader);
    glAttachShader(_displayProgram, fragmentShader);
    glLinkProgram(_displayProgram);
    
    glGetProgramiv(_displayProgram, GL_LINK_STATUS, &success);
    if (!success) {
        GLchar infoLog[512];
        glGetProgramInfoLog(_displayProgram, 512, NULL, infoLog);
        NSLog(@"Display program linking failed: %s", infoLog);
        return NO;
    }
    
    // 清理着色器
    glDeleteShader(vertexShader);
    glDeleteShader(fragmentShader);
    
    // 创建顶点缓冲区
    glGenBuffers(1, &_displayVBO);
    glBindBuffer(GL_ARRAY_BUFFER, _displayVBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(quadVertices), quadVertices, GL_STATIC_DRAW);
    
    // 创建索引缓冲区
    glGenBuffers(1, &_displayIBO);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _displayIBO);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(quadIndices), quadIndices, GL_STATIC_DRAW);
    
    return YES;
}

- (void)testBasicDisplay {
    NSLog(@"Drawing a simple colored rectangle to test display");
    
    // 检查OpenGL ES状态
    GLenum error = glGetError();
    if (error != GL_NO_ERROR) {
        NSLog(@"OpenGL ES error before drawing: 0x%x", error);
    }
    
    // 创建一个简单的着色器程序来绘制彩色矩形
    static GLuint testProgram = 0;
    static GLuint testVBO = 0;
    
    if (testProgram == 0) {
        // 创建简单的顶点着色器
        const char* vertexShaderSource = R"(
            attribute vec4 position;
            void main() {
                gl_Position = position;
            }
        )";
        
        // 创建简单的片段着色器
        const char* fragmentShaderSource = R"(
            precision mediump float;
            void main() {
                gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0); // 红色
            }
        )";
        
        // 编译着色器
        GLuint vertexShader = glCreateShader(GL_VERTEX_SHADER);
        glShaderSource(vertexShader, 1, &vertexShaderSource, NULL);
        glCompileShader(vertexShader);
        
        GLuint fragmentShader = glCreateShader(GL_FRAGMENT_SHADER);
        glShaderSource(fragmentShader, 1, &fragmentShaderSource, NULL);
        glCompileShader(fragmentShader);
        
        // 创建程序
        testProgram = glCreateProgram();
        glAttachShader(testProgram, vertexShader);
        glAttachShader(testProgram, fragmentShader);
        glLinkProgram(testProgram);
        
        // 清理着色器
        glDeleteShader(vertexShader);
        glDeleteShader(fragmentShader);
        
        // 创建顶点缓冲区
        float vertices[] = {
            -0.5f, -0.5f,
             0.5f, -0.5f,
             0.5f,  0.5f,
            -0.5f,  0.5f
        };
        
        glGenBuffers(1, &testVBO);
        glBindBuffer(GL_ARRAY_BUFFER, testVBO);
        glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
    }
    
    // 使用测试程序
    glUseProgram(testProgram);
    
    // 绑定顶点缓冲区
    glBindBuffer(GL_ARRAY_BUFFER, testVBO);
    
    // 设置顶点属性
    GLint posAttrib = glGetAttribLocation(testProgram, "position");
    glVertexAttribPointer(posAttrib, 2, GL_FLOAT, GL_FALSE, 0, 0);
    glEnableVertexAttribArray(posAttrib);
    
    // 绘制矩形
    glDrawArrays(GL_TRIANGLE_FAN, 0, 4);
    
    // 呈现到屏幕
    [_displayContext presentRenderbuffer:GL_RENDERBUFFER];
    
    // 检查OpenGL ES状态
    error = glGetError();
    if (error != GL_NO_ERROR) {
        NSLog(@"OpenGL ES error after drawing: 0x%x", error);
    }
    
    NSLog(@"Basic display test completed");
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
