cmake_minimum_required(VERSION 3.21)

project(firebird VERSION 1.6 LANGUAGES C CXX)

include(CheckLanguage)
check_language(ASM)
if(CMAKE_ASM_COMPILER)
    enable_language(ASM)
endif()

set(TRANSLATION_ENABLED "auto" CACHE STRING "Enable the JIT: true, false or auto (default)")
set_property(CACHE TRANSLATION_ENABLED PROPERTY STRINGS true false auto)
set(SUPPORT_LINUX "" CACHE STRING "Emulate a Linux OS: true, false or auto (default)")
set_property(CACHE SUPPORT_LINUX PROPERTY STRINGS true false auto)

foreach(_fb_opt IN ITEMS TRANSLATION_ENABLED SUPPORT_LINUX)
    string(TOLOWER "${${_fb_opt}}" _fb_val)
    if(_fb_val STREQUAL "" OR _fb_val STREQUAL "auto")
        set(${_fb_opt} "auto")
    elseif(_fb_val MATCHES "^(1|on|yes|true|t|y)$")
        set(${_fb_opt} "true")
    elseif(_fb_val MATCHES "^(0|off|no|false|f|n)$")
        set(${_fb_opt} "false")
    else()
        message(FATAL_ERROR "${_fb_opt} must be set to true, false or auto, not '${${_fb_opt}}'")
    endif()
    unset(_fb_val)
endforeach()

if(SUPPORT_LINUX STREQUAL "auto")
    if(IOS OR ANDROID)
        set(SUPPORT_LINUX "false")
    else()
        set(SUPPORT_LINUX "true")
    endif()
endif()

