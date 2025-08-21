cmake_minimum_required(VERSION 3.16)
project(IOSDirectRendering)

# 设置iOS部署目标
set(CMAKE_OSX_DEPLOYMENT_TARGET "12.0")
set(CMAKE_OSX_ARCHITECTURES "arm64")

# 设置C++标准
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 查找必要的框架
find_library(UIKIT_FRAMEWORK UIKit)
find_library(FOUNDATION_FRAMEWORK Foundation)
find_library(METAL_FRAMEWORK Metal)
find_library(METALKIT_FRAMEWORK MetalKit)
find_library(OPENGLES_FRAMEWORK OpenGLES)
find_library(IOSURFACE_FRAMEWORK IOSurface)
find_library(COREVIDEO_FRAMEWORK CoreVideo)
find_library(QUARTZCORE_FRAMEWORK QuartzCore)

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

# 链接框架
target_link_libraries(ios_direct_rendering
    ${UIKIT_FRAMEWORK}
    ${FOUNDATION_FRAMEWORK}
    ${METAL_FRAMEWORK}
    ${METALKIT_FRAMEWORK}
    ${OPENGLES_FRAMEWORK}
    ${IOSURFACE_FRAMEWORK}
    ${COREVIDEO_FRAMEWORK}
    ${QUARTZCORE_FRAMEWORK}
)

# 设置编译选项
target_compile_options(ios_direct_rendering PRIVATE
    -fobjc-arc
    -fmodules
    -fobjc-weak
)

# 设置包含目录
target_include_directories(ios_direct_rendering PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

# 设置预处理器定义
target_compile_definitions(ios_direct_rendering PRIVATE
    IOS_DIRECT_RENDERING=1
)
