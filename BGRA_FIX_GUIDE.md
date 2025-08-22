# iOS BGRA兼容性修复指南

## 问题分析

iOS上的`CVOpenGLESTextureCache`失败错误`-6661`通常是由于以下原因：

1. **BGRA格式不支持**：iOS的OpenGL ES实现通常不支持`GL_BGRA_EXT`格式
2. **像素格式不匹配**：IOSurface的像素格式与OpenGL ES纹理格式不兼容
3. **扩展缺失**：设备不支持必要的OpenGL ES扩展

## 修复方案

### 方案1: 使用RGBA格式 (推荐)

```objc
// 创建IOSurface时使用RGBA格式
NSDictionary* surfaceProperties = @{
    (NSString*)kIOSurfaceWidth: @512,
    (NSString*)kIOSurfaceHeight: @512,
    (NSString*)kIOSurfaceBytesPerElement: @4,
    (NSString*)kIOSurfaceBytesPerRow: @(512 * 4),
    (NSString*)kIOSurfacePixelFormat: @(kCVPixelFormatType_32RGBA) // 使用RGBA
};

// CVOpenGLESTextureCache使用GL_RGBA格式
CVOpenGLESTextureCacheCreateTextureFromImage(
    kCFAllocatorDefault,
    textureCache,
    surface,
    NULL,
    GL_TEXTURE_2D,
    GL_RGBA,  // 使用GL_RGBA而不是GL_BGRA_EXT
    width, height,
    GL_RGBA,
    GL_UNSIGNED_BYTE,
    0,
    &textureRef
);
```

### 方案2: 扩展检查和Fallback

```objc
- (BOOL)displayUsingCVOpenGLESTextureCache:(IOSurfaceRef)surface pixelFormat:(OSType)pixelFormat {
    // 检查BGRA扩展支持
    const char* extensions = (const char*)glGetString(GL_EXTENSIONS);
    BOOL supportsBGRA = extensions && strstr(extensions, "GL_EXT_bgra") != NULL;
    
    GLenum glFormat = GL_RGBA; // 默认使用RGBA
    
    if (pixelFormat == kCVPixelFormatType_32BGRA) {
        if (supportsBGRA) {
            glFormat = GL_BGRA_EXT;
        } else {
            // 不支持BGRA，使用RGBA并处理颜色转换
            glFormat = GL_RGBA;
        }
    }
    
    // 尝试创建纹理
    CVReturn result = CVOpenGLESTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault, textureCache, surface, NULL,
        GL_TEXTURE_2D, glFormat, width, height, glFormat, GL_UNSIGNED_BYTE, 0, &textureRef
    );
    
    if (result != kCVReturnSuccess && glFormat == GL_BGRA_EXT) {
        // BGRA失败，尝试RGBA
        NSLog(@"BGRA failed, retrying with RGBA");
        result = CVOpenGLESTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, surface, NULL,
            GL_TEXTURE_2D, GL_RGBA, width, height, GL_RGBA, GL_UNSIGNED_BYTE, 0, &textureRef
        );
    }
    
    return result == kCVReturnSuccess;
}
```

### 方案3: 着色器颜色转换

如果必须使用BGRA格式，可以在着色器中处理颜色通道转换：

```glsl
// 顶点着色器
attribute vec4 position;
attribute vec2 texCoord;
varying vec2 v_texCoord;

void main() {
    gl_Position = position;
    v_texCoord = texCoord;
}

// 片段着色器 - BGRA到RGBA转换
precision mediump float;
varying vec2 v_texCoord;
uniform sampler2D texture;

void main() {
    vec4 color = texture2D(texture, v_texCoord);
    // BGRA到RGBA转换: BGR -> RGB
    gl_FragColor = vec4(color.bgr, color.a);
}
```

## 完整的修复实现

### 1. 修改IOSurface创建

```objc
- (BOOL)createIOSurface {
    // 使用RGBA格式避免兼容性问题
    NSDictionary* surfaceProperties = @{
        (NSString*)kIOSurfaceWidth: @512,
        (NSString*)kIOSurfaceHeight: @512,
        (NSString*)kIOSurfaceBytesPerElement: @4,
        (NSString*)kIOSurfaceBytesPerRow: @(512 * 4),
        (NSString*)kIOSurfacePixelFormat: @(kCVPixelFormatType_32RGBA)
    };
    
    _ioSurface = IOSurfaceCreate((__bridge CFDictionaryRef)surfaceProperties);
    if (!_ioSurface) {
        NSLog(@"Failed to create IOSurface");
        return NO;
    }
    
    OSType pixelFormat = IOSurfaceGetPixelFormat(_ioSurface);
    NSLog(@"Created IOSurface with format: %u (%@)", 
          (unsigned int)pixelFormat,
          pixelFormat == kCVPixelFormatType_32RGBA ? @"RGBA" : @"Unknown");
    return YES;
}
```

