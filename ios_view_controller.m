#import "ios_view_controller.h"
#import <IOSurface/IOSurfaceRef.h>
#import <QuartzCore/CADisplayLink.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/EAGLDrawable.h>
#import <CoreVideo/CoreVideo.h>

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
    
    // 设置视图背景色
    self.view.backgroundColor = [UIColor blackColor];
    
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
    // 创建IOSurface属性
    NSDictionary* surfaceProperties = @{
        (NSString*)kIOSurfaceWidth: @512,
        (NSString*)kIOSurfaceHeight: @512,
        (NSString*)kIOSurfaceBytesPerElement: @4,
        (NSString*)kIOSurfaceBytesPerRow: @(512 * 4),
        (NSString*)kIOSurfacePixelFormat: @(kCVPixelFormatType_32RGBA) // 使用RGBA格式，与OpenGL ES兼容
    };
    
    // 创建IOSurface
    _ioSurface = IOSurfaceCreate((__bridge CFDictionaryRef)surfaceProperties);
    if (!_ioSurface) {
        NSLog(@"Failed to create IOSurface");
        return NO;
    }
    
    NSLog(@"Successfully created IOSurface for rendering with format: %u", (unsigned int)IOSurfaceGetPixelFormat(_ioSurface));
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
        // 获取当前的IOSurface
        IOSurfaceRef surface = [_mainRenderer getCurrentSurface];
        if (surface) {
            // 设置显示上下文为当前上下文
            [EAGLContext setCurrentContext:_displayContext];
            
            // 绑定显示帧缓冲区
            glBindFramebuffer(GL_FRAMEBUFFER, _displayFramebuffer);
            
            // 设置视口
            glViewport(0, 0, (GLsizei)_eaglLayer.bounds.size.width, (GLsizei)_eaglLayer.bounds.size.height);
            
            // 清除背景
            glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
            glClear(GL_COLOR_BUFFER_BIT);
            
            // 从IOSurface创建纹理
            CVOpenGLESTextureRef textureRef = NULL;
            CVReturn result = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
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
                // 获取纹理名称
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
                
                NSLog(@"Displayed IOSurface content to screen");
            } else {
                NSLog(@"Failed to create display texture from IOSurface: %d", result);
            }
            
            // 释放IOSurface引用
            CFRelease(surface);
        }
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
    
    // 绘制四边形
    glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_SHORT, 0);
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