find_package(Qt6 6.3 REQUIRED COMPONENTS Core Gui Widgets QuickWidgets QuickControls2 LinguistTools)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_EXTENSIONS ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTOUIC ON)
set(CMAKE_AUTORCC ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type (qmake: debug or release)" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS Debug Release RelWithDebInfo MinSizeRel)
endif()

if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/core/gif-h/gif.h")
    message(FATAL_ERROR "You have to run 'git submodule init' and 'git submodule update' first.")
endif()

if(UNIX AND NOT ANDROID)
    message(STATUS "PREFIX: ${CMAKE_INSTALL_PREFIX}")
endif()

if(APPLE AND NOT IOS)
    if(NOT CMAKE_OSX_ARCHITECTURES)
        set(CMAKE_OSX_ARCHITECTURES "${CMAKE_SYSTEM_PROCESSOR}" CACHE STRING "macOS architecture to build for" FORCE)
    endif()
    list(LENGTH CMAKE_OSX_ARCHITECTURES _fb_apple_arch_count)
    if(NOT _fb_apple_arch_count EQUAL 1)
        message(FATAL_ERROR "Firebird can only be built for one macOS architecture at a time, not for: ${CMAKE_OSX_ARCHITECTURES}")
    endif()
    unset(_fb_apple_arch_count)
endif()

if(ANDROID)
    if(CMAKE_ANDROID_ARCH_ABI)
        set(FB_ARCH "${CMAKE_ANDROID_ARCH_ABI}")
    else()
        set(FB_ARCH "${CMAKE_SYSTEM_PROCESSOR}")
    endif()
elseif(APPLE AND NOT IOS)
    set(FB_ARCH "${CMAKE_OSX_ARCHITECTURES}")
elseif(EMSCRIPTEN OR CMAKE_SYSTEM_NAME STREQUAL "Emscripten")
    set(FB_ARCH "wasm")
else()
    set(FB_ARCH "${CMAKE_SYSTEM_PROCESSOR}")
endif()

if(FB_ARCH MATCHES "^arm64")
    set(FB_ARCH "aarch64")
endif()

if(FB_ARCH MATCHES "^arm")
    set(FB_ARCH "arm")
endif()

if(FB_ARCH MATCHES "^(i[3456]86|x86)$")
    set(FB_ARCH "x86")
endif()

if(FB_ARCH STREQUAL "AMD64")
    set(FB_ARCH "x86_64")
endif()

set(ASMCODE_IMPL "${CMAKE_CURRENT_SOURCE_DIR}/core/asmcode.c")

file(GLOB TRANSLATE "${CMAKE_CURRENT_SOURCE_DIR}/core/translate_${FB_ARCH}.c*")

if(TRANSLATION_ENABLED STREQUAL "auto")
    if(TRANSLATE)
        set(TRANSLATION_ENABLED "true")
    else()
        set(TRANSLATION_ENABLED "false")
    endif()
endif()

if(TRANSLATION_ENABLED STREQUAL "true")
    if(NOT TRANSLATE)
        message(FATAL_ERROR "No JIT found for arch ${FB_ARCH}")
    endif()
    if(NOT CMAKE_ASM_COMPILER)
        message(FATAL_ERROR "The JIT requires handwritten .S assembly files, but no assembler was detected.")
    endif()

    set(ASMCODE_IMPL "")
    file(GLOB ASMCODE_IMPL "${CMAKE_CURRENT_SOURCE_DIR}/core/asmcode_${FB_ARCH}.S")
    if(NOT FB_ARCH STREQUAL "x86")
        list(APPEND ASMCODE_IMPL "${CMAKE_CURRENT_SOURCE_DIR}/core/asmcode.c")
    endif()
endif()

message(STATUS "FB_ARCH: ${FB_ARCH}")
message(STATUS "TRANSLATION_ENABLED: ${TRANSLATION_ENABLED}")
message(STATUS "SUPPORT_LINUX: ${SUPPORT_LINUX}")

set(FB_SOURCES ${ASMCODE_IMPL}
    core/fieldparser.cpp
    lcdwidget.cpp
    mainwindow.cpp
    main.cpp
    emuthread.cpp
    qmlbridge.cpp
    qtkeypadbridge.cpp
    core/arm_interpreter.cpp
    core/coproc.cpp
    core/cpu.cpp
    core/thumb_interpreter.cpp
    core/usblink_queue.cpp
    core/armsnippets_loader.c
    core/casplus.c
    core/des.c
    core/disasm.c
    core/gdbstub.c
    core/gif.cpp
    core/interrupt.c
    core/keypad.cpp
    core/lcd.c
    core/link.c
    core/mem.c
    core/misc.c
    core/mmu.c
    core/schedule.c
    core/serial.c
    core/sha256.c
    core/usb.c
    core/usb_cx2.cpp
    core/usblink.c
    core/usblink_cx2.cpp
    qtframebuffer.cpp
    core/debug.cpp
    core/flash.cpp
    core/emu.cpp
    usblinktreewidget.cpp
    kitmodel.cpp
    fbaboutdialog.cpp
    dockwidget.cpp
    consolelineedit.cpp
    core/cx2.cpp
)

if(UNIX OR EMSCRIPTEN OR CMAKE_SYSTEM_NAME STREQUAL "Emscripten")
    list(APPEND FB_SOURCES core/os/os-linux.c)
endif()

if(ANDROID)
    list(APPEND FB_SOURCES core/os/os-android.cpp)
endif()

if(WIN32)
    list(APPEND FB_SOURCES core/os/os-win32.c)
endif()

if(TRANSLATION_ENABLED STREQUAL "true")
    list(APPEND FB_SOURCES ${TRANSLATE})
endif()

set(FB_HEADERS
    apptranslation.h
    core/fieldparser.h
    core/usb_cx2.h
    core/usblink_cx2.h
    emuthread.h
    lcdwidget.h
    mainwindow.h
    keymap.h
    qmlbridge.h
    qtkeypadbridge.h
    core/os/os.h
    core/armcode_bin.h
    core/armsnippets.h
    core/asmcode.h
    core/bitfield.h
    core/casplus.h
    core/cpu.h
    core/cpudefs.h
    core/debug.h
    core/des.h
    core/disasm.h
    core/emu.h
    core/flash.h
    core/gdbstub.h
    core/gif.h
    core/interrupt.h
    core/keypad.h
    core/lcd.h
    core/link.h
    core/mem.h
    core/misc.h
    core/mmu.h
    core/schedule.h
    core/sha256.h
    core/translate.h
    core/usb.h
    core/usblink.h
    core/usblink_queue.h
    qtframebuffer.h
    usblinktreewidget.h
    kitmodel.h
    fbaboutdialog.h
    dockwidget.h
    consolelineedit.h
    core/cx2.h
)

set(FB_FORMS mainwindow.ui)
set(FB_RESOURCES resources.qrc)

set(FB_LUPDATE_QML
    qml/Keypad.qml
    qml/MobileUI.qml
    qml/ConfigPagesModel.qml
    qml/NNumButton.qml
    qml/MobileControl2.qml
    qml/SidebarButton.qml
    qml/ConfigPageDebug.qml
    qml/ConfigPageEmulation.qml
    qml/ConfigPageFileTransfer.qml
    qml/ConfigPageKits.qml
    qml/NBigButton.qml
    qml/NButton.qml
    qml/NAlphaButton.qml
    qml/NDualButton.qml
    qml/FBConfigDialog.qml
    qml/FlashDialog.qml
    qml/Touchpad.qml
    qml/Firebird/Emu/Emu.qml
    qml/Firebird/Emu/EmuScreen.qml
    qml/Firebird/UIComponents/FBLabel.qml
    qml/Firebird/UIComponents/FileSelect.qml
    qml/Firebird/UIComponents/PageDelegate.qml
    qml/Firebird/UIComponents/PageList.qml
    qml/Firebird/UIComponents/ConfigPages.qml
)

set(FB_DISTFILES
    resources/org.firebird.firebird-emu.desktop
    core/firebird-send
    android/AndroidManifest.xml
    android/res/values/libs.xml
    android/build.gradle
)

set(FB_LUPDATE_QML_PRESENT "")
foreach(_fb_qml IN LISTS FB_LUPDATE_QML)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${_fb_qml}")
        list(APPEND FB_LUPDATE_QML_PRESENT "${_fb_qml}")
    else()
        message(WARNING "firebird.pro lists '${_fb_qml}' for lupdate/the IDE, but the file does not exist (skipped)")
    endif()
endforeach()
set(FB_DISTFILES_PRESENT "")
foreach(_fb_dist IN LISTS FB_DISTFILES)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${_fb_dist}")
        list(APPEND FB_DISTFILES_PRESENT "${_fb_dist}")
    else()
        message(WARNING "firebird.pro lists '${_fb_dist}' as DISTFILE, but the file does not exist (skipped)")
    endif()
endforeach()

set(QT_ANDROID_PACKAGE_NAME        "org.firebird.emu" CACHE STRING "Android application package name")
set(QT_ANDROID_MIN_SDK_VERSION     "23"               CACHE STRING "Android minimum SDK version")
set(QT_ANDROID_TARGET_SDK_VERSION  "28"               CACHE STRING "Android target SDK version")

set(QML_IMPORT_PATH "${CMAKE_CURRENT_SOURCE_DIR}/qml" CACHE PATH "QML import path for Qt Creator's code model")

qt_add_executable(firebird-emu
    WIN32
    MACOSX_BUNDLE
    ${FB_SOURCES}
    ${FB_HEADERS}
    ${FB_FORMS}
    ${FB_RESOURCES}
    ${FB_LUPDATE_QML_PRESENT}
    ${FB_DISTFILES_PRESENT}
)

if(ANDROID)
    set_target_properties(firebird-emu PROPERTIES
        QT_ANDROID_PACKAGE_SOURCE_DIR   "${CMAKE_CURRENT_SOURCE_DIR}/android"
        QT_ANDROID_PACKAGE_NAME         "${QT_ANDROID_PACKAGE_NAME}"
        QT_ANDROID_MIN_SDK_VERSION      "${QT_ANDROID_MIN_SDK_VERSION}"
        QT_ANDROID_TARGET_SDK_VERSION   "${QT_ANDROID_TARGET_SDK_VERSION}"
    )
endif()

if(ANDROID)
    set(_abi "${CMAKE_ANDROID_ARCH_ABI}")

    set_target_properties(firebird-emu PROPERTIES
        QT_ANDROID_DEPLOYMENT_DEPENDENCIES
        "lib/libQt6Core_${_abi}.so;\
lib/libQt6Gui_${_abi}.so;\
lib/libQt6Widgets_${_abi}.so;\
lib/libQt6Network_${_abi}.so;\
lib/libQt6Qml_${_abi}.so;\
lib/libQt6QmlModels_${_abi}.so;\
lib/libQt6QmlWorkerScript_${_abi}.so;\
lib/libQt6Quick_${_abi}.so;\
lib/libQt6QuickWidgets_${_abi}.so;\
lib/libQt6QuickControls2_${_abi}.so;\
lib/libQt6QuickTemplates2_${_abi}.so;\
lib/libQt6QuickLayouts_${_abi}.so;\
lib/libQt6QuickControls2Impl_${_abi}.so;\
lib/libQt6OpenGL_${_abi}.so;\
lib/libQt6Svg_${_abi}.so;\
plugins/platforms/libplugins_platforms_qtforandroid_${_abi}.so"
    )
endif()

target_link_libraries(firebird-emu PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Widgets
    Qt6::QuickWidgets
    Qt6::QuickControls2
)

target_include_directories(firebird-emu PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")

target_compile_definitions(firebird-emu PRIVATE FB_VERSION=1.6)

target_compile_definitions(firebird-emu PRIVATE
    $<$<COMPILE_LANGUAGE:CXX>:QT_NO_CAST_FROM_ASCII>)

if(SUPPORT_LINUX STREQUAL "true")
    target_compile_definitions(firebird-emu PRIVATE SUPPORT_LINUX)
endif()

if(IOS OR ANDROID)
    target_compile_definitions(firebird-emu PRIVATE MOBILE_UI)
endif()

if(NOT TRANSLATION_ENABLED STREQUAL "true")
    target_compile_definitions(firebird-emu PRIVATE NO_TRANSLATION)
endif()

target_compile_options(firebird-emu PRIVATE -g -Wall -Wextra)

if(EMSCRIPTEN OR CMAKE_SYSTEM_NAME STREQUAL "Emscripten")
    target_compile_options(firebird-emu PRIVATE "-sUSE_ZLIB=1")
    target_link_options(firebird-emu PRIVATE "-sUSE_ZLIB=1")
else()
    find_package(ZLIB REQUIRED)
    target_link_libraries(firebird-emu PRIVATE ZLIB::ZLIB)
endif()

if(NOT WIN32 AND NOT (
        CMAKE_CXX_COMPILER_ID MATCHES "Clang" AND (
            CMAKE_SYSTEM_NAME STREQUAL "Linux" OR
            CMAKE_SYSTEM_NAME STREQUAL "FreeBSD" OR
            EMSCRIPTEN OR
            CMAKE_SYSTEM_NAME STREQUAL "Emscripten")))
    set_property(TARGET firebird-emu PROPERTY INTERPROCEDURAL_OPTIMIZATION TRUE)
endif()

if(NOT WIN32)
    target_compile_options(firebird-emu PRIVATE
        $<$<NOT:$<COMPILE_LANGUAGE:CXX>>:-Wa,--noexecstack>)
endif()

if(WIN32)
    target_compile_options(firebird-emu PRIVATE -mno-ms-bitfields)
endif()

if(FB_ARCH STREQUAL "arm")
    if(ANDROID)
        target_compile_options(firebird-emu PRIVATE -marm)
    else()
        target_compile_options(firebird-emu PRIVATE -march=armv7-a -marm)
    endif()
endif()

if(ANDROID)
    target_link_options(firebird-emu PRIVATE "-Wl,-Bsymbolic")
endif()

if(WIN32)
    target_link_libraries(firebird-emu PRIVATE winmm ws2_32)
endif()

if(IOS)
    target_compile_definitions(firebird-emu PRIVATE IS_IOS_BUILD)
    target_compile_options(firebird-emu PRIVATE -mno-thumb)
    target_link_options(firebird-emu PRIVATE -mno-thumb)
    set_target_properties(firebird-emu PROPERTIES
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist")
    file(GLOB FB_IOS_ICONS "${CMAKE_CURRENT_SOURCE_DIR}/resources/ios/Icon*.png")
    if(FB_IOS_ICONS)
        target_sources(firebird-emu PRIVATE ${FB_IOS_ICONS})
        set_source_files_properties(${FB_IOS_ICONS} PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
    endif()
endif()

if(APPLE AND NOT IOS)
    target_sources(firebird-emu PRIVATE resources/logo.icns)
    set_source_files_properties(resources/logo.icns PROPERTIES
        MACOSX_PACKAGE_LOCATION Resources)
    set_target_properties(firebird-emu PROPERTIES MACOSX_BUNDLE_ICON_FILE logo.icns)
endif()

set(FB_IDE_ONLY
    core/asmcode_arm.S
    core/asmcode_aarch64.S
    core/asmcode_x86.S
    core/asmcode_x86_64.S
    core/asmcode.c
    core/os/os-emscripten.c
    core/translate_arm.cpp
    core/translate_aarch64.cpp
    core/translate_x86.c
    core/translate_x86_64.c
    headless/main.cpp
    emscripten/main.cpp
)
list(TRANSFORM FB_IDE_ONLY PREPEND "${CMAKE_CURRENT_SOURCE_DIR}/")

set(FB_JIT_COMPILED_FILES "")
if(TRANSLATION_ENABLED STREQUAL "true")
    list(APPEND FB_JIT_COMPILED_FILES ${TRANSLATE})
endif()
foreach(_fb_compiled IN LISTS ASMCODE_IMPL FB_JIT_COMPILED_FILES)
    get_filename_component(_fb_compiled "${_fb_compiled}"
        ABSOLUTE BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
    list(REMOVE_ITEM FB_IDE_ONLY "${_fb_compiled}")
endforeach()
unset(_fb_compiled)
unset(FB_JIT_COMPILED_FILES)

target_sources(firebird-emu PRIVATE ${FB_IDE_ONLY})
set_source_files_properties(${FB_IDE_ONLY} PROPERTIES HEADER_FILE_ONLY TRUE)

if(UNIX AND NOT ANDROID)
    install(TARGETS firebird-emu
        RUNTIME DESTINATION bin
        BUNDLE DESTINATION bin)
    install(FILES resources/org.firebird-emus.firebird-emu.desktop
        DESTINATION share/applications)
    install(FILES resources/org.firebird-emus.firebird-emu.png
        DESTINATION share/icons/hicolor/512x512/apps)
    install(PROGRAMS core/firebird-send
        DESTINATION bin)
endif()

set(FB_TS_FILES
    i18n/de_DE.ts
    i18n/fr_FR.ts
    i18n/pl_PL.ts
    i18n/zh_CN.ts
    i18n/zh_TW.ts
    i18n/yue_HK.ts
)

add_custom_target(update_translations
    COMMAND Qt6::lupdate
        ${FB_SOURCES} ${FB_HEADERS} ${FB_FORMS} ${FB_LUPDATE_QML_PRESENT}
        -ts ${FB_TS_FILES}
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    VERBATIM
    COMMENT "Updating i18n/*.ts files (lupdate)"
)
add_custom_target(release_translations
    COMMAND Qt6::lrelease ${FB_TS_FILES}
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    VERBATIM
    COMMENT "Regenerating i18n/*.qm files (lrelease, embedded via resources.qrc)"
)

if(WIN32)
    set(FB_SHELL_ARGS cmd /c)
else()
    set(FB_SHELL_ARGS /bin/sh -c)
endif()
add_custom_target(armsnippets
    COMMAND ${FB_SHELL_ARGS}
        "arm-none-eabi-gcc -fno-leading-underscore -c '${CMAKE_CURRENT_SOURCE_DIR}/core/armsnippets.S' -o armsnippets.o -mcpu=arm926ej-s && arm-none-eabi-objcopy -O binary armsnippets.o snippets.bin && xxd -i snippets.bin > '${CMAKE_CURRENT_SOURCE_DIR}/core/armcode_bin.h' && rm armsnippets.o"
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    VERBATIM
    COMMENT "Generate the binary arm code into core/armcode_bin.h"
)
