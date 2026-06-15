TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = TikTok

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = TikTokHelper

TikTokHelper_FILES = TikTokHelper.m
TikTokHelper_CFLAGS = -fobjc-arc
TikTokHelper_FRAMEWORKS = Foundation UIKit CoreData
TikTokHelper_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/library.mk
