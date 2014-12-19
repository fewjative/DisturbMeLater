ARCHS = armv7 arm64
include theos/makefiles/common.mk

BUNDLE_NAME = DisturbMeLaterSettings
DisturbMeLaterSettings_FILES = DisturbMeLaterSettings.mm
DisturbMeLaterSettings_INSTALL_PATH = /Library/PreferenceBundles
DisturbMeLaterSettings_FRAMEWORKS = UIKit
DisturbMeLaterSettings_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/DisturbMeLaterSettings.plist$(ECHO_END)

include $(THEOS_MAKE_PATH)/aggregate.mk
