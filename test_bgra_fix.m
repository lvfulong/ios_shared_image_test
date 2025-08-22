#import <Foundation/Foundation.h>
#import <IOSurface/IOSurfaceRef.h>
#import <CoreVideo/CoreVideo.h>
#import <OpenGLES/ES2/gl.h>

// 测试BGRA兼容性修复
void testBGRACompatibility() {
    NSLog(@"=== iOS BGRA兼容性测试 ===");
    
    // 测试1: 检查OpenGL ES扩展支持
    NSLog(@"\n--- 测试1: OpenGL ES扩展支持 ---");
    const char* extensions = (const char*)glGetString(GL_EXTENSIONS);
    if (extensions) {
        BOOL supportsBGRA = strstr(extensions, "GL_EXT_bgra") != NULL;
        BOOL supportsBGRA8 = strstr(extensions, "GL_EXT_bgra8") != NULL;
        BOOL supportsBGRA8888 = strstr(extensions, "GL_EXT_bgra8888") != NULL;
        
        NSLog(@"GL_EXT_bgra support: %@", supportsBGRA ? @"YES" : @"NO");
        NSLog(@"GL_EXT_bgra8 support: %@", supportsBGRA8 ? @"YES" : @"NO");
        NSLog(@"GL_EXT_bgra8888 support: %@", supportsBGRA8888 ? @"YES" : @"NO");
        
        if (!supportsBGRA && !supportsBGRA8 && !supportsBGRA8888) {
            NSLog(@"⚠️ iOS不支持BGRA扩展，需要使用RGBA格式");
        }
    } else {
        NSLog(@"❌ 无法获取OpenGL ES扩展信息");
    }
    
    // 测试2: 创建不同格式的IOSurface
    NSLog(@"\n--- 测试2: IOSurface格式测试 ---");
    
    // RGBA格式
    NSDictionary* rgbaProperties = @{
        (NSString*)kIOSurfaceWidth: @256,
        (NSString*)kIOSurfaceHeight: @256,
        (NSString*)kIOSurfaceBytesPerElement: @4,
        (NSString*)kIOSurfaceBytesPerRow: @(256 * 4),
        (NSString*)kIOSurfacePixelFormat: @(kCVPixelFormatType_32RGBA)
    };
    
    IOSurfaceRef rgbaSurface = IOSurfaceCreate((__bridge CFDictionaryRef)rgbaProperties);
    if (rgbaSurface) {
        OSType format = IOSurfaceGetPixelFormat(rgbaSurface);
        NSLog(@"RGBA IOSurface created successfully: format %u", (unsigned int)format);
        CFRelease(rgbaSurface);
    } else {
        NSLog(@"❌ Failed to create RGBA IOSurface");
    }
    
    // BGRA格式 (可能在某些设备上失败)
    NSDictionary* bgraProperties = @{
        (NSString*)kIOSurfaceWidth: @256,
        (NSString*)kIOSurfaceHeight: @256,
        (NSString*)kIOSurfaceBytesPerElement: @4,
        (NSString*)kIOSurfaceBytesPerRow: @(256 * 4),
        (NSString*)kIOSurfacePixelFormat: @(kCVPixelFormatType_32BGRA)
    };
    
    IOSurfaceRef bgraSurface = IOSurfaceCreate((__bridge CFDictionaryRef)bgraProperties);
    if (bgraSurface) {
        OSType format = IOSurfaceGetPixelFormat(bgraSurface);
        NSLog(@"BGRA IOSurface created successfully: format %u", (unsigned int)format);
        CFRelease(bgraSurface);
    } else {
        NSLog(@"⚠️ Failed to create BGRA IOSurface (not supported on this device)");
    }
    
    // 测试3: CVOpenGLESTextureCache兼容性
    NSLog(@"\n--- 测试3: CVOpenGLESTextureCache兼容性 ---");
    NSLog(@"CVOpenGLESTextureCache在iOS上通常只支持RGBA格式");
    NSLog(@"BGRA格式需要使用RGBA格式并处理颜色通道转换");
    
    NSLog(@"\n=== 修复建议 ===");
    NSLog(@"1. 使用RGBA格式创建IOSurface");
    NSLog(@"2. 在CVOpenGLESTextureCache中使用GL_RGBA格式");
    NSLog(@"3. 如果需要BGRA，在着色器中处理颜色通道转换");
    NSLog(@"4. 添加扩展检查和fallback机制");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        testBGRACompatibility();
    }
    return 0;
}
