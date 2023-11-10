TARGET = iphone:latest:15.0
FINALPACKAGE=1
DEBUG=0

THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ShowTouch
ShowTouch_FILES = Tweak.xm
ShowTouch_LIBRARIES = colorpicker
ShowTouch_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
	
SUBPROJECTS += showtouchprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
