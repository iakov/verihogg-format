cmake_minimum_required(VERSION 3.20 FATAL_ERROR)

project(verihogg-format VERSION 0.1.0 LANGUAGES CXX)

# Default build type
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Choose build type" FORCE)
endif()

# Use C++20
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Option: statically link the C runtime on MSVC (off = dynamic /MD).
option(VHG_USE_STATIC_CRT "Link C runtime statically on MSVC" OFF)

# Option: wrap the compiler in ccache to slice CI rebuild times. Enabled from
# CI via -DVHG_ENABLE_CCACHE=ON so local builds stay unchanged.
option(VHG_ENABLE_CCACHE "Use ccache as the compiler launcher" OFF)
find_program(VHG_CCACHE_PROGRAM ccache)
if(VHG_ENABLE_CCACHE AND VHG_CCACHE_PROGRAM)
  message(STATUS "Using ccache: ${VHG_CCACHE_PROGRAM}")
  set(CMAKE_CXX_COMPILER_LAUNCHER ${VHG_CCACHE_PROGRAM})
endif()

file(GLOB_RECURSE SRC CONFIGURE_DEPENDS formatter/src/**.cpp)

# Slang: support both slang (direct install) and slang-verilog (vcpkg) package names.
find_package(slang CONFIG QUIET)
if(NOT slang_FOUND)
  find_package(slang-verilog CONFIG QUIET)
  if(slang-verilog_FOUND AND NOT TARGET slang::slang)
    add_library(slang::slang ALIAS slang-verilog::slang)
  endif()
endif()
if(NOT TARGET slang::slang)
  message(FATAL_ERROR "\nslang (sv-lang) not found. Install via vcpkg:\n"
    "  vcpkg install slang-verilog\n"
    "Or provide a CMake prefix path pointing to a slang build:\n"
    "  cmake -S . -B build -DCMAKE_PREFIX_PATH=/path/to/slang/install\n")
endif()

# Microsoft.GSL: header-only. Some platforms ship a "gsl" package that is
# GNU Scientific Library (not Microsoft GSL) and does not provide gsl/span.
# A compile check -- not find_path/find_package -- is the reliable way to
# tell them apart, so probe the header and fall back to FetchContent.
include(CheckIncludeFileCXX)
check_include_file_cxx(gsl/span VHG_HAVE_MICROSOFT_GSL)
find_package(Microsoft.GSL CONFIG QUIET)
if(NOT TARGET Microsoft.GSL::GSL)
  if(VHG_HAVE_MICROSOFT_GSL)
    # The header already resolves with the current include flags (vcpkg or
    # system install offers gsl/span but no CMake config). An empty INTERFACE
    # target avoids re-downloading a header-only lib the compiler can find.
    add_library(Microsoft.GSL::GSL INTERFACE IMPORTED)
  else()
    include(FetchContent)
    FetchContent_Declare(microsoft-gsl
      GIT_REPOSITORY https://github.com/microsoft/GSL
      GIT_TAG v4.2.0
      GIT_SHALLOW TRUE)
    FetchContent_MakeAvailable(microsoft-gsl)
  endif()
endif()

# CLI11: header-only; FetchContent fallback.
find_package(CLI11 CONFIG QUIET)
if(NOT CLI11_FOUND)
  include(FetchContent)
  FetchContent_Declare(cli11
    GIT_REPOSITORY https://github.com/CLIUtils/CLI11.git
    GIT_TAG v2.4.2
    GIT_SHALLOW TRUE)
  FetchContent_MakeAvailable(cli11)
endif()

find_package(Threads REQUIRED)

find_package(yaml-cpp CONFIG REQUIRED)

# valijson: header-only; supports both ValiJSON::valijson and bare valijson targets.
find_package(valijson CONFIG QUIET)
if(NOT valijson_FOUND)
  include(FetchContent)
  FetchContent_Declare(valijson
    GIT_REPOSITORY https://github.com/tristanpenman/valijson.git
    GIT_TAG v1.1.2
    GIT_SHALLOW TRUE
    GIT_SUBMODULES "")
  FetchContent_MakeAvailable(valijson)
endif()

# Embed the configuration JSON schema into the binary so that runtime
# validation does not depend on files installed alongside the executable.
# The generated translation unit is self-contained: sources that IDE tooling
# parses never include files from the build tree.
set(VHG_SCHEMA_FILE
  ${CMAKE_CURRENT_SOURCE_DIR}/schemas/verihogg-format.schema.json)
set(VHG_GENERATED_DIR ${CMAKE_CURRENT_BINARY_DIR}/generated)
file(MAKE_DIRECTORY ${VHG_GENERATED_DIR}/config)
file(READ ${VHG_SCHEMA_FILE} VHG_SCHEMA_JSON)
file(WRITE ${VHG_GENERATED_DIR}/config/schema_embedded.cpp
"#include \"config/schema_embedded.h\"

namespace format::config {

auto embeddedSchemaJson() -> std::string_view {
  return
R\"VHG(
${VHG_SCHEMA_JSON}
)VHG\";
}

}  // namespace format::config
")
set(VHG_GENERATED_SOURCE ${VHG_GENERATED_DIR}/config/schema_embedded.cpp)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
  ${VHG_SCHEMA_FILE})

if(TARGET ValiJSON::valijson)
  set(VHG_VALIJSON_TARGET ValiJSON::valijson)
else()
  set(VHG_VALIJSON_TARGET valijson)
endif()

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

add_executable(${PROJECT_NAME} ${SRC} ${VHG_GENERATED_SOURCE})

if(WIN32)
  set(VHG_RC_FILE ${CMAKE_CURRENT_SOURCE_DIR}/formatter/resources/verihogg-format.rc)
  target_sources(${PROJECT_NAME} PRIVATE ${VHG_RC_FILE})
endif()

target_include_directories(${PROJECT_NAME}
  PUBLIC
  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/formatter/include>
)
target_compile_definitions(${PROJECT_NAME}
  PRIVATE VERIHOGG_VERSION="${PROJECT_VERSION}")
target_link_libraries(${PROJECT_NAME} PRIVATE slang::slang Microsoft.GSL::GSL CLI11::CLI11 Threads::Threads yaml-cpp::yaml-cpp ${VHG_VALIJSON_TARGET})

if(MSVC)
  target_compile_options(${PROJECT_NAME} PRIVATE /W4 /bigobj)
  if(VHG_USE_STATIC_CRT)
    set_property(TARGET ${PROJECT_NAME} PROPERTY MSVC_RUNTIME_LIBRARY
      "MultiThreaded$<$<CONFIG:Debug>:Debug>")
  else()
    set_property(TARGET ${PROJECT_NAME} PROPERTY MSVC_RUNTIME_LIBRARY
      "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")
  endif()
else()
  target_compile_options(${PROJECT_NAME} PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

# Precompiled header for the common library/system headers; cuts rebuild time
# substantially on MSVC and (with ccache) on GCC/Clang across all platforms.
target_precompile_headers(${PROJECT_NAME} PRIVATE
  <string>
  <string_view>
  <vector>
  <optional>
  <variant>
  <span>
  <memory>
  <filesystem>
  <fstream>
  <iostream>
  <sstream>
  <functional>
  <algorithm>
  <numeric>
  <cstdint>
)

# Install rule
include(GNUInstallDirs)
install(TARGETS ${PROJECT_NAME}
  RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})

# if(NOT DEFINED BUILD_TESTING)
# set(BUILD_TESTING ON)
# endif()
find_package(GTest QUIET)

if(GTest_FOUND)
  enable_testing()

  if(DEFINED ENV{SCR1_ROOT})
    set(SCR1_PATH "$ENV{SCR1_ROOT}")
  elseif(DEFINED SCR1_ROOT)
    set(SCR1_PATH "${SCR1_ROOT}")
  else()
    message(WARNING "SCR1_ROOT not set — SCR1 integration tests will be skipped. "
      "Set SCR1_ROOT to a checkout of https://github.com/syntacore/scr1 to enable them.")
    set(VHG_SKIP_SCR1 TRUE)
  endif()

  if(NOT VHG_SKIP_SCR1)
    message(STATUS "Using SCR1 from: ${SCR1_PATH}")
  endif()

  file(GLOB_RECURSE LIB_SRC CONFIGURE_DEPENDS formatter/src/**.cpp)
  list(FILTER LIB_SRC EXCLUDE REGEX ".*/main\\.cpp$")

  add_library(verihogg-format-lib STATIC ${LIB_SRC} ${VHG_GENERATED_SOURCE})
  target_include_directories(verihogg-format-lib PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/formatter/include>)
  target_compile_definitions(verihogg-format-lib
    PUBLIC VERIHOGG_VERSION="${PROJECT_VERSION}")
  target_precompile_headers(verihogg-format-lib REUSE_FROM ${PROJECT_NAME})
  target_link_libraries(verihogg-format-lib PUBLIC slang::slang Microsoft.GSL::GSL CLI11::CLI11 Threads::Threads)
  target_link_libraries(verihogg-format-lib PRIVATE yaml-cpp::yaml-cpp ${VHG_VALIJSON_TARGET})
  if(MSVC)
    set_property(TARGET verihogg-format-lib PROPERTY MSVC_RUNTIME_LIBRARY
      "MultiThreaded$<$<CONFIG:Debug>:Debug>$<IF:$<BOOL:${VHG_USE_STATIC_CRT}>,,DLL>")
  endif()

  file(GLOB_RECURSE TEST_SRC CONFIGURE_DEPENDS formatter/tests/*.cpp)
  if(VHG_SKIP_SCR1)
    list(FILTER TEST_SRC EXCLUDE REGEX ".*scr1_tests\\.cpp$")
  endif()

  if(TEST_SRC)
    add_executable(verihogg-tests ${TEST_SRC})
    target_link_libraries(verihogg-tests PRIVATE verihogg-format-lib GTest::gtest GTest::gtest_main CLI11::CLI11)
    # gtest_discover_tests resolves the emulator from the target's
    # CROSSCOMPILING_EMULATOR *property*, not the global variable, so mirror
    # the global into the property or discovery/(PRE_TEST) runs the bare .exe.
    if(CMAKE_CROSSCOMPILING_EMULATOR)
      set_target_properties(verihogg-tests PROPERTIES
        CROSSCOMPILING_EMULATOR "${CMAKE_CROSSCOMPILING_EMULATOR}")
    endif()
    if(NOT VHG_SKIP_SCR1)
      target_compile_definitions(verihogg-tests PRIVATE SCR1_DIR="${SCR1_PATH}")
    endif()
    include(GoogleTest)
    gtest_discover_tests(verihogg-tests DISCOVERY_MODE PRE_TEST)
    if(NOT WIN32 OR CMAKE_CROSSCOMPILING_EMULATOR)
    add_test(NAME CheckCliInputErrors
        COMMAND ${CMAKE_COMMAND}
          -DFORMATTER=$<TARGET_FILE:verihogg-format>
          -DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/check-cli-tests
          -P ${CMAKE_CURRENT_SOURCE_DIR}/formatter/tests/check_cli_test.cmake)
    endif()
  endif()
endif()
