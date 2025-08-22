# iOS 像素格式修复总结

## 问题发现

通过日志分析发现了一个关键问题：

```
Successfully created IOSurface for rendering with format: 1380401729 (RGBA)
```

但是实际上：
- **1380401729 = kCVPixelFormatType_32BGRA** (BGRA格式)
- **1111970369 = kCVPixelFormatType_32RGBA** (RGBA格式)

## 问题原因

1. **错误的格式常量使用**：代码中使用了错误的像素格式常量
2. **格式识别错误**：日志中错误地将BGRA格式识别为RGBA
3. **CVOpenGLESTextureCache失败**：由于格式不匹配导致`-6661`错误

## 修复方案

### 1. 修正IOSurface创建

```objc
// 修复前 (错误)
(NSString*)kIOSurfacePixelFormat: @(kCVPixelFormatType_32RGBA)

// 修复后 (正确)
(NSString*)kIOSurfacePixelFormat: @(1111970369) // kCVPixelFormatType_32RGBA
```

### 2. 修正格式判断逻辑

```objc
// 修复前 (错误)
pixelFormat == kCVPixelFormatType_32RGBA ? @"RGBA" : 
pixelFormat == kCVPixelFormatType_32BGRA ? @"BGRA" : @"Unknown"

// 修复后 (正确)
pixelFormat == 1111970369 ? @"RGBA" : 
pixelFormat == 1380401729 ? @"BGRA" : @"Unknown"
```

### 3. 确保使用RGBA格式

```objc
// 创建IOSurface时使用RGBA格式
NSDictionary* surfaceProperties = @{
    (NSString*)kIOSurfaceWidth: @512,
    (NSString*)kIOSurfaceHeight: @512,
    (NSString*)kIOSurfaceBytesPerElement: @4,
    (NSString*)kIOSurfaceBytesPerRow: @(512 * 4),
    (NSString*)kIOSurfacePixelFormat: @(1111970369) // 确保使用RGBA格式
};
```

## 像素格式对照表

| 格式 | 常量值 | 描述 |
|------|--------|------|
| RGBA | 1111970369 | kCVPixelFormatType_32RGBA |
| BGRA | 1380401729 | kCVPixelFormatType_32BGRA |

## 修复效果

修复后应该看到：

```
Successfully created IOSurface for rendering with format: 1111970369 (RGBA)
CVOpenGLESTextureCache: Using GL_RGBA format for RGBA pixel format
CVOpenGLESTextureCache: Successfully displayed using zero-copy method
```

而不是：

```
Successfully created IOSurface for rendering with format: 1380401729 (RGBA) ❌
CVOpenGLESTextureCache: Failed with error -6661 ❌
```

## 关键修复点

1. **使用正确的像素格式常量**
2. **确保IOSurface创建使用RGBA格式**
3. **修正格式判断和日志输出**
4. **保持CVOpenGLESTextureCache的零拷贝优势**

## 验证方法

运行修复后的程序，应该看到：
- ✅ IOSurface格式为1111970369 (RGBA)
- ✅ CVOpenGLESTextureCache成功创建纹理
- ✅ 零拷贝渲染正常工作
- ✅ 不再出现-6661错误
