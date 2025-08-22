#import <Foundation/Foundation.h>
#import <IOSurface/IOSurfaceRef.h>
#import <CoreVideo/CoreVideo.h>
#import <OpenGLES/ES2/gl.h>
#import <Metal/Metal.h>

// 测试不同的零拷贝方式
void testZeroCopyMethods() {
    NSLog(@"=== iOS 零拷贝纹理创建方法测试 ===");
    
    // 创建测试用的IOSurface
    NSDictionary* surfaceProperties = @{
        (NSString*)kIOSurfaceWidth: @512,
        (NSString*)kIOSurfaceHeight: @512,
        (NSString*)kIOSurfaceBytesPerElement: @4,
        (NSString*)kIOSurfaceBytesPerRow: @(512 * 4),
        (NSString*)kIOSurfacePixelFormat: @(kCVPixelFormatType_32RGBA)
    };
    
    IOSurfaceRef surface = IOSurfaceCreate((__bridge CFDictionaryRef)surfaceProperties);
    if (!surface) {
        NSLog(@"Failed to create test IOSurface");
        return;
    }
    
    NSLog(@"Created test IOSurface: %zux%zu, format: %u", 
          IOSurfaceGetWidth(surface), 
          IOSurfaceGetHeight(surface),
          (unsigned int)IOSurfaceGetPixelFormat(surface));
    
    // 方法1: CVOpenGLESTextureCache (iOS标准方式)
    NSLog(@"\n--- 方法1: CVOpenGLESTextureCache ---");
    NSLog(@"这是iOS上最标准的零拷贝方式，类似于macOS的CGLTexImageIOSurface2D");
    NSLog(@"使用CVOpenGLESTextureCacheCreateTextureFromImage直接从IOSurface创建OpenGL ES纹理");
    NSLog(@"优点：标准API，兼容性好，真正的零拷贝");
    NSLog(@"缺点：需要Core Video支持");
    
    // 方法2: OpenGL ES扩展
    NSLog(@"\n--- 方法2: OpenGL ES扩展 ---");
    NSLog(@"使用glTexImage2D但传递NULL作为像素数据指针");
    NSLog(@"优点：直接使用OpenGL ES API");
    NSLog(@"缺点：需要OpenGL ES实现支持IOSurface扩展");
    
    // 方法3: Metal纹理直接绑定
    NSLog(@"\n--- 方法3: Metal纹理直接绑定 ---");
    NSLog(@"使用newTextureWithDescriptor:iosurface:plane:直接从IOSurface创建Metal纹理");
    NSLog(@"优点：最现代的方式，性能最佳，真正的零拷贝");
    NSLog(@"缺点：需要Metal支持，需要Metal渲染管线");
    
    // 方法4: 拷贝方式
    NSLog(@"\n--- 方法4: 拷贝方式 (备用) ---");
    NSLog(@"使用IOSurfaceLock和glTexImage2D进行数据拷贝");
    NSLog(@"优点：兼容性最好，总是能工作");
    NSLog(@"缺点：有数据拷贝开销");
    
    NSLog(@"\n=== 推荐使用顺序 ===");
    NSLog(@"1. CVOpenGLESTextureCache (最推荐，标准且高效)");
    NSLog(@"2. Metal纹理直接绑定 (如果使用Metal渲染管线)");
    NSLog(@"3. OpenGL ES扩展 (如果支持)");
    NSLog(@"4. 拷贝方式 (作为最后的备用方案)");
    
    // 清理
    CFRelease(surface);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        testZeroCopyMethods();
    }
    return 0;
}
