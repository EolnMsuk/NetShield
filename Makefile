ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NetShield
NetShield_FILES = Sources/Tweak.xm Sources/Client.mm Sources/Broker.mm Sources/Dashboard.mm Sources/IPC.mm Sources/AdditionalHooks.mm
NetShield_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter
NetShield_CCFLAGS = -std=c++17
NetShield_FRAMEWORKS = Foundation UIKit
NetShield_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += Preferences
ifeq ($(BUILD_PROBE),1)
SUBPROJECTS += Tests/Probe
endif
include $(THEOS_MAKE_PATH)/aggregate.mk
