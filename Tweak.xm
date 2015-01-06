#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <PersistentConnection/PCPersistentTimer.h>
#import <UIKit/UIKit.h>
#import <substrate.h>

#define SYS_VER_GREAT_OR_EQUAL(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:64] != NSOrderedAscending)

@interface SBUIControlCenterButton : UIButton
- (void)_updateSelected:(BOOL)selected highlighted:(BOOL)highlighted;
@end

@interface SBControlCenterButton : SBUIControlCenterButton
@property(copy, nonatomic) NSString *identifier;
@end

@interface SBCCQuickLaunchSectionController
- (NSString *)_bundleIDForButton:(SBControlCenterButton *)button;
- (void)CCFLLInit:(SBControlCenterButton *)button;
@end

@interface CCTControlCenterButton : SBUIControlCenterButton
- (SBCCQuickLaunchSectionController *)delegate;
- (NSString *)identifier;
@end

@interface SBControlCenterSettingsSectionSettings
+(id)buttonModuleClasses;
@end

@interface SBCCDoNotDisturbSetting
+(id)identifier;
+(id)displayName;
-(BOOL)_toggleState;
-(void)activate;
-(void)deactivate;
@end

@interface SBControlCenterGrabberView : UIView
-(void)presentStatusUpdate:(id)obj;
@end

@interface SBCCButtonModule
-(id)identifier;
@end

@interface SBLockScreenManager : NSObject
+ (id)sharedInstance;
- (BOOL)isUILocked;
@end

static PCPersistentTimer *dndTimer;
static UIDatePicker * pickerView;
static SBCCButtonModule * bm;
static bool changeStr = NO;
static NSTimeInterval timeInterval;
static BOOL enabled = NO;
static BOOL fsInstalled = NO;
static BOOL polusInstalled = NO;
static BOOL auxoInstalled = NO;
static BOOL multiCenter = NO;
//store date and time to compare just in case the DnD doesnt turb back off because they turned their phone off.

%hook SpringBoard

-(void)applicationDidFinishLaunching:(id)application {
	
	%orig;
}

%end

%hook SBCCButtonController

-(SBCCButtonModule*)module{

	SBCCButtonModule * orig = %orig;
	if([[orig identifier] isEqualToString:@"doNotDisturb"])
	{
		NSLog(@"[DML]Found DND button module.");
		bm = orig;
	}
	return orig;
}

%end

%hook SBCCDoNotDisturbSetting

-(id)statusUpdate
{
	changeStr = YES;
	int state = [bm state];

	if(state==0 && [dndTimer isValid])
	{
		NSLog(@"[DML]Invalidating timer, DND toggled off while timer exists.");
		[dndTimer invalidate];
		dndTimer = nil;
	}

	id orig = %orig;
	return orig;
}

%end

%hook SBControlCenterStatusUpdate

-(id)popStatusString
{
	NSString * orig = %orig;

	if(changeStr && [dndTimer isValid])
	{
		NSString * baseStr = @"DND Will Turn Off After: ";

		NSInteger seconds = ((NSInteger)timeInterval)%60;
		NSInteger minutes = ((NSInteger)timeInterval/60)%60;
		NSInteger hours = ((NSInteger)timeInterval)/3600;

		NSString * timeStr = [NSString stringWithFormat:@"%02ld:%02ld:%02ld",(long)hours,(long)minutes,(long)seconds];
		NSString *combinedStr = [NSString stringWithFormat:@"%@%@",baseStr,timeStr];
		changeStr = NO;
		return combinedStr;
	}
	else
	{
		changeStr = NO;
		return orig;
	}
}

%end

%hook SBControlCenterButton

//Display the time the user set
%new - (void)displayCustomText
{
	UIView * view = [[[self superview] superview] superview];
	SBControlCenterGrabberView * gv = MSHookIvar<SBControlCenterGrabberView*>(view,"_grabberView");

	NSString * baseStr = @"DND Will Turn Off After: ";
	NSInteger seconds = ((NSInteger)timeInterval)%60;
	NSInteger minutes = ((NSInteger)timeInterval/60)%60;
	NSInteger hours = ((NSInteger)timeInterval)/3600;

	NSString * timeStr = [NSString stringWithFormat:@"%02ld:%02ld:%02ld",(long)hours,(long)minutes,(long)seconds];
	NSString *combinedStr = [NSString stringWithFormat:@"%@%@",baseStr,timeStr];

	[gv presentStatusUpdate:[%c(SBControlCenterStatusUpdate) statusUpdateWithString:combinedStr reason:@"doNotDisturb"]];
}

//Display the timer will be removed
%new - (void)displayCustomText:(NSString*)str
{
	UIView * view = [[[self superview] superview] superview];
	SBControlCenterGrabberView * gv = MSHookIvar<SBControlCenterGrabberView*>(view,"_grabberView");
	[gv presentStatusUpdate:[%c(SBControlCenterStatusUpdate) statusUpdateWithString:str reason:@"doNotDisturb"]];
}

