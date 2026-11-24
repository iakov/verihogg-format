function(enable_ubsan)
  add_compile_options($<$<OR:$<CXX_COMPILER_ID:GNU>,$<CXX_COMPILER_ID:Clang>,$<CXX_COMPILER_ID:AppleClang>>:
    -fsanitize=undefined -fno-sanitize-recover=all>)
  add_link_options($<$<OR:$<CXX_COMPILER_ID:GNU>,$<CXX_COMPILER_ID:Clang>,$<CXX_COMPILER_ID:AppleClang>>:
    -fsanitize=undefined>)
endfunction()

function(enable_asan)
  add_compile_options($<$<OR:$<CXX_COMPILER_ID:GNU>,$<CXX_COMPILER_ID:Clang>,$<CXX_COMPILER_ID:AppleClang>,$<CXX_COMPILER_ID:MSVC>>:
    -fsanitize=address -fno-omit-frame-pointer -fno-optimize-sibling-calls>)
  add_link_options($<$<OR:$<CXX_COMPILER_ID:GNU>,$<CXX_COMPILER_ID:Clang>,$<CXX_COMPILER_ID:AppleClang>,$<CXX_COMPILER_ID:MSVC>>:
    -fsanitize=address>)
endfunction()