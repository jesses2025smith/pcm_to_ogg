#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint pcm_to_ogg.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'pcm_to_ogg'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter plugin project.'
  s.description      = <<-DESC
A new Flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  s.source           = { :path => '.' }
  
  # Copy source files from parent directory to podspec directory during pod install
  # This is necessary because CocoaPods source_files doesn't support parent directory paths (../)
  s.prepare_command = <<-CMD
    # Create Sources directory if it doesn't exist
    if [ -d "Sources" ]; then
      rm -rf Sources
    fi
    # Copy src directory structure to Sources
    mkdir -p Sources && cp -R ../src/* Sources/
    
  CMD
  
  # Compile source files directly instead of using precompiled static libraries
  # Paths are relative to podspec directory (macos/) after prepare_command copies files
  s.source_files = 'Classes/**/*',
                   'Sources/pcm_to_ogg.c',
                   'Sources/third_party/libogg-1.3.5/src/bitwise.c',
                   'Sources/third_party/libogg-1.3.5/src/framing.c',
                   'Sources/third_party/libvorbis-1.3.7/lib/analysis.c',
                   'Sources/third_party/libvorbis-1.3.7/lib/bitrate.c',
                   'Sources/third_party/libvorbis-1.3.7/lib/block.c',
                   'Sources/third_party/libvorbis-1.3.7/lib/codebook.c',
                   'Sources/third_party/libvorbis-1.3.7/lib/envelope.c',
                   'Sources/third_party/libvorbis-1.3.7/lib/floor0.c',
                   'Sources/third_party/libvorbis-1.3.7/lib/floor1.c',
                   'Sources/third_party/libvorbis-1.3.7/lib/info.c',
                   'Sources/third_party/libvorbis-1.3.7/lib/lookup.c',
                   'Sources/third_party/libvorbis-1.3.7/lib/lpc.c',
                   'Sources/third_party/libvorbis-1.3.7/lib/lsp.c',
                   'Sources/third_party/libvorbis-1.3.7/lib/mapping0.c',
                   'Sources/third_party/libvorbis-1.3.7/lib/mdct.c',
                   'Sources/third_party/libvorbis-1.3.7/lib/psy.c',
                   'Sources/third_party/libvorbis-1.3.7/lib/registry.c',
                   'Sources/third_party/libvorbis-1.3.7/lib/res0.c',
                   'Sources/third_party/libvorbis-1.3.7/lib/sharedbook.c',
                   'Sources/third_party/libvorbis-1.3.7/lib/smallft.c',
                   'Sources/third_party/libvorbis-1.3.7/lib/synthesis.c',
                   'Sources/third_party/libvorbis-1.3.7/lib/vorbisenc.c',
                   'Sources/third_party/libvorbis-1.3.7/lib/vorbisfile.c',
                   'Sources/third_party/libvorbis-1.3.7/lib/window.c'
  
  # Public headers - only expose plugin headers, not third-party library headers
  # Third-party headers (ogg/vorbis) are accessed via header search paths and copied by script phase
  s.public_header_files = 'Classes/**/*.h',
                          'Sources/pcm_to_ogg.h'
  
  # Script phase to copy header files and directories to framework Headers after build
  # This ensures all necessary headers are available in the framework
  s.script_phase = {
    :name => 'Copy Header Files and Directories',
    :script => <<-SCRIPT,
      # Find the framework Headers directory
      FRAMEWORK_HEADERS="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.framework/Headers"
      mkdir -p "${FRAMEWORK_HEADERS}"
      
      # Copy pcm_to_ogg.h
      if [ -f "${PODS_TARGET_SRCROOT}/Sources/pcm_to_ogg.h" ]; then
        cp "${PODS_TARGET_SRCROOT}/Sources/pcm_to_ogg.h" "${FRAMEWORK_HEADERS}/" || true
      fi
      
      # Copy ogg/ and vorbis/ directories from copied source
      if [ -d "${PODS_TARGET_SRCROOT}/Sources/third_party/libogg-1.3.5/include/ogg" ]; then
        cp -R "${PODS_TARGET_SRCROOT}/Sources/third_party/libogg-1.3.5/include/ogg" "${FRAMEWORK_HEADERS}/" || true
      fi
      
      if [ -d "${PODS_TARGET_SRCROOT}/Sources/third_party/libvorbis-1.3.7/include/vorbis" ]; then
        cp -R "${PODS_TARGET_SRCROOT}/Sources/third_party/libvorbis-1.3.7/include/vorbis" "${FRAMEWORK_HEADERS}/" || true
      fi
      
      # Update umbrella header to include third-party headers to silence warnings
      # Find and update umbrella header in Pods directory
      UMBRELLA_HEADER_PODS="${PODS_ROOT}/Target Support Files/${PRODUCT_NAME}/${PRODUCT_NAME}-umbrella.h"
      UMBRELLA_HEADER_FRAMEWORK="${FRAMEWORK_HEADERS}/${PRODUCT_NAME}-umbrella.h"
      
      update_umbrella() {
        local header_file="$1"
        if [ -f "${header_file}" ] && ! grep -q "ogg/config_types.h" "${header_file}"; then
          # Create a temp file with the modifications
          TEMP_FILE=$(mktemp)
          # Copy everything before FOUNDATION_EXPORT double, add imports, then add the rest
          sed '/^FOUNDATION_EXPORT double/,$!d' "${header_file}" > "${TEMP_FILE}.tail"
          sed '/^FOUNDATION_EXPORT double/,$d' "${header_file}" > "${TEMP_FILE}.head"
          echo '#import "ogg/config_types.h"' >> "${TEMP_FILE}.head"
          echo '#import "ogg/os_types.h"' >> "${TEMP_FILE}.head"
          echo '#import "vorbis/vorbisfile.h"' >> "${TEMP_FILE}.head"
          cat "${TEMP_FILE}.head" "${TEMP_FILE}.tail" > "${header_file}"
          rm -f "${TEMP_FILE}.head" "${TEMP_FILE}.tail" "${TEMP_FILE}"
        fi
      }
      
      update_umbrella "${UMBRELLA_HEADER_PODS}"
      update_umbrella "${UMBRELLA_HEADER_FRAMEWORK}"
    SCRIPT
    :execution_position => :after_compile,
    :output_files => ['${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.framework/Headers/pcm_to_ogg.h', '${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.framework/Headers/${PRODUCT_NAME}-umbrella.h']
  }

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES',
    # Header search paths for ogg and vorbis from copied source directories
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/Sources" "${PODS_TARGET_SRCROOT}/Sources/third_party/libogg-1.3.5/include" "${PODS_TARGET_SRCROOT}/Sources/third_party/libvorbis-1.3.7/include" "${PODS_TARGET_SRCROOT}/Sources/third_party/libvorbis-1.3.7/lib"',
    # Ensure symbols are exported for framework
    'OTHER_CFLAGS' => '$(inherited) -fvisibility=default',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -fvisibility=default',
    # Suppress umbrella header warnings for third-party headers
    'CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER' => 'NO'
  }
  
  # Suppress warnings from the C libraries
  s.compiler_flags = '-Wno-everything -fvisibility=default'
  
  s.swift_version = '5.0'
end