//Function for when our timer is fired
%new - (void)fireAway {
	NSLog(@"[DisturbMeLater] Sending fire message from dndTimer...");

	//only change the state if it is currently active
	if([bm state]==1)
	{
		[bm _toggleState];
	}
}

//Any method will work to add the long press gesture recognizer to the DoNotDisturb button.
-(BOOL)isEnabled
{
	bool orig = %orig;

	if ([[self identifier] isEqualToString:@"doNotDisturb"] || [[self identifier] isEqualToString:@"Do Not Disturb"])
	{
	    UILongPressGestureRecognizer * longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressTap:)];
		[self addGestureRecognizer:longPress];
		[longPress release];
	}

	return orig;
}

%new -(void)alertView:(UIAlertView*)alertView clickedButtonAtIndex:(NSInteger)buttonIndex{
	if(alertView.tag==101)
	{
		//AlertView for when we long press and DND is NOT enabled
		if(buttonIndex==0)
		{
			//do nothing
		}
		else
		{
			timeInterval = (NSTimeInterval)pickerView.countDownDuration;
			NSInteger seconds = (NSInteger) timeInterval;

			NSLog(@"[DML]User would like to set a timer for DND lasting %d seconds.",seconds);

			if(!dndTimer)
			{
				dndTimer = [[PCPersistentTimer alloc] initWithTimeInterval:seconds serviceIdentifier:@"com.joshdoctors.disturbmelater" target:self selector:@selector(fireAway) userInfo:nil];
				[dndTimer scheduleInRunLoop:[NSRunLoop mainRunLoop]];
			}
			else
			{
				[dndTimer invalidate];
				dndTimer = nil;
				dndTimer = [[PCPersistentTimer alloc] initWithTimeInterval:seconds serviceIdentifier:@"com.joshdoctors.disturbmelater" target:self selector:@selector(fireAway) userInfo:nil];
				[dndTimer scheduleInRunLoop:[NSRunLoop mainRunLoop]];
			}

			//Timer is not activated(prior to our activation now) but DND is currently enabled
			if([bm state]!=1)//
				[self sendActionsForControlEvents:64];//simulate the the button press(64 = touchUpInside) so we get the fancy visual effects
			else
			{
				SBLockScreenManager *lockscreenManager = (SBLockScreenManager *)[objc_getClass("SBLockScreenManager") sharedInstance];

				if(lockscreenManager.isUILocked)
				{
					[self displayCustomText];
				}
				else
				{
					if(!multiCenter)
						[self displayCustomText];
				}
			}
		}

		[pickerView release];
		pickerView = nil;
	}
	else if(alertView.tag==202)
	{
		//AlertView for when we long press and DND IS enabled
		if(buttonIndex==0)
		{
			//do nothing
		}
		else if(buttonIndex==1)
		{
			NSLog(@"[DML]User would like to readjust the timer.");

			UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Do Not Disturb"
			message:@"When should Do No Disturb turn off?"
			delegate:self
		    cancelButtonTitle:@"Cancel"
		    otherButtonTitles:@"Set",nil];

		    pickerView = [[UIDatePicker alloc] initWithFrame:CGRectMake(10,alert.bounds.size.height,320,216)];
		    pickerView.datePickerMode = UIDatePickerModeCountDownTimer;
		    
		    [alert setValue:pickerView forKey:@"accessoryView"];
		    alert.bounds = CGRectMake(0,0,320 + 20, alert.bounds.size.height + 216 + 20);
		    alert.tag = 101;
		    [alert show];

		    [alert release];
		}
		else if(buttonIndex==2)
		{
			NSLog(@"[DML]User would like to remove the timer. DND will remain on however.");
			[dndTimer invalidate];
			dndTimer = nil;

			SBLockScreenManager *lockscreenManager = (SBLockScreenManager *)[objc_getClass("SBLockScreenManager") sharedInstance];

			if(lockscreenManager.isUILocked)
			{
				[self displayCustomText:@"DND Removed Timer"];
			}
			else
			{
				if(!multiCenter)
					[self displayCustomText:@"DND Removed Timer"];
			}				
		}
	}
}

