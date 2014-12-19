ARCHS = armv7 arm64
include theos/makefiles/common.mk

TWEAK_NAME = DisturbMeLater
DisturbMeLater_FILES = Tweak.xm
DisturbMeLater_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
DisturbMeLater_PRIVATE_FRAMEWORKS = PersistentConnection
DisturbMeLater_CFLAGS = -Wno-error
export GO_EASY_ON_ME := 1
include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += DisturbMeLaterSettings
include $(THEOS_MAKE_PATH)/aggregate.mk

before-stage::
	find . -name ".DS_STORE" -delete
after-install::
	install.exec "killall -9 backboardd"
