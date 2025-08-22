#import <Foundation/Foundation.h>
#import <IOSurface/IOSurfaceRef.h>

// 测试像素格式修复
void testPixelFormats() {
    NSLog(@"=== iOS 像素格式测试 ===");
    
    // 定义正确的像素格式常量
    const OSType kCVPixelFormatType_32RGBA = 1111970369;
    const OSType kCVPixelFormatType_32BGRA = 1380401729;
    
    NSLog(@"kCVPixelFormatType_32RGBA = %u", (unsigned int)kCVPixelFormatType_32RGBA);
    NSLog(@"kCVPixelFormatType_32BGRA = %u", (unsigned int)kCVPixelFormatType_32BGRA);
    
    // 测试RGBA格式IOSurface创建
    NSLog(@"\n--- 测试RGBA格式IOSurface ---");
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
        NSLog(@"✅ RGBA IOSurface created successfully: format %u (%@)", 
              (unsigned int)format,
              format == kCVPixelFormatType_32RGBA ? @"RGBA" : 
              format == kCVPixelFormatType_32BGRA ? @"BGRA" : @"Unknown");
        CFRelease(rgbaSurface);
    } else {
        NSLog(@"❌ Failed to create RGBA IOSurface");
    }
    
    // 测试BGRA格式IOSurface创建
    NSLog(@"\n--- 测试BGRA格式IOSurface ---");
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
        NSLog(@"✅ BGRA IOSurface created successfully: format %u (%@)", 
              (unsigned int)format,
              format == kCVPixelFormatType_32RGBA ? @"RGBA" : 
              format == kCVPixelFormatType_32BGRA ? @"BGRA" : @"Unknown");
        CFRelease(bgraSurface);
    } else {
        NSLog(@"❌ Failed to create BGRA IOSurface");
    }
    
    NSLog(@"\n=== 修复总结 ===");
    NSLog(@"1. 使用正确的像素格式常量");
    NSLog(@"2. RGBA格式: %u", (unsigned int)kCVPixelFormatType_32RGBA);
    NSLog(@"3. BGRA格式: %u", (unsigned int)kCVPixelFormatType_32BGRA);
    NSLog(@"4. 确保IOSurface创建使用RGBA格式");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        testPixelFormats();
    }
    return 0;
}
