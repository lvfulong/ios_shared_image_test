@echo off
setlocal enabledelayedexpansion

REM iOS构建问题修复脚本 (Windows版本)
REM 解决头文件找不到的问题

REM 颜色定义
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

call :print_info "=== iOS构建问题修复脚本 (Windows) ==="

REM 在Windows上，iOS构建通常不可用
call :print_error "iOS构建需要在macOS系统上进行"
call :print_info "请将项目复制到macOS系统，然后运行以下命令："
echo.
echo   1. 给修复脚本添加执行权限：
echo      chmod +x fix_ios_build.sh
echo.
echo   2. 运行修复脚本：
echo      ./fix_ios_build.sh
echo.
echo   3. 构建项目：
echo      ./build_ios.sh
echo.

call :print_info "修复脚本将自动："
call :print_info "  - 检查Xcode和iOS SDK安装"
call :print_info "  - 验证必要的框架是否存在"
call :print_info "  - 创建修复后的CMakeLists.txt"
call :print_info "  - 更新项目配置"
echo.

call :print_warning "当前在Windows系统上，无法直接构建iOS应用"
call :print_info "请将项目复制到macOS系统进行构建"

exit /b 0
