#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

// 分析CVOpenGLESTextureCache错误
void analyzeCVOpenGLESTextureCacheError() {
    NSLog(@"=== CVOpenGLESTextureCache 错误分析 ===");
    
    // 常见的CVReturn错误码
    NSLog(@"常见CVReturn错误码:");
    NSLog(@"kCVReturnSuccess = %d", kCVReturnSuccess);
    NSLog(@"kCVReturnError = %d", kCVReturnError);
    NSLog(@"kCVReturnInvalidArgument = %d", kCVReturnInvalidArgument);
    NSLog(@"kCVReturnAllocationFailed = %d", kCVReturnAllocationFailed);
    NSLog(@"kCVReturnUnsupported = %d", kCVReturnUnsupported);
    NSLog(@"kCVReturnInvalidDisplay = %d", kCVReturnInvalidDisplay);
    NSLog(@"kCVReturnDisplayLinkAlreadyRunning = %d", kCVReturnDisplayLinkAlreadyRunning);
    NSLog(@"kCVReturnDisplayLinkNotRunning = %d", kCVReturnDisplayLinkNotRunning);
    NSLog(@"kCVReturnDisplayLinkCallbacksNotSet = %d", kCVReturnDisplayLinkCallbacksNotSet);
    NSLog(@"kCVReturnInvalidPixelFormat = %d", kCVReturnInvalidPixelFormat);
    NSLog(@"kCVReturnInvalidSize = %d", kCVReturnInvalidSize);
    NSLog(@"kCVReturnInvalidPixelBufferAttributes = %d", kCVReturnInvalidPixelBufferAttributes);
    NSLog(@"kCVReturnPixelBufferNotOpenGLCompatible = %d", kCVReturnPixelBufferNotOpenGLCompatible);
    NSLog(@"kCVReturnPixelBufferNotMetalCompatible = %d", kCVReturnPixelBufferNotMetalCompatible);
    
    // 分析-6661错误
    NSLog(@"\n=== 分析错误 -6661 ===");
    NSLog(@"错误 -6661 可能的原因:");
    NSLog(@"1. IOSurface与OpenGL ES上下文不兼容");
    NSLog(@"2. IOSurface的像素格式虽然正确，但其他属性有问题");
    NSLog(@"3. OpenGL ES上下文状态不正确");
    NSLog(@"4. IOSurface的尺寸或对齐要求不满足");
    NSLog(@"5. 设备不支持特定的像素格式组合");
    
    NSLog(@"\n=== 可能的解决方案 ===");
    NSLog(@"1. 检查IOSurface的创建参数");
    NSLog(@"2. 验证OpenGL ES上下文状态");
    NSLog(@"3. 尝试不同的像素格式");
    NSLog(@"4. 检查设备兼容性");
    NSLog(@"5. 使用Metal纹理作为替代方案");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        analyzeCVOpenGLESTextureCacheError();
    }
    return 0;
}