### 2. 改进CVOpenGLESTextureCache实现

```objc
- (BOOL)displayUsingCVOpenGLESTextureCache:(IOSurfaceRef)surface pixelFormat:(OSType)pixelFormat {
    // 检查扩展支持
    const char* extensions = (const char*)glGetString(GL_EXTENSIONS);
    BOOL supportsBGRA = extensions && strstr(extensions, "GL_EXT_bgra") != NULL;
    
    // 根据像素格式和扩展支持选择格式
    GLenum glFormat = GL_RGBA;
    if (pixelFormat == kCVPixelFormatType_32BGRA && supportsBGRA) {
        glFormat = GL_BGRA_EXT;
    }
    
    // 尝试创建纹理
    CVOpenGLESTextureRef textureRef = NULL;
    CVReturn result = CVOpenGLESTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault, _displayTextureCache, surface, NULL,
        GL_TEXTURE_2D, glFormat, width, height, glFormat, GL_UNSIGNED_BYTE, 0, &textureRef
    );
    
    // 如果失败且使用了BGRA，尝试RGBA
    if (result != kCVReturnSuccess && glFormat == GL_BGRA_EXT) {
        NSLog(@"BGRA failed, retrying with RGBA");
        result = CVOpenGLESTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, _displayTextureCache, surface, NULL,
            GL_TEXTURE_2D, GL_RGBA, width, height, GL_RGBA, GL_UNSIGNED_BYTE, 0, &textureRef
        );
    }
    
    if (result == kCVReturnSuccess) {
        // 成功创建纹理，进行渲染
        GLuint textureName = CVOpenGLESTextureGetName(textureRef);
        glBindTexture(GL_TEXTURE_2D, textureName);
        
        // 设置纹理参数
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        // 渲染
        [self drawFullscreenQuad];
        [_displayContext presentRenderbuffer:GL_RENDERBUFFER];
        
        CFRelease(textureRef);
        return YES;
    }
    
    NSLog(@"CVOpenGLESTextureCache failed: %d", result);
    return NO;
}
```

## 测试和验证

### 1. 检查扩展支持

```objc
void checkExtensions() {
    const char* extensions = (const char*)glGetString(GL_EXTENSIONS);
    if (extensions) {
        NSLog(@"Supported extensions: %s", extensions);
        
        // 检查BGRA相关扩展
        BOOL supportsBGRA = strstr(extensions, "GL_EXT_bgra") != NULL;
        BOOL supportsBGRA8 = strstr(extensions, "GL_EXT_bgra8") != NULL;
        
        NSLog(@"BGRA support: %@", supportsBGRA ? @"YES" : @"NO");
        NSLog(@"BGRA8 support: %@", supportsBGRA8 ? @"YES" : @"NO");
    }
}
```

### 2. 测试不同格式

```objc
void testFormats() {
    // 测试RGBA格式
    NSDictionary* rgbaProps = @{
        (NSString*)kIOSurfacePixelFormat: @(kCVPixelFormatType_32RGBA)
    };
    
    // 测试BGRA格式
    NSDictionary* bgraProps = @{
        (NSString*)kIOSurfacePixelFormat: @(kCVPixelFormatType_32BGRA)
    };
    
    // 创建并测试
    IOSurfaceRef rgbaSurface = IOSurfaceCreate((__bridge CFDictionaryRef)rgbaProps);
    IOSurfaceRef bgraSurface = IOSurfaceCreate((__bridge CFDictionaryRef)bgraProps);
    
    if (rgbaSurface) {
        NSLog(@"RGBA format supported");
        CFRelease(rgbaSurface);
    }
    
    if (bgraSurface) {
        NSLog(@"BGRA format supported");
        CFRelease(bgraSurface);
    } else {
        NSLog(@"BGRA format not supported");
    }
}
```

## 总结

**推荐解决方案**：

1. **使用RGBA格式**：避免BGRA兼容性问题
2. **添加扩展检查**：动态检测BGRA支持
3. **实现Fallback机制**：BGRA失败时自动切换到RGBA
4. **着色器转换**：必要时在着色器中处理颜色通道转换

这样可以确保在所有iOS设备上都能正常工作，同时保持零拷贝的性能优势。
