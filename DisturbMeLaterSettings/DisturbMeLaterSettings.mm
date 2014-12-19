#import <Preferences/Preferences.h>
#import <UIKit/UIKit.h>

@interface DisturbMeLaterSettingsListController: PSListController {
}
@end

@interface ViewController : UIViewController <UIImagePickerControllerDelegate,UINavigationControllerDelegate>
@end

@implementation DisturbMeLaterSettingsListController
- (id)specifiers {
	if(_specifiers == nil) {
		_specifiers = [[self loadSpecifiersFromPlistName:@"DisturbMeLaterSettings" target:self] retain];
	}
	return _specifiers;

}

-(void)hasFlipswitch 
{
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Have Flipswitch installed?"
		message:@"When you enable this tweak, performing a long hold on the Do Not Disturb toggle will no longer open to the Do Not Disturb settings page and instead will allow this tweak to activate. Example tweaks that use Flipswitch: CCControls, FlipControlCenter."
		delegate:self
		cancelButtonTitle:@"Ok" 
		otherButtonTitles:nil];
	[alert show];
	[alert release];
}

-(void)twitter {

	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://mobile.twitter.com/Fewjative"]];

}

@end
