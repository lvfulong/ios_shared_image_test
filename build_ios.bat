@echo off
setlocal enabledelayedexpansion

REM iOS 直接渲染版本构建脚本 (Windows版本)
REM 支持零拷贝渲染的GLES多线程三角形渲染器

REM 颜色定义 (Windows不支持ANSI颜色，使用echo)
set "RED=[ERROR]"
set "GREEN=[SUCCESS]"
set "YELLOW=[WARNING]"
set "BLUE=[INFO]"

REM 打印带颜色的消息
:print_info
echo %BLUE% %~1
goto :eof

:print_success
echo %GREEN% %~1
goto :eof

:print_warning
echo %YELLOW% %~1
goto :eof

:print_error
echo %RED% %~1
goto :eof

REM 检查依赖
:check_dependencies
call :print_info "检查构建依赖..."

REM 检查cmake
where cmake >nul 2>&1
if %errorlevel% neq 0 (
    call :print_error "cmake 未找到，请安装 cmake"
    exit /b 1
)

REM 检查xcodebuild (在Windows上通常不可用)
where xcodebuild >nul 2>&1
if %errorlevel% neq 0 (
    call :print_warning "xcodebuild 未找到，iOS构建需要在macOS上进行"
    call :print_info "请将项目复制到macOS系统进行构建"
    exit /b 1
)

call :print_success "依赖检查完成"
goto :eof

REM 创建构建目录
:create_build_dir
set "build_dir=build_ios"
call :print_info "创建构建目录: %build_dir%"

if exist "%build_dir%" (
    call :print_warning "构建目录已存在，清理中..."
    rmdir /s /q "%build_dir%"
)

mkdir "%build_dir%"
cd "%build_dir%"

call :print_success "构建目录创建完成"
goto :eof

REM 配置CMake项目
:configure_project
call :print_info "配置CMake项目..."

REM 在Windows上，iOS构建通常不可用
call :print_error "iOS构建需要在macOS系统上进行"
call :print_info "请将项目复制到macOS系统，然后运行 build_ios.sh"
exit /b 1

REM 构建项目
:build_project
call :print_info "开始构建项目..."

REM 构建Release版本
cmake --build . --config Release

if %errorlevel% equ 0 (
    call :print_success "项目构建成功"
) else (
    call :print_error "项目构建失败"
    exit /b 1
)
goto :eof

REM 检查构建结果
:check_build_result
call :print_info "检查构建结果..."

set "app_path="

REM 查找生成的.app文件
if exist "Release\ios_direct_rendering.app" (
    set "app_path=Release\ios_direct_rendering.app"
) else if exist "Debug\ios_direct_rendering.app" (
    set "app_path=Debug\ios_direct_rendering.app"
) else (
    call :print_warning "未找到生成的.app文件"
    goto :eof
)

call :print_success "找到应用: %app_path%"

REM 检查文件大小
for %%A in ("%app_path%") do set "size=%%~zA"
call :print_info "应用大小: %size% bytes"
goto :eof

REM 清理构建
:clean_build
call :print_info "清理构建文件..."
cd ..
if exist "build_ios" rmdir /s /q "build_ios"
call :print_success "清理完成"
goto :eof

REM 显示帮助信息
:show_help
echo iOS 直接渲染版本构建脚本 (Windows版本)
echo.
echo 用法: %~nx0 [选项]
echo.
echo 选项:
echo   -h, --help     显示此帮助信息
echo   -c, --clean    清理构建文件
echo   -d, --debug    构建Debug版本
echo   -r, --release  构建Release版本 (默认)
echo.
echo 示例:
echo   %~nx0              # 构建Release版本
echo   %~nx0 --debug      # 构建Debug版本
echo   %~nx0 --clean      # 清理构建文件
echo.
echo 注意:
echo   - iOS构建需要在macOS系统上进行
echo   - 需要安装 Xcode 和 iOS 开发工具
echo   - 支持 iOS 12.0+ 和 ARM64 架构
echo   - 实现了零拷贝渲染优化
goto :eof

REM 主函数
:main
set "build_type=Release"
set "should_clean=false"

REM 解析命令行参数
:parse_args
if "%~1"=="" goto :start_build
if "%~1"=="-h" goto :show_help
if "%~1"=="--help" goto :show_help
if "%~1"=="-c" (
    set "should_clean=true"
    shift
    goto :parse_args
)
if "%~1"=="--clean" (
    set "should_clean=true"
    shift
    goto :parse_args
)
if "%~1"=="-d" (
    set "build_type=Debug"
    shift
    goto :parse_args
)
if "%~1"=="--debug" (
    set "build_type=Debug"
    shift
    goto :parse_args
)
if "%~1"=="-r" (
    set "build_type=Release"
    shift
    goto :parse_args
)
if "%~1"=="--release" (
    set "build_type=Release"
    shift
    goto :parse_args
)

call :print_error "未知选项: %~1"
call :show_help
exit /b 1

:start_build
call :print_info "=== iOS 直接渲染版本构建脚本 (Windows) ==="
call :print_info "构建类型: %build_type%"
call :print_info "零拷贝渲染优化: 已启用"

if "%should_clean%"=="true" (
    call :clean_build
    exit /b 0
)

REM 执行构建流程
call :check_dependencies
if %errorlevel% neq 0 exit /b %errorlevel%

call :create_build_dir
if %errorlevel% neq 0 exit /b %errorlevel%

call :configure_project
if %errorlevel% neq 0 exit /b %errorlevel%

call :build_project
if %errorlevel% neq 0 exit /b %errorlevel%

call :check_build_result

call :print_success "=== 构建完成 ==="
call :print_info "项目已成功构建为iOS应用"
call :print_info "支持零拷贝渲染，性能优化"

exit /b 0
