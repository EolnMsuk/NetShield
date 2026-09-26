ARCHS = arm64
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless
include $(THEOS)/makefiles/common.mk
TOOL_NAME = netshield-probe
netshield-probe_FILES = main.c
netshield-probe_CFLAGS = -Wall -Wextra
netshield-probe_INSTALL_PATH = /usr/bin
include $(THEOS_MAKE_PATH)/tool.mk
