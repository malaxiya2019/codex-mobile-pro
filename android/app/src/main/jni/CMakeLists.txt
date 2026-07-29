cmake_minimum_required(VERSION 3.18.1)

project("pty_native")

# 编译静态库，实际会被 app 的 linker 加载为共享库
add_library(pty_native SHARED
    pty.c
)

target_include_directories(pty_native PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

# 链接 Android 日志库用于调试
target_link_libraries(pty_native
    log
)

# 强制使用 C99 标准
set_target_properties(pty_native PROPERTIES
    C_STANDARD 99
    C_STANDARD_REQUIRED ON
)
