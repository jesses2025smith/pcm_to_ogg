cmake_minimum_required(VERSION 3.10)
project(pcm_to_ogg C)

# The order is important: ogg is needed by vorbis.
add_subdirectory(third_party/libogg-1.3.5)
add_subdirectory(third_party/libvorbis-1.3.7)

# For Linux and Android, enable position-independent code (-fPIC) for static libraries
# This is required when linking static libraries into shared libraries
if(CMAKE_SYSTEM_NAME STREQUAL "Linux" OR ANDROID)
    set_target_properties(ogg_static PROPERTIES
        POSITION_INDEPENDENT_CODE ON
    )
    set_target_properties(vorbis_static PROPERTIES
        POSITION_INDEPENDENT_CODE ON
    )
endif()

# Create a library from our C wrapper source file.
add_library(pcm_to_ogg_library
    pcm_to_ogg.c
)

# For Linux and Android, we need -fPIC to link static libraries into shared libraries
if(CMAKE_SYSTEM_NAME STREQUAL "Linux" OR ANDROID)
  set_target_properties(pcm_to_ogg_library PROPERTIES
    POSITION_INDEPENDENT_CODE ON
  )
endif()

# Don't set visibility preset here - let the C code's __attribute__((visibility("default"))) 
# handle it. Setting C_VISIBILITY_PRESET would override the attribute.

# Link our library against the vorbis static library.
# vorbis_static already links against ogg_static.
target_link_libraries(pcm_to_ogg_library PRIVATE vorbis_static)

# Add the include directories from our third-party libs
# so our pcm_to_ogg.c can find the headers.
target_include_directories(pcm_to_ogg_library PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/libogg-1.3.5/include
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/libvorbis-1.3.7/include
)

# --- Web Specific ---
if(FLUTTER_TARGET_WEB)
    add_library(pcm_to_ogg STATIC
        pcm_to_ogg.c
    )
    target_link_libraries(pcm_to_ogg PRIVATE vorbis_static)
    set_target_properties(pcm_to_ogg PROPERTIES
        OUTPUT_NAME "pcm_to_ogg"
        SUFFIX ".wasm"
    )
endif()

# --- Android Specific ---
# Create a shared library for Android (JNI).
# The name here must match what is loaded in the Dart code.
# On Android, we directly compile the source into the shared library to ensure
# all symbols (including streaming encoder functions) are exported.
if(ANDROID)
    add_library(pcm_to_ogg SHARED
        pcm_to_ogg.c
        pcm_to_ogg_android.c
    )
    target_link_libraries(pcm_to_ogg PRIVATE
        vorbis_static
        ogg_static
    )
    target_include_directories(pcm_to_ogg PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/third_party/libogg-1.3.5/include
        ${CMAKE_CURRENT_SOURCE_DIR}/third_party/libvorbis-1.3.7/include
    )
endif()