%new - (void)longPressTap:(UILongPressGestureRecognizer*)sender
{
	NSLog(@"Held - no special tweaks.");
	if(enabled)
	{
		if(!polusInstalled)
		{
			if(sender.state==UIGestureRecognizerStateEnded)
			{
				NSLog(@"[DML]Long press detected.");
				bool active = [bm state];
				NSLog(@"[DML]DND active?: %d",active);

				if(active)
				{
					//if we have an active timer
					if([dndTimer isValid])
					{	
						NSLog(@"[DML]DND is Active and we have an existing timer.");	
						UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Do Not Disturb"
					    message:nil
					    delegate:self
					    cancelButtonTitle:@"Cancel"
					    otherButtonTitles:@"Readjust Timer",@"Remove Timer",nil];

					    alert.tag = 202;
					    [alert show];

					    [alert release];
					}
					else
					{
						//if we don't have an active timer
						NSLog(@"[DML]DND is Active and we do NOT have an existing timer.");	
						UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Do Not Disturb"
					    message:@"When should Do No Disturb turn off?"
					    delegate:self
					    cancelButtonTitle:@"Cancel"
					    otherButtonTitles:@"Set",nil];

					    pickerView = [[UIDatePicker alloc] initWithFrame:CGRectMake(10,alert.bounds.size.height,320,216)];
					    pickerView.datePickerMode = UIDatePickerModeCountDownTimer;
					    
					    [alert setValue:pickerView forKey:@"accessoryView"];
					    alert.bounds = CGRectMake(0,0,320 + 20, alert.bounds.size.height + 216 + 20);
					    alert.tag = 101;
					    [alert show];

					    [alert release];
					}
				}
				else
				{
					NSLog(@"[DML]DND is NOT Active.");

					UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Do Not Disturb"
				    message:@"When should Do No Disturb turn off?"
				    delegate:self
				    cancelButtonTitle:@"Cancel"
				    otherButtonTitles:@"Set",nil];

				    pickerView = [[UIDatePicker alloc] initWithFrame:CGRectMake(10,alert.bounds.size.height,320,216)];
				    pickerView.datePickerMode = UIDatePickerModeCountDownTimer;
				    
				    [alert setValue:pickerView forKey:@"accessoryView"];
				    alert.bounds = CGRectMake(0,0,320 + 20, alert.bounds.size.height + 216 + 20);
				    alert.tag = 101;
				    [alert show];

				    [alert release];
				}
			}
		}
	}
}

%end

%hook FSSwitchButton

-(void)_held
{
	NSLog(@"Held - FSSwitchButton");

	NSString * identifier = MSHookIvar<NSString*>(self,"switchIdentifier");
	if(!enabled || ![identifier isEqualToString:@"com.a3tweaks.switch.do-not-disturb"])
	{
		%orig;
	}
	else
	{
		NSLog(@"[DML]Long press detected.");
		bool active = [bm state];
		NSLog(@"[DML]DND active?: %d",active);

		if(active)
		{
			//if we have an active timer
			if([dndTimer isValid])
			{	
				NSLog(@"[DML]DND is Active and we have an existing timer.");	
				UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Do Not Disturb"
			    message:nil
			    delegate:self
			    cancelButtonTitle:@"Cancel"
			    otherButtonTitles:@"Readjust Timer",@"Remove Timer",nil];

			    alert.tag = 202;
			    [alert show];

			    [alert release];
			}
			else
			{
				//if we don't have an active timer
				NSLog(@"[DML]DND is Active and we do NOT have an existing timer.");	
				UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Do Not Disturb"
			    message:@"When should Do No Disturb turn off?"
			    delegate:self
			    cancelButtonTitle:@"Cancel"
			    otherButtonTitles:@"Set",nil];

			    pickerView = [[UIDatePicker alloc] initWithFrame:CGRectMake(10,alert.bounds.size.height,320,216)];
			    pickerView.datePickerMode = UIDatePickerModeCountDownTimer;
			    
			    [alert setValue:pickerView forKey:@"accessoryView"];
			    alert.bounds = CGRectMake(0,0,320 + 20, alert.bounds.size.height + 216 + 20);
			    alert.tag = 101;
			    [alert show];

			    [alert release];
			}
		}
		else
		{
			NSLog(@"[DML]DND is NOT Active.");

			UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Do Not Disturb"
		    message:@"When should Do No Disturb turn off?"
		    delegate:self
		    cancelButtonTitle:@"Cancel"
		    otherButtonTitles:@"Set",nil];

		    pickerView = [[UIDatePicker alloc] initWithFrame:CGRectMake(10,alert.bounds.size.height,320,216)];
		    pickerView.datePickerMode = UIDatePickerModeCountDownTimer;
		    
		    [alert setValue:pickerView forKey:@"accessoryView"];
		    alert.bounds = CGRectMake(0,0,320 + 20, alert.bounds.size.height + 216 + 20);
		    alert.tag = 101;
		    [alert show];

		    [alert release];
		}
	}

}

