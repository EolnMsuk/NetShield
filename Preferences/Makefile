ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = NetShieldPrefs
NetShieldPrefs_FILES = NSRootListController.m
NetShieldPrefs_FRAMEWORKS = UIKit Foundation
NetShieldPrefs_PRIVATE_FRAMEWORKS = Preferences
NetShieldPrefs_CFLAGS = -fobjc-arc
NetShieldPrefs_INSTALL_PATH = /Library/PreferenceBundles
NetShieldPrefs_RESOURCE_DIRS = Resources
include $(THEOS_MAKE_PATH)/bundle.mk
