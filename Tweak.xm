#import <UIKit/UIKit.h>
#import <libcolorpicker.h>
#import <CoreFoundation/CoreFoundation.h>
#import <SpringBoard/SpringBoard.h>
#import <Foundation/Foundation.h>
#import <roothide.h>

#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

#if DEBUG == 0
#define NSLog(...)
#endif

#define kIdentifier @"com.lnx.showtouch"
#define kSettingsChangedNotification (CFStringRef)@"com.lnx.showtouch/ReloadPrefs"
#define kColorChangedNotification (CFStringRef)@"com.lnx.showtouch/colorChanged"

#define kColorPath jbroot(@"/var/mobile/Library/Preferences/com.lnx.showtouch.color.plist")
#define kSettingsPath jbroot(@"/var/mobile/Library/Preferences/com.lnx.showtouch.plist")

@interface TouchWindow : UIWindow
@property (nonatomic, strong) NSTimer *hideTimer;
@end

@implementation TouchWindow
-(BOOL)_ignoresHitTest {
  return YES;
}
-(BOOL)canBecomeKeyWindow {
    return NO;
}
@end

static CAShapeLayer *circleShape;
static UIColor *touchColor;
static BOOL enabled = YES;
static NSInteger runmode;

static CGFloat touchSize;

@interface UITouchesEvent : UIEvent
-(id)_windows;
@end

@interface UIApplication (STUIApp)
-(SBApplication*)_accessibilityFrontMostApplication;
@end

TouchWindow* makeWindow(CGRect frame)
{
    TouchWindow* w = nil;
    
    UIWindowScene* theScene=nil;
    for (UIWindowScene* windowScene in [UIApplication sharedApplication].connectedScenes) {
        NSLog(@"windowScene=%@ %@ state=%ld", windowScene, windowScene.windows, (long)windowScene.activationState);
        if(!theScene && windowScene.activationState==UISceneActivationStateForegroundInactive)
            theScene = windowScene;
        if (windowScene.activationState == UISceneActivationStateForegroundActive) {
            theScene = windowScene;
            break;
        }
    }
    w = [[TouchWindow alloc] initWithWindowScene:theScene];
    [w setFrame:frame];
    
    return w;
}

NSMutableArray* gTouchesWindows = nil;

void showtouches(UITouchesEvent* touches)
{
  NSMutableArray* currentTouches = [[[touches valueForKey:@"_allTouchesMutable"] allObjects] mutableCopy];
  NSLog(@"currentTouches=(%lu): %@", currentTouches.count, currentTouches);

  for(int i=gTouchesWindows.count; i<currentTouches.count; i++) {
    TouchWindow* window = makeWindow(CGRectZero);
    gTouchesWindows[i] = window;
  }
  for(int i=currentTouches.count; i<gTouchesWindows.count; i++) {
    TouchWindow* w = gTouchesWindows[i];
    w.hidden = YES;
  }

  for (int i = 0; i < currentTouches.count; i++) {

    UITouch* touch = currentTouches[i];
    TouchWindow* window = gTouchesWindows[i];

    NSLog(@"touch.window[%d]=%d %ld/%ld,%ld/%ld, %@", i,touch.window.isHidden, 
    touch.window.rootViewController.interfaceOrientation, touch.window.windowScene.interfaceOrientation, 
    window.rootViewController.interfaceOrientation, window.windowScene.interfaceOrientation, 
    touch.window);
    
    BOOL shouldShowTouch = ![touch.window isKindOfClass:%c(ICSSecureWindow)];

    if (!shouldShowTouch) {
      NSLog(@"shouldShowTouch=%d", shouldShowTouch);
      window.hidden = YES;
      continue;
    }

    CGRect screen = [UIScreen mainScreen].nativeBounds;
    screen.size.width /= [UIScreen mainScreen].scale;
    screen.size.height /= [UIScreen mainScreen].scale;
    CGPoint touchLocation = [[touch valueForKey:@"_locationInWindow"] CGPointValue];
    NSLog(@"touchLocation=%@, screen=%@", NSStringFromCGPoint(touchLocation), NSStringFromCGRect(screen));

    window.bounds = CGRectMake(touchLocation.x, touchLocation.y, touchSize, touchSize);
    window.center = CGPointMake(touchLocation.x, touchLocation.y);
    window.windowLevel = UIWindowLevelStatusBar + 100000;
    window.backgroundColor = touchColor;
    window.layer.cornerRadius = touchSize / 2;
    window.userInteractionEnabled = NO;
    window.hidden = NO;
  }
}

%hook UITouchesEvent

-(void)_setHIDEvent:(id)arg1 {
  // NSLog(@"_setHIDEvent: %@", self);
  // NSLog(@"arg1=%@", arg1);
  // NSLog(@"_windows=%@", [self _windows]);
  
  if (enabled) {
    dispatch_async(dispatch_get_main_queue(), ^{
      showtouches(self);
    });
  }

  %orig;
}
%end

static void reloadColorPrefs() {
	NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:kColorPath];
	touchColor = [preferences objectForKey:@"touchColor"] ? LCPParseColorString([preferences objectForKey:@"touchColor"], @"#FFFFFF") : [UIColor redColor];
}

bool prefsinited=false;
static void reloadPrefs() {
	CFPreferencesAppSynchronize((CFStringRef)kIdentifier);

	NSDictionary *prefs = nil;
	if ([NSHomeDirectory() isEqualToString:@"/var/mobile"]) {
		CFArrayRef keyList = CFPreferencesCopyKeyList((CFStringRef)kIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
		if (keyList != nil) {
			prefs = (NSDictionary *)CFBridgingRelease(CFPreferencesCopyMultiple(keyList, (CFStringRef)kIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
			if (prefs == nil)
				prefs = [NSDictionary dictionary];
			CFRelease(keyList);
		}
	} else {
		prefs = [NSDictionary dictionaryWithContentsOfFile:kSettingsPath];
	}

	runmode = [prefs objectForKey:@"runmode"] ? [[prefs objectForKey:@"runmode"] integerValue] : 1; //always show by default
  touchSize = [prefs objectForKey:@"touchSize"] ? [[prefs objectForKey:@"touchSize"] floatValue] : 30;

  switch(runmode) {
    case 0:
      enabled = NO;
      break;

    case 1:
      enabled = YES;
      break;

    case 2:
      if(prefsinited) 
        enabled = UIScreen.mainScreen.captured; //hang forever in ctor in springboard
      else 
        enabled = NO; //disabled by default
      break;
  }
}

%ctor {
	reloadPrefs();
	reloadColorPrefs();
  prefsinited = true;
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)reloadPrefs, kSettingsChangedNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)reloadColorPrefs, kColorChangedNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
  NSLog(@"ShowTouch loading");

  [[NSNotificationCenter defaultCenter] addObserverForName: UIScreenCapturedDidChangeNotification
      object: nil
      queue: nil
      usingBlock: ^ (NSNotification * notification) {
        if(runmode == 2) enabled = UIScreen.mainScreen.captured;
  }];

  gTouchesWindows = [[NSMutableArray alloc] init];
}