%new -(void)alertView:(UIAlertView*)alertView clickedButtonAtIndex:(NSInteger)buttonIndex{
	if(alertView.tag==101)
	{
		//AlertView for when we long press and DND is NOT enabled
		if(buttonIndex==0)
		{
			//do nothing
		}
		else
		{
			timeInterval = (NSTimeInterval)pickerView.countDownDuration;
			NSInteger seconds = (NSInteger) timeInterval;

			NSLog(@"[DML]User would like to set a timer for DND lasting %d seconds.",seconds);

			if(!dndTimer)
			{
				dndTimer = [[PCPersistentTimer alloc] initWithTimeInterval:seconds serviceIdentifier:@"com.joshdoctors.disturbmelater" target:self selector:@selector(fireAway) userInfo:nil];
				[dndTimer scheduleInRunLoop:[NSRunLoop mainRunLoop]];
			}
			else
			{
				[dndTimer invalidate];
				dndTimer = nil;
				dndTimer = [[PCPersistentTimer alloc] initWithTimeInterval:seconds serviceIdentifier:@"com.joshdoctors.disturbmelater" target:self selector:@selector(fireAway) userInfo:nil];
				[dndTimer scheduleInRunLoop:[NSRunLoop mainRunLoop]];
			}

			//Timer is not activated(prior to our activation now) but we DND is currently enabled
			if([bm state]!=1)//
			{
				[self sendActionsForControlEvents:64];//simulate the the button press(64 = touchUpInside) so we get the fancy visual effects
				[self displayCustomText];
			}
			else
			{
				[self displayCustomText];
			}
		}

		[pickerView release];
		pickerView = nil;
	}
	else if(alertView.tag==202)
	{
		//AlertView for when we long press and DND IS enabled
		if(buttonIndex==0)
		{
			//do nothing
		}
		else if(buttonIndex==1)
		{
			NSLog(@"[DML]User would like to readjust the timer.");

			UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Do Not Disturb"
			message:@"When should Do No Disturb turn off?"
			delegate:self
		    cancelButtonTitle:@"Cancel"
		    otherButtonTitles:@"Set",nil];

		    pickerView = [[UIDatePicker alloc] initWithFrame:CGRectMake(10,alert.bounds.size.height,320,216)];
		    pickerView.datePickerMode = UIDatePickerModeCountDownTimer;
		    
		    [alert setValue:pickerView forKey:@"accessoryView"];
		    alert.bounds = CGRectMake(0,0,320 + 20, alert.bounds.size.height + 216 + 20);
		    alert.tag = 101;
		    [alert show];

		    [alert release];
		}
		else if(buttonIndex==2)
		{
			NSLog(@"[DML]User would like to remove the timer. DND will remain on however.");
			[dndTimer invalidate];
			dndTimer = nil;
			[self displayCustomText:@"DND Removed Timer"];
		}
	}
}

%new - (void)displayCustomText
{
	UIView * view = [[[self superview] superview] superview];
	SBControlCenterGrabberView * gv = MSHookIvar<SBControlCenterGrabberView*>(view,"_grabberView");

	NSString * baseStr = @"DND Will Turn Off After: ";
	NSInteger seconds = ((NSInteger)timeInterval)%60;
	NSInteger minutes = ((NSInteger)timeInterval/60)%60;
	NSInteger hours = ((NSInteger)timeInterval)/3600;

	NSString * timeStr = [NSString stringWithFormat:@"%02ld:%02ld:%02ld",(long)hours,(long)minutes,(long)seconds];
	NSString *combinedStr = [NSString stringWithFormat:@"%@%@",baseStr,timeStr];

	[gv presentStatusUpdate:[%c(SBControlCenterStatusUpdate) statusUpdateWithString:combinedStr reason:@"doNotDisturb"]];
}

//Display the timer will be removed
%new - (void)displayCustomText:(NSString*)str
{
	UIView * view = [[[self superview] superview] superview];
	SBControlCenterGrabberView * gv = MSHookIvar<SBControlCenterGrabberView*>(view,"_grabberView");
	[gv presentStatusUpdate:[%c(SBControlCenterStatusUpdate) statusUpdateWithString:str reason:@"doNotDisturb"]];
}

//Function for when our timer is fired
%new - (void)fireAway {
	NSLog(@"[DisturbMeLater] Sending fire message from dndTimer...");

	//only change the state if it is currently active
	if([bm state]==1)
	{
		[bm _toggleState];
	}
}

%end

%hook _FSSwitchButton

-(void)_held
{
	NSLog(@"Held - _FSSwitchButton");

	NSString * identifier = MSHookIvar<NSString*>(self,"switchIdentifier");
	if(!enabled || ![identifier isEqualToString:@"com.a3tweaks.switch.do-not-disturb"])
	{
		%orig;
	}
	else
	{
		NSLog(@"[DML]Long press detected.");
		bool active = [bm state];
		NSLog(@"[DML]DND active?: %d",active);

		if(active)
		{
			//if we have an active timer
			if([dndTimer isValid])
			{	
				NSLog(@"[DML]DND is Active and we have an existing timer.");	
				UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Do Not Disturb"
			    message:nil
			    delegate:self
			    cancelButtonTitle:@"Cancel"
			    otherButtonTitles:@"Readjust Timer",@"Remove Timer",nil];

			    alert.tag = 202;
			    [alert show];

			    [alert release];
			}
			else
			{
				//if we don't have an active timer
				NSLog(@"[DML]DND is Active and we do NOT have an existing timer.");	
				UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Do Not Disturb"
			    message:@"When should Do No Disturb turn off?"
			    delegate:self
			    cancelButtonTitle:@"Cancel"
			    otherButtonTitles:@"Set",nil];

			    pickerView = [[UIDatePicker alloc] initWithFrame:CGRectMake(10,alert.bounds.size.height,320,216)];
			    pickerView.datePickerMode = UIDatePickerModeCountDownTimer;
			    
			    [alert setValue:pickerView forKey:@"accessoryView"];
			    alert.bounds = CGRectMake(0,0,320 + 20, alert.bounds.size.height + 216 + 20);
			    alert.tag = 101;
			    [alert show];

			    [alert release];
			}
		}
		else
		{
			NSLog(@"[DML]DND is NOT Active.");

			UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Do Not Disturb"
		    message:@"When should Do No Disturb turn off?"
		    delegate:self
		    cancelButtonTitle:@"Cancel"
		    otherButtonTitles:@"Set",nil];

		    pickerView = [[UIDatePicker alloc] initWithFrame:CGRectMake(10,alert.bounds.size.height,320,216)];
		    pickerView.datePickerMode = UIDatePickerModeCountDownTimer;
		    
		    [alert setValue:pickerView forKey:@"accessoryView"];
		    alert.bounds = CGRectMake(0,0,320 + 20, alert.bounds.size.height + 216 + 20);
		    alert.tag = 101;
		    [alert show];

		    [alert release];
		}
	}

}

