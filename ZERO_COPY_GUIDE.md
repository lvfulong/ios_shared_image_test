# iOS 零拷贝纹理创建方法指南

## 概述

在iOS上，有几种方式可以实现从IOSurface到纹理的零拷贝，类似于macOS的`CGLTexImageIOSurface2D`。本文档详细介绍了这些方法及其实现。

## 零拷贝方法对比

### 1. CVOpenGLESTextureCache (推荐)

**iOS标准方式，类似于macOS的CGLTexImageIOSurface2D**

```objc
// 创建纹理缓存
CVOpenGLESTextureCacheRef textureCache;
CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, eaglContext, NULL, &textureCache);

// 从IOSurface创建零拷贝纹理
CVOpenGLESTextureRef textureRef;
CVReturn result = CVOpenGLESTextureCacheCreateTextureFromImage(
    kCFAllocatorDefault,
    textureCache,
    iosurface,
    NULL,
    GL_TEXTURE_2D,
    GL_RGBA,
    width, height,
    GL_RGBA,
    GL_UNSIGNED_BYTE,
    0,
    &textureRef
);

if (result == kCVReturnSuccess) {
    GLuint textureName = CVOpenGLESTextureGetName(textureRef);
    // 使用textureName进行OpenGL ES操作
    CFRelease(textureRef);
}
```

**优点：**
- 标准API，兼容性好
- 真正的零拷贝
- iOS官方推荐方式

**缺点：**
- 需要Core Video支持

### 2. OpenGL ES扩展方式

**直接使用OpenGL ES API，传递NULL指针**

```objc
GLuint texture;
glGenTextures(1, &texture);
glBindTexture(GL_TEXTURE_2D, texture);

// 设置纹理参数
glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

// 关键：传递NULL作为像素数据指针，实现零拷贝
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 
             0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
```

**优点：**
- 直接使用OpenGL ES API
- 简单直接

**缺点：**
- 需要OpenGL ES实现支持IOSurface扩展
- 兼容性可能不如CVOpenGLESTextureCache

### 3. Metal纹理直接绑定 (最现代)

**使用Metal的零拷贝纹理创建**

```objc
// 创建Metal纹理描述符
MTLTextureDescriptor* descriptor = [MTLTextureDescriptor 
    texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                  width:width
                                 height:height
                              mipmapped:NO];
descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;

// 直接从IOSurface创建Metal纹理，零拷贝
id<MTLTexture> texture = [metalDevice newTextureWithDescriptor:descriptor
                                                     iosurface:iosurface
                                                         plane:0];
```

**优点：**
- 最现代的方式
- 性能最佳
- 真正的零拷贝

**缺点：**
- 需要Metal支持
- 需要Metal渲染管线
- 与OpenGL ES混合使用较复杂

### 4. 拷贝方式 (备用)

**传统的数据拷贝方法**

```objc
// 锁定IOSurface
IOSurfaceLock(iosurface, kIOSurfaceLockReadOnly, NULL);
void* pixelData = IOSurfaceGetBaseAddress(iosurface);

// 创建纹理并拷贝数据
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 
             0, GL_RGBA, GL_UNSIGNED_BYTE, pixelData);

// 解锁IOSurface
IOSurfaceUnlock(iosurface, kIOSurfaceLockReadOnly, NULL);
```

**优点：**
- 兼容性最好
- 总是能工作

**缺点：**
- 有数据拷贝开销
- 不是零拷贝

## 实现示例

### 在视图控制器中使用

```objc
// 设置零拷贝方式
typedef NS_ENUM(NSInteger, ZeroCopyMethod) {
    ZeroCopyMethodCVOpenGLESTextureCache = 0,  // 推荐
    ZeroCopyMethodOpenGLESExtension = 1,
    ZeroCopyMethodMetalTexture = 2,
    ZeroCopyMethodCopy = 3
};

@property (nonatomic, assign) ZeroCopyMethod zeroCopyMethod;

// 在viewDidLoad中设置
- (void)viewDidLoad {
    [super viewDidLoad];
    _zeroCopyMethod = ZeroCopyMethodCVOpenGLESTextureCache; // 推荐使用
}

// 根据选择的方式显示纹理
switch (_zeroCopyMethod) {
    case ZeroCopyMethodCVOpenGLESTextureCache:
        success = [self displayUsingCVOpenGLESTextureCache:surface pixelFormat:pixelFormat];
        break;
    case ZeroCopyMethodOpenGLESExtension:
        success = [self displayUsingOpenGLESExtension:surface pixelFormat:pixelFormat];
        break;
    case ZeroCopyMethodMetalTexture:
        success = [self displayUsingMetalTexture:surface pixelFormat:pixelFormat];
        break;
    case ZeroCopyMethodCopy:
        [self displayUsingCopyMethod:surface pixelFormat:pixelFormat];
        success = YES;
        break;
}
```

## 性能对比

| 方法 | 零拷贝 | 性能 | 兼容性 | 复杂度 |
|------|--------|------|--------|--------|
| CVOpenGLESTextureCache | ✅ | 高 | 高 | 中 |
| OpenGL ES扩展 | ✅ | 高 | 中 | 低 |
| Metal纹理绑定 | ✅ | 最高 | 中 | 高 |
| 拷贝方式 | ❌ | 低 | 最高 | 低 |

## 推荐使用策略

1. **首选：CVOpenGLESTextureCache**
   - 标准且高效
   - 兼容性好
   - 真正的零拷贝

2. **现代应用：Metal纹理绑定**
   - 如果使用Metal渲染管线
   - 性能最佳

3. **备用：OpenGL ES扩展**
   - 如果CVOpenGLESTextureCache不可用
   - 需要直接OpenGL ES控制

4. **最后备用：拷贝方式**
   - 确保总是能工作
   - 兼容性最好

## 注意事项

1. **像素格式匹配**：确保IOSurface的像素格式与OpenGL ES纹理格式匹配
2. **上下文管理**：确保在正确的OpenGL ES上下文中创建纹理
3. **资源清理**：及时释放CVOpenGLESTextureRef等资源
4. **错误处理**：实现适当的错误处理和备用方案

## 总结

iOS上虽然没有直接的`CGLTexImageIOSurface2D`等价物，但`CVOpenGLESTextureCache`提供了类似的功能，是iOS上实现零拷贝纹理创建的标准方式。对于现代应用，Metal纹理绑定提供了最佳性能，但需要相应的渲染管线支持。
