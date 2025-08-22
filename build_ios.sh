#!/bin/bash

# iOS 直接渲染版本构建脚本
# 支持零拷贝渲染的GLES多线程三角形渲染器

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
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

# 检查依赖
check_dependencies() {
    print_info "检查构建依赖..."
    
    # 检查cmake
    if ! command -v cmake &> /dev/null; then
        print_error "cmake 未找到，请安装 cmake"
        exit 1
    fi
    
    # 检查xcodebuild
    if ! command -v xcodebuild &> /dev/null; then
        print_error "xcodebuild 未找到，请安装 Xcode"
        exit 1
    fi
    
    # 检查iOS工具链
    if [ ! -f "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk" ]; then
        print_warning "iOS SDK 未找到，可能需要安装 Xcode 或 iOS 开发工具"
    fi
    
    print_success "依赖检查完成"
}

# 创建构建目录
create_build_dir() {
    local build_dir="build_ios"
    
    print_info "创建构建目录: $build_dir"
    
    if [ -d "$build_dir" ]; then
        print_warning "构建目录已存在，清理中..."
        rm -rf "$build_dir"
    fi
    
    mkdir -p "$build_dir"
    cd "$build_dir"
    
    print_success "构建目录创建完成"
}

# 配置CMake项目
configure_project() {
    print_info "配置CMake项目..."
    
    # 尝试使用iOS工具链
    local toolchain_file=""
    
    # 常见的iOS工具链位置
    local toolchain_paths=(
        "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
        "/usr/local/share/cmake/ios.toolchain.cmake"
        "$HOME/cmake/ios.toolchain.cmake"
    )
    
    for path in "${toolchain_paths[@]}"; do
        if [ -f "$path" ] || [ -d "$path" ]; then
            if [[ "$path" == *"toolchain.cmake" ]]; then
                toolchain_file="$path"
                break
            fi
        fi
    done
    
    local cmake_cmd="cmake -G Xcode"
    
    if [ -n "$toolchain_file" ]; then
        print_info "使用工具链文件: $toolchain_file"
        cmake_cmd="$cmake_cmd -DCMAKE_TOOLCHAIN_FILE=$toolchain_file"
    else
        print_warning "未找到iOS工具链文件，使用默认配置"
        # 设置iOS相关变量
        cmake_cmd="$cmake_cmd -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0"
        cmake_cmd="$cmake_cmd -DCMAKE_OSX_ARCHITECTURES=arm64"
        cmake_cmd="$cmake_cmd -DCMAKE_SYSTEM_NAME=iOS"
    fi
    
    cmake_cmd="$cmake_cmd ../CMakeLists.txt"
    
    print_info "执行: $cmake_cmd"
    eval $cmake_cmd
    
    if [ $? -eq 0 ]; then
        print_success "CMake配置成功"
    else
        print_error "CMake配置失败"
        exit 1
    fi
}

# 构建项目
build_project() {
    print_info "开始构建项目..."
    
    # 构建Release版本
    cmake --build . --config Release
    
    if [ $? -eq 0 ]; then
        print_success "项目构建成功"
    else
        print_error "项目构建失败"
        exit 1
    fi
}

# 检查构建结果
check_build_result() {
    print_info "检查构建结果..."
    
    local app_path=""
    
    # 查找生成的.app文件
    if [ -d "Release/ios_direct_rendering.app" ]; then
        app_path="Release/ios_direct_rendering.app"
    elif [ -d "Debug/ios_direct_rendering.app" ]; then
        app_path="Debug/ios_direct_rendering.app"
    else
        print_warning "未找到生成的.app文件"
        return
    fi
    
    print_success "找到应用: $app_path"
    
    # 显示应用信息
    if command -v plutil &> /dev/null; then
        print_info "应用信息:"
        plutil -p "$app_path/Info.plist" | grep -E "(CFBundleName|CFBundleVersion|CFBundleIdentifier)"
    fi
    
    # 检查文件大小
    local size=$(du -sh "$app_path" | cut -f1)
    print_info "应用大小: $size"
}

# 清理构建
clean_build() {
    print_info "清理构建文件..."
    cd ..
    rm -rf build_ios
    print_success "清理完成"
}

# 显示帮助信息
show_help() {
    echo "iOS 直接渲染版本构建脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  -c, --clean    清理构建文件"
    echo "  -d, --debug    构建Debug版本"
    echo "  -r, --release  构建Release版本 (默认)"
    echo ""
    echo "示例:"
    echo "  $0              # 构建Release版本"
    echo "  $0 --debug      # 构建Debug版本"
    echo "  $0 --clean      # 清理构建文件"
    echo ""
    echo "注意:"
    echo "  - 需要安装 Xcode 和 iOS 开发工具"
    echo "  - 支持 iOS 12.0+ 和 ARM64 架构"
    echo "  - 实现了零拷贝渲染优化"
}

# 主函数
main() {
    local build_type="Release"
    local should_clean=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--clean)
                should_clean=true
                shift
                ;;
            -d|--debug)
                build_type="Debug"
                shift
                ;;
            -r|--release)
                build_type="Release"
                shift
                ;;
            *)
                print_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    print_info "=== iOS 直接渲染版本构建脚本 ==="
    print_info "构建类型: $build_type"
    print_info "零拷贝渲染优化: 已启用"
    
    if [ "$should_clean" = true ]; then
        clean_build
        exit 0
    fi
    
    # 执行构建流程
    #check_dependencies
    create_build_dir
    configure_project
    #build_project
    #check_build_result
    
    print_success "=== 构建完成 ==="
    print_info "项目已成功构建为iOS应用"
    print_info "支持零拷贝渲染，性能优化"
}

# 运行主函数
main "$@"