%new -(void)alertView:(UIAlertView*)alertView clickedButtonAtIndex:(NSInteger)buttonIndex{
	if(alertView.tag==101)
	{
		//AlertView for when we long press and DND is NOT enabled
		if(buttonIndex==0)
		{
			//do nothing
		}
		else
		{
			timeInterval = (NSTimeInterval)pickerView.countDownDuration;
			NSInteger seconds = (NSInteger) timeInterval;

			NSLog(@"[DML]User would like to set a timer for DND lasting %d seconds.",seconds);

			if(!dndTimer)
			{
				dndTimer = [[PCPersistentTimer alloc] initWithTimeInterval:seconds serviceIdentifier:@"com.joshdoctors.disturbmelater" target:self selector:@selector(fireAway) userInfo:nil];
				[dndTimer scheduleInRunLoop:[NSRunLoop mainRunLoop]];
			}
			else
			{
				[dndTimer invalidate];
				dndTimer = nil;
				dndTimer = [[PCPersistentTimer alloc] initWithTimeInterval:seconds serviceIdentifier:@"com.joshdoctors.disturbmelater" target:self selector:@selector(fireAway) userInfo:nil];
				[dndTimer scheduleInRunLoop:[NSRunLoop mainRunLoop]];
			}

			//Timer is not activated(prior to our activation now) but we DND is currently enabled
			if([bm state]!=1)//
			{
				[self sendActionsForControlEvents:64];//simulate the the button press(64 = touchUpInside) so we get the fancy visual effects
				[self displayCustomText];
			}
			else
			{
				[self displayCustomText];
			}
		}

		[pickerView release];
		pickerView = nil;
	}
	else if(alertView.tag==202)
	{
		//AlertView for when we long press and DND IS enabled
		if(buttonIndex==0)
		{
			//do nothing
		}
		else if(buttonIndex==1)
		{
			NSLog(@"[DML]User would like to readjust the timer.");

			UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Do Not Disturb"
			message:@"When should Do No Disturb turn off?"
			delegate:self
		    cancelButtonTitle:@"Cancel"
		    otherButtonTitles:@"Set",nil];

		    pickerView = [[UIDatePicker alloc] initWithFrame:CGRectMake(10,alert.bounds.size.height,320,216)];
		    pickerView.datePickerMode = UIDatePickerModeCountDownTimer;
		    
		    [alert setValue:pickerView forKey:@"accessoryView"];
		    alert.bounds = CGRectMake(0,0,320 + 20, alert.bounds.size.height + 216 + 20);
		    alert.tag = 101;
		    [alert show];

		    [alert release];
		}
		else if(buttonIndex==2)
		{
			NSLog(@"[DML]User would like to remove the timer. DND will remain on however.");
			[dndTimer invalidate];
			dndTimer = nil;
			[self displayCustomText:@"DND Removed Timer"];
		}
	}
}

%new - (void)displayCustomText
{
	UIView * view = [[[self superview] superview] superview];
	SBControlCenterGrabberView * gv = MSHookIvar<SBControlCenterGrabberView*>(view,"_grabberView");

	NSString * baseStr = @"DND Will Turn Off After: ";
	NSInteger seconds = ((NSInteger)timeInterval)%60;
	NSInteger minutes = ((NSInteger)timeInterval/60)%60;
	NSInteger hours = ((NSInteger)timeInterval)/3600;

	NSString * timeStr = [NSString stringWithFormat:@"%02ld:%02ld:%02ld",(long)hours,(long)minutes,(long)seconds];
	NSString *combinedStr = [NSString stringWithFormat:@"%@%@",baseStr,timeStr];

	[gv presentStatusUpdate:[%c(SBControlCenterStatusUpdate) statusUpdateWithString:combinedStr reason:@"doNotDisturb"]];
}

//Display the timer will be removed
%new - (void)displayCustomText:(NSString*)str
{
	UIView * view = [[[self superview] superview] superview];
	SBControlCenterGrabberView * gv = MSHookIvar<SBControlCenterGrabberView*>(view,"_grabberView");
	[gv presentStatusUpdate:[%c(SBControlCenterStatusUpdate) statusUpdateWithString:str reason:@"doNotDisturb"]];
}

//Function for when our timer is fired
%new - (void)fireAway {
	NSLog(@"[DisturbMeLater] Sending fire message from dndTimer...");

	//only change the state if it is currently active
	if([bm state]==1)
	{
		[bm _toggleState];
	}
}

