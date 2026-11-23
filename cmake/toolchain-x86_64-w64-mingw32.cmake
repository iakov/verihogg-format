# Toolchain file for cross-compiling to Windows x64 using MinGW-w64.
# Usage: cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-x86_64-w64-mingw32.cmake
#
# The -posix compiler variant is required for std::thread and C++ exception
# support. The -win32 variant lacks __thread and breaks C++ exception chains
# across thread boundaries.

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# Use the POSIX thread model variant for std::thread and C++ exception support.
set(CMAKE_C_COMPILER x86_64-w64-mingw32-gcc-posix)
set(CMAKE_CXX_COMPILER x86_64-w64-mingw32-g++-posix)
set(CMAKE_RC_COMPILER x86_64-w64-mingw32-windres)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)