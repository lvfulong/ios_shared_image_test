#!/bin/bash

# iOS构建问题修复脚本
# 解决头文件找不到的问题

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info "=== iOS构建问题修复脚本 ==="

# 检查Xcode安装
print_info "检查Xcode安装..."
if [ ! -d "/Applications/Xcode.app" ]; then
    print_error "Xcode未安装，请先安装Xcode"
    exit 1
fi

# 检查iOS SDK
print_info "检查iOS SDK..."
IOS_SDK_PATH="/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
if [ ! -d "$IOS_SDK_PATH" ]; then
    print_error "iOS SDK未找到: $IOS_SDK_PATH"
    print_info "请确保已安装iOS开发工具"
    exit 1
fi

print_success "iOS SDK找到: $IOS_SDK_PATH"

# 检查必要的框架
print_info "检查必要的框架..."
FRAMEWORKS=(
    "UIKit.framework"
    "Foundation.framework"
    "Metal.framework"
    "MetalKit.framework"
    "OpenGLES.framework"
    "IOSurface.framework"
    "CoreVideo.framework"
    "QuartzCore.framework"
)

for framework in "${FRAMEWORKS[@]}"; do
    framework_path="$IOS_SDK_PATH/System/Library/Frameworks/$framework"
    if [ -d "$framework_path" ]; then
        print_success "✓ $framework"
    else
        print_error "✗ $framework 未找到"
        exit 1
    fi
done

# 创建修复后的CMakeLists.txt
print_info "创建修复后的CMakeLists.txt..."
cat > CMakeLists_fixed.txt << 'EOF'
cmake_minimum_required(VERSION 3.16)
project(IOSDirectRendering)

# 设置iOS部署目标
set(CMAKE_OSX_DEPLOYMENT_TARGET "12.0")
set(CMAKE_OSX_ARCHITECTURES "arm64")

# 设置iOS SDK路径
set(CMAKE_OSX_SYSROOT "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk")

# 设置C++标准
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 设置源文件
set(SOURCES
    main.m
    ios_app_delegate.m
    ios_view_controller.m
    ios_main_renderer.m
    ios_renderer.m
    ios_texture_manager.m
)

# 创建可执行文件
add_executable(ios_direct_rendering ${SOURCES})

# 设置Xcode特定属性
set_target_properties(ios_direct_rendering PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.example.iosdirectrendering"
    XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "iPhone Developer"
    XCODE_ATTRIBUTE_DEVELOPMENT_TEAM ""
    XCODE_ATTRIBUTE_PROVISIONING_PROFILE_SPECIFIER ""
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
    XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS "iphoneos iphonesimulator"
)

# 直接链接框架（使用完整路径）
target_link_libraries(ios_direct_rendering
    "${CMAKE_OSX_SYSROOT}/System/Library/Frameworks/UIKit.framework/UIKit"
    "${CMAKE_OSX_SYSROOT}/System/Library/Frameworks/Foundation.framework/Foundation"
    "${CMAKE_OSX_SYSROOT}/System/Library/Frameworks/Metal.framework/Metal"
    "${CMAKE_OSX_SYSROOT}/System/Library/Frameworks/MetalKit.framework/MetalKit"
    "${CMAKE_OSX_SYSROOT}/System/Library/Frameworks/OpenGLES.framework/OpenGLES"
    "${CMAKE_OSX_SYSROOT}/System/Library/Frameworks/IOSurface.framework/IOSurface"
    "${CMAKE_OSX_SYSROOT}/System/Library/Frameworks/CoreVideo.framework/CoreVideo"
    "${CMAKE_OSX_SYSROOT}/System/Library/Frameworks/QuartzCore.framework/QuartzCore"
)

# 设置编译选项
target_compile_options(ios_direct_rendering PRIVATE
    -fobjc-arc
    -fmodules
    -fobjc-weak
    -F"${CMAKE_OSX_SYSROOT}/System/Library/Frameworks"
    -I"${CMAKE_OSX_SYSROOT}/usr/include"
)

# 设置包含目录
target_include_directories(ios_direct_rendering PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    "${CMAKE_OSX_SYSROOT}/System/Library/Frameworks"
    "${CMAKE_OSX_SYSROOT}/usr/include"
)

# 设置预处理器定义
target_compile_definitions(ios_direct_rendering PRIVATE
    IOS_DIRECT_RENDERING=1
)
EOF

print_success "修复后的CMakeLists.txt已创建: CMakeLists_fixed.txt"

# 备份原始文件
if [ -f "CMakeLists.txt" ]; then
    print_info "备份原始CMakeLists.txt..."
    cp CMakeLists.txt CMakeLists_backup.txt
    print_success "备份完成: CMakeLists_backup.txt"
fi

# 替换为修复版本
print_info "替换CMakeLists.txt..."
cp CMakeLists_fixed.txt CMakeLists.txt
print_success "CMakeLists.txt已更新"

# 清理构建目录
if [ -d "build_ios" ]; then
    print_info "清理旧的构建目录..."
    rm -rf build_ios
    print_success "构建目录已清理"
fi

print_success "=== 修复完成 ==="
print_info "现在可以尝试重新构建项目:"
print_info "  ./build_ios.sh"
print_info ""
print_info "如果仍有问题，请检查:"
print_info "  1. Xcode版本是否支持iOS 12.0+"
print_info "  2. 是否安装了iOS开发工具"
print_info "  3. 设备是否支持Metal和OpenGL ES 2.0"