%end

%hook PLFlipswitchButton

-(void)heldDown:(UILongPressGestureRecognizer*)sender
{
	NSLog(@"heldDown - PLFlipswitchButton");
	NSString * identifier = MSHookIvar<NSString*>(self,"_switchID");
	if(!enabled || ![identifier isEqualToString:@"com.a3tweaks.switch.do-not-disturb"])
	{
		%orig;
	}
	else
	{
		if(!(sender.state==UIGestureRecognizerStateCancelled || sender.state==UIGestureRecognizerStateEnded))
		{
			return;
		}

		NSLog(@"[DML]Long press detected.");
		bool active = [bm state];
		NSLog(@"[DML]DND active?: %d",active);

		if(active)
		{
			//if we have an active timer
			if([dndTimer isValid])
			{	
				NSLog(@"[DML]DND is Active and we have an existing timer.");	
				UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Do Not Disturb"
			    message:nil
			    delegate:self
			    cancelButtonTitle:@"Cancel"
			    otherButtonTitles:@"Readjust Timer",@"Remove Timer",nil];

			    alert.tag = 202;
			    [alert show];

			    [alert release];
			}
			else
			{
				//if we don't have an active timer
				NSLog(@"[DML]DND is Active and we do NOT have an existing timer.");	
				UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Do Not Disturb"
			    message:@"When should Do No Disturb turn off?"
			    delegate:self
			    cancelButtonTitle:@"Cancel"
			    otherButtonTitles:@"Set",nil];

			    pickerView = [[UIDatePicker alloc] initWithFrame:CGRectMake(10,alert.bounds.size.height,320,216)];
			    pickerView.datePickerMode = UIDatePickerModeCountDownTimer;
			    
			    [alert setValue:pickerView forKey:@"accessoryView"];
			    alert.bounds = CGRectMake(0,0,320 + 20, alert.bounds.size.height + 216 + 20);
			    alert.tag = 101;
			    [alert show];

			    [alert release];
			}
		}
		else
		{
			NSLog(@"[DML]DND is NOT Active.");

			UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Do Not Disturb"
		    message:@"When should Do No Disturb turn off?"
		    delegate:self
		    cancelButtonTitle:@"Cancel"
		    otherButtonTitles:@"Set",nil];

		    pickerView = [[UIDatePicker alloc] initWithFrame:CGRectMake(10,alert.bounds.size.height,320,216)];
		    pickerView.datePickerMode = UIDatePickerModeCountDownTimer;
		    
		    [alert setValue:pickerView forKey:@"accessoryView"];
		    alert.bounds = CGRectMake(0,0,320 + 20, alert.bounds.size.height + 216 + 20);
		    alert.tag = 101;
		    [alert show];

		    [alert release];
		}
	}

}

%new -(void)alertView:(UIAlertView*)alertView clickedButtonAtIndex:(NSInteger)buttonIndex{
	if(alertView.tag==101)
	{
		//AlertView for when we long press and DND is NOT enabled
		if(buttonIndex==0)
		{
			//do nothing
		}
		else
		{
			timeInterval = (NSTimeInterval)pickerView.countDownDuration;
			NSInteger seconds = (NSInteger) timeInterval;

			NSLog(@"[DML]User would like to set a timer for DND lasting %d seconds.",seconds);

			if(!dndTimer)
			{
				dndTimer = [[PCPersistentTimer alloc] initWithTimeInterval:seconds serviceIdentifier:@"com.joshdoctors.disturbmelater" target:self selector:@selector(fireAway) userInfo:nil];
				[dndTimer scheduleInRunLoop:[NSRunLoop mainRunLoop]];
			}
			else
			{
				[dndTimer invalidate];
				dndTimer = nil;
				dndTimer = [[PCPersistentTimer alloc] initWithTimeInterval:seconds serviceIdentifier:@"com.joshdoctors.disturbmelater" target:self selector:@selector(fireAway) userInfo:nil];
				[dndTimer scheduleInRunLoop:[NSRunLoop mainRunLoop]];
			}

			//Timer is not activated(prior to our activation now) but we DND is currently enabled
			if([bm state]!=1)//
			{
				[self sendActionsForControlEvents:64];//simulate the the button press(64 = touchUpInside) so we get the fancy visual effects
				[self displayCustomText];
			}
			else
			{
				[self displayCustomText];
			}
		}

		[pickerView release];
		pickerView = nil;
	}
	else if(alertView.tag==202)
	{
		//AlertView for when we long press and DND IS enabled
		if(buttonIndex==0)
		{
			//do nothing
		}
		else if(buttonIndex==1)
		{
			NSLog(@"[DML]User would like to readjust the timer.");

			UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Do Not Disturb"
			message:@"When should Do No Disturb turn off?"
			delegate:self
		    cancelButtonTitle:@"Cancel"
		    otherButtonTitles:@"Set",nil];

		    pickerView = [[UIDatePicker alloc] initWithFrame:CGRectMake(10,alert.bounds.size.height,320,216)];
		    pickerView.datePickerMode = UIDatePickerModeCountDownTimer;
		    
		    [alert setValue:pickerView forKey:@"accessoryView"];
		    alert.bounds = CGRectMake(0,0,320 + 20, alert.bounds.size.height + 216 + 20);
		    alert.tag = 101;
		    [alert show];

		    [alert release];
		}
		else if(buttonIndex==2)
		{
			NSLog(@"[DML]User would like to remove the timer. DND will remain on however.");
			[dndTimer invalidate];
			dndTimer = nil;
			[self displayCustomText:@"DND Removed Timer"];
		}
	}
}

