cmake_minimum_required( VERSION 3.13...99.99)

project( MulleObjCPosixFoundation C)


### mulle-sde environment

# add cmake module paths to search path
list( INSERT CMAKE_MODULE_PATH 0 "${PROJECT_SOURCE_DIR}/cmake/share")
list( INSERT CMAKE_MODULE_PATH 0 "${PROJECT_SOURCE_DIR}/cmake/reflect")
list( INSERT CMAKE_MODULE_PATH 0 "${PROJECT_SOURCE_DIR}/cmake")

include( Environment)

include( Files)

### Platform gate
#
# This project only provides Posix code, so it builds everywhere except
# Windows. On Windows it must still configure harmlessly, so it can sit in a
# cross-platform craft order (see REPOS). Clearing the sources makes
# Library.cmake emit an empty INTERFACE library: nothing is compiled, linked or
# installed, but the target still exists for a linking consumer.
#
if( WIN32)
   message( STATUS "${PROJECT_NAME}: not Posix, building to nothing")
   set( SOURCES)
   set( STAGE2_SOURCES)
endif()

### Library

if( HEADERS_PHASE)
   install( FILES ${INSTALL_PUBLIC_HEADERS}  DESTINATION "include/MulleObjCPosixFoundation")
   install( FILES ${INSTALL_PRIVATE_HEADERS} DESTINATION "include/MulleObjCPosixFoundation")
   install( FILES ${INSTALL_CMAKE_INCLUDES}          DESTINATION "include/MulleObjCPosixFoundation/cmake")

   # short cut out
   if( NOT COMPILE_PHASE AND NOT LINK_PHASE)
      return()
   endif()
endif()

if( LINK_PHASE)
   include( Dependencies OPTIONAL)
endif()

include( Library)
include( InstallLibrary)
include( FinalOutput OPTIONAL)