%new - (void)displayCustomText
{
	UIView * view = [[[[self superview] superview] superview] superview];

	NSLog(@"View: %@",view);
	SBControlCenterGrabberView * gv = MSHookIvar<SBControlCenterGrabberView*>(view,"_grabberView");

	NSString * baseStr = @"DND Will Turn Off After: ";
	NSInteger seconds = ((NSInteger)timeInterval)%60;
	NSInteger minutes = ((NSInteger)timeInterval/60)%60;
	NSInteger hours = ((NSInteger)timeInterval)/3600;

	NSString * timeStr = [NSString stringWithFormat:@"%02ld:%02ld:%02ld",(long)hours,(long)minutes,(long)seconds];
	NSString *combinedStr = [NSString stringWithFormat:@"%@%@",baseStr,timeStr];

	[gv presentStatusUpdate:[%c(SBControlCenterStatusUpdate) statusUpdateWithString:combinedStr reason:@"doNotDisturb"]];
}

//Display the timer will be removed
%new - (void)displayCustomText:(NSString*)str
{
	UIView * view = [[[[self superview] superview] superview] superview];
	SBControlCenterGrabberView * gv = MSHookIvar<SBControlCenterGrabberView*>(view,"_grabberView");
	[gv presentStatusUpdate:[%c(SBControlCenterStatusUpdate) statusUpdateWithString:str reason:@"doNotDisturb"]];
}

//Function for when our timer is fired
%new - (void)fireAway {
	NSLog(@"[DisturbMeLater] Sending fire message from dndTimer...");

	//only change the state if it is currently active
	if([bm state]==1)
	{
		[bm _toggleState];
	}
}

%end

%hook HBCBToggleContainer

-(void)heldGestureRecognizerOnContactContainer:(UILongPressGestureRecognizer*)sender
{
	NSLog(@"Held - HBCBToggleContainer");
	NSString * identifier = [self switchID];
	if(!enabled || ![identifier isEqualToString:@"com.a3tweaks.switch.do-not-disturb"])
	{
		%orig;
	}
	else
	{
		if(!(sender.state==UIGestureRecognizerStateCancelled || sender.state==UIGestureRecognizerStateEnded))
		{
			return;
		}

		NSLog(@"[DML]Long press detected.");
		bool active = [bm state];
		NSLog(@"[DML]DND active?: %d",active);

		if(active)
		{
			//if we have an active timer
			if([dndTimer isValid])
			{	
				NSLog(@"[DML]DND is Active and we have an existing timer.");	
				UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Do Not Disturb"
			    message:nil
			    delegate:self
			    cancelButtonTitle:@"Cancel"
			    otherButtonTitles:@"Readjust Timer",@"Remove Timer",nil];

			    alert.tag = 202;
			    [alert show];

			    [alert release];
			}
			else
			{
				//if we don't have an active timer
				NSLog(@"[DML]DND is Active and we do NOT have an existing timer.");	
				UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Do Not Disturb"
			    message:@"When should Do No Disturb turn off?"
			    delegate:self
			    cancelButtonTitle:@"Cancel"
			    otherButtonTitles:@"Set",nil];

			    pickerView = [[UIDatePicker alloc] initWithFrame:CGRectMake(10,alert.bounds.size.height,320,216)];
			    pickerView.datePickerMode = UIDatePickerModeCountDownTimer;
			    
			    [alert setValue:pickerView forKey:@"accessoryView"];
			    alert.bounds = CGRectMake(0,0,320 + 20, alert.bounds.size.height + 216 + 20);
			    alert.tag = 101;
			    [alert show];

			    [alert release];
			}
		}
		else
		{
			NSLog(@"[DML]DND is NOT Active.");

			UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Do Not Disturb"
		    message:@"When should Do No Disturb turn off?"
		    delegate:self
		    cancelButtonTitle:@"Cancel"
		    otherButtonTitles:@"Set",nil];

		    pickerView = [[UIDatePicker alloc] initWithFrame:CGRectMake(10,alert.bounds.size.height,320,216)];
		    pickerView.datePickerMode = UIDatePickerModeCountDownTimer;
		    
		    [alert setValue:pickerView forKey:@"accessoryView"];
		    alert.bounds = CGRectMake(0,0,320 + 20, alert.bounds.size.height + 216 + 20);
		    alert.tag = 101;
		    [alert show];

		    [alert release];
		}
	}
	
}

%new -(void)alertView:(UIAlertView*)alertView clickedButtonAtIndex:(NSInteger)buttonIndex{
	if(alertView.tag==101)
	{
		//AlertView for when we long press and DND is NOT enabled
		if(buttonIndex==0)
		{
			//do nothing
		}
		else
		{
			timeInterval = (NSTimeInterval)pickerView.countDownDuration;
			NSInteger seconds = (NSInteger) timeInterval;

			NSLog(@"[DML]User would like to set a timer for DND lasting %d seconds.",seconds);

			if(!dndTimer)
			{
				dndTimer = [[PCPersistentTimer alloc] initWithTimeInterval:seconds serviceIdentifier:@"com.joshdoctors.disturbmelater" target:self selector:@selector(fireAway) userInfo:nil];
				[dndTimer scheduleInRunLoop:[NSRunLoop mainRunLoop]];
			}
			else
			{
				[dndTimer invalidate];
				dndTimer = nil;
				dndTimer = [[PCPersistentTimer alloc] initWithTimeInterval:seconds serviceIdentifier:@"com.joshdoctors.disturbmelater" target:self selector:@selector(fireAway) userInfo:nil];
				[dndTimer scheduleInRunLoop:[NSRunLoop mainRunLoop]];
			}

			//Timer is not activated(prior to our activation now) but we DND is currently enabled
			if([bm state]!=1)//
			{
				[bm _toggleState];
			}
		}

		[pickerView release];
		pickerView = nil;
	}
	else if(alertView.tag==202)
	{
		//AlertView for when we long press and DND IS enabled
		if(buttonIndex==0)
		{
			//do nothing
		}
		else if(buttonIndex==1)
		{
			NSLog(@"[DML]User would like to readjust the timer.");

			UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Do Not Disturb"
			message:@"When should Do No Disturb turn off?"
			delegate:self
		    cancelButtonTitle:@"Cancel"
		    otherButtonTitles:@"Set",nil];

		    pickerView = [[UIDatePicker alloc] initWithFrame:CGRectMake(10,alert.bounds.size.height,320,216)];
		    pickerView.datePickerMode = UIDatePickerModeCountDownTimer;
		    
		    [alert setValue:pickerView forKey:@"accessoryView"];
		    alert.bounds = CGRectMake(0,0,320 + 20, alert.bounds.size.height + 216 + 20);
		    alert.tag = 101;
		    [alert show];

		    [alert release];
		}
		else if(buttonIndex==2)
		{
			NSLog(@"[DML]User would like to remove the timer. DND will remain on however.");
			[dndTimer invalidate];
			dndTimer = nil;
		}
	}
}

//Function for when our timer is fired
%new - (void)fireAway {
	NSLog(@"[DisturbMeLater] Sending fire message from dndTimer...");

	//only change the state if it is currently active
	if([bm state]==1)
	{
		[bm _toggleState];
	}
}

%end

static void loadPrefs() 
{
	NSLog(@"Loading DisturbMeLater prefs");
    CFPreferencesAppSynchronize(CFSTR("com.joshdoctors.disturbmelater"));

    enabled = !CFPreferencesCopyAppValue(CFSTR("enabled"), CFSTR("com.joshdoctors.disturbmelater")) ? NO : [(id)CFPreferencesCopyAppValue(CFSTR("enabled"), CFSTR("com.joshdoctors.disturbmelater")) boolValue];

    if (enabled) {
        NSLog(@"[DisturbMeLater] We are enabled");
    } else {
        NSLog(@"[DisturbMeLater] We are NOT enabled");
    }

    if(auxoInstalled)
    {
    	NSDictionary * auxoDict = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.a3tweaks.auxo3.plist"];
    	NSNumber * multiCenterKey = auxoDict[@"MultiCenter"];

    	multiCenter = multiCenterKey ? [multiCenterKey boolValue] : 0;

	    if (multiCenter) {
	        NSLog(@"[DisturbMeLater] Auxo3 is installed and user is using multiCenter");
	    } else {
	        NSLog(@"[DisturbMeLater] Auxo3 is installed but user is NOT using multiCenter");
	    }
    }
}

%ctor
{

	NSLog(@"Loading DisturbMeLater");
	NSLog(@"Loading FlipSwitch and FlipCC");
	fsInstalled = dlopen("/Library/MobileSubstrate/DynamicLibraries/Flipswitch.dylib", RTLD_LAZY) != NULL;
	NSLog(@"FlipSwitch installed? %ld",(long)fsInstalled);

	polusInstalled = dlopen("/Library/MobileSubstrate/DynamicLibraries/Polus.dylib", RTLD_LAZY) != NULL;
	NSLog(@"Polus installed? %ld",(long)polusInstalled);

	auxoInstalled = dlopen("/Library/MobileSubstrate/DynamicLibraries/Auxo3.dylib", RTLD_LAZY) != NULL;
	NSLog(@"Auxo installed? %ld",(long)auxoInstalled);

	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                NULL,
                                (CFNotificationCallback)loadPrefs,
                                CFSTR("com.joshdoctors.disturbmelater/settingschanged"),
                                NULL,
                                CFNotificationSuspensionBehaviorDeliverImmediately);
	loadPrefs();
}