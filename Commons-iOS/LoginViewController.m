//
//  SettingsViewController.m
//  Commons-iOS
//
//  Created by Brion on 1/25/13.
//  Copyright (c) 2013 Wikimedia. All rights reserved.
//

#import "LoginViewController.h"
#import "CommonsApp.h"
#import "mwapi/MWApi.h"
#import "MWI18N/MWMessage.h"
#import "MyUploadsViewController.h"
#import "GradientButton.h"
#import "AppDelegate.h"
#import "LoadingIndicator.h"
#import "GrayscaleImageView.h"
#import "GettingStartedViewController.h"
#import "QuartzCore/QuartzCore.h"
#import "AspectFillThumbFetcher.h"
#import "PictureOfTheDayImageView.h"
#import "UILabel+ResizeWithAttributes.h"

// This is the size reduction of the logo when the device is rotated to
// landscape (non-iPad - on iPad size reduction is not needed as there is ample screen area)
#define LOGO_SCALE_NON_IPAD_LANDSCAPE 0.53

// This is the extra distance the login container is moved when the keyboard is revealed
#define LOGIN_CONTAINER_VERTICAL_OFFSET -30.0

#define RADIANS_TO_DEGREES(radians) ((radians) * (180.0 / M_PI))
#define DEGREES_TO_RADIANS(angle) ((angle) / 180.0 * M_PI)

#define RESET_PASSWORD_URL @"http://commons.wikimedia.org/wiki/Special:PasswordReset"

// Note: to change the bundled picture of the day simply remove the existing one from the
// bundle, add the new one, then change is date to match the date from the newly bundled
// file name (Nice thing about this approach is the code doesn't have to know anything
// about a special-case file - it works normally with no extra checks)
#define DEFAULT_BUNDLED_PIC_OF_DAY_DATE @"2013-05-24"

// Change this to a plist later, but we're not bundling that many images
#define BUNDLED_PIC_OF_DAY_DATES @"2007-06-15|2008-01-25|2008-11-14|2009-06-19|2010-05-24|2012-07-08|2013-02-24|2013-04-21|2013-04-29|2013-05-24|2013-06-04"

// Pic of day transition settings
#define SECONDS_TO_SHOW_EACH_PIC_OF_DAY 6.0f
#define SECONDS_TO_TRANSITION_EACH_PIC_OF_DAY 2.3f

#define PIC_OF_THE_DAY_TO_DOWNLOAD_DAYS_AGO 0 //0 for today, 1 for yesterday, -1 for tomorrow etc

// Force the app to download and cache a particularly interesting picture of the day
#define FORCE_PIC_OF_DAY_DOWNLOAD_FOR_DATE nil //@"2013-05-24"

@interface LoginViewController (){
    AspectFillThumbFetcher *pictureOfTheDayGetter_;
    BOOL showingPictureOfTheDayAttribution_;
    NSMutableArray *cachedPotdDateStrings_;
    NSTimer *potdCycler_;
    uint potdCylerIndex_;
}

- (void)showMyUploadsVC;

@property (weak, nonatomic) AppDelegate *appDelegate;
@property (strong, nonatomic) NSString *trimmedUsername;
@property (strong, nonatomic) NSString *trimmedPassword;
@property (strong, nonatomic) NSString *pictureOfTheDayUser;
@property (strong, nonatomic) NSString *pictureOfTheDayDateString;

@end

@implementation LoginViewController
{
    UILongPressGestureRecognizer *longPressRecognizer;
    UISwipeGestureRecognizer *swipeRecognizerUp;
    UISwipeGestureRecognizer *swipeRecognizerDown;
    UISwipeGestureRecognizer *swipeRecognizerLeft;
    UITapGestureRecognizer *tapRecognizer;
    UITapGestureRecognizer *doubleTapRecognizer;
    CGPoint originalInfoContainerCenter;
    
    // Only skip the login screen on initial load
    bool allowSkippingToMyUploads;

}

- (id)initWithCoder:(NSCoder *)decoder
{
    if (self = [super initWithCoder:decoder])
    {
        allowSkippingToMyUploads = YES;
        pictureOfTheDayGetter_ = [[AspectFillThumbFetcher alloc] init];
        self.pictureOfTheDayUser = nil;
        self.pictureOfTheDayDateString = nil;
        showingPictureOfTheDayAttribution_ = NO;
        cachedPotdDateStrings_ = [[NSMutableArray alloc] init];
        self.potdImageView.image = nil;
        potdCylerIndex_ = 0;
        potdCycler_ = nil;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    originalInfoContainerCenter = CGPointZero;

    // Remember where the login info container had been so it can be moved back here when the keyboard is hidden
    originalInfoContainerCenter = _loginInfoContainer.center;
    
	// Get the app delegate so the loading indicator may be accessed
	self.appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];

	// Set gradient buttons color
	[self.loginButton useWhiteStyle];
    [self.logoutButton useWhiteStyle];

    // l10n
    self.navigationItem.title = [MWMessage forKey:@"login-title"].text;
    self.usernameField.placeholder = [MWMessage forKey:@"settings-username-placeholder"].text;
    self.passwordField.placeholder = [MWMessage forKey:@"settings-password-placeholder"].text;
    [self.loginButton setTitle:[MWMessage forKey:@"login-button"].text forState:UIControlStateNormal];

    [self.logoutButton setTitle:[MWMessage forKey:@"logout-button"].text forState:UIControlStateNormal];

    [self.recoverPasswordButton setTitle:[MWMessage forKey:@"login-recover-password-button"].text forState:UIControlStateNormal];

    // Disable auto-correct on login boxes
    self.usernameField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.passwordField.autocorrectionType = UITextAutocorrectionTypeNo;
    
    // Gray out the login button if no credentials
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fadeLoginButtonIfNoCredentials) name:UITextFieldTextDidChangeNotification object:self.usernameField];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fadeLoginButtonIfNoCredentials) name:UITextFieldTextDidChangeNotification object:self.passwordField];
    
    [self.loginButton setTitleColor:[UIColor grayColor] forState:UIControlStateDisabled];
    
	// Do any additional setup after loading the view.
    CommonsApp *app = CommonsApp.singleton;
    self.usernameField.text = app.username;
    self.passwordField.text = app.password;
    
    //hide keyboard when anywhere else is tapped
	tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
    tapRecognizer.numberOfTapsRequired = 1;
	[self.view addGestureRecognizer:tapRecognizer];

	longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress)];
    longPressRecognizer.minimumPressDuration = 1.0f;
	[self.view addGestureRecognizer:longPressRecognizer];
    
    swipeRecognizerUp = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeUp)];
    swipeRecognizerUp.numberOfTouchesRequired = 1;
    swipeRecognizerUp.direction = UISwipeGestureRecognizerDirectionUp;
	[self.view addGestureRecognizer:swipeRecognizerUp];

    swipeRecognizerDown = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeDown)];
    swipeRecognizerDown.numberOfTouchesRequired = 1;
    swipeRecognizerDown.direction = UISwipeGestureRecognizerDirectionDown;
	[self.view addGestureRecognizer:swipeRecognizerDown];

    swipeRecognizerLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeLeft)];
    swipeRecognizerLeft.numberOfTouchesRequired = 1;
    swipeRecognizerLeft.direction = UISwipeGestureRecognizerDirectionLeft;
	[self.view addGestureRecognizer:swipeRecognizerLeft];

    doubleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap)];
    doubleTapRecognizer.numberOfTapsRequired = 2;
	[self.view addGestureRecognizer:doubleTapRecognizer];
    doubleTapRecognizer.enabled = NO;

    [self fadeLoginButtonIfNoCredentials];

    self.potdImageView.useFilter = NO;

    // Ensure bundled pic of day is in cache
    [self copyToCacheBundledPotdsNamed:BUNDLED_PIC_OF_DAY_DATES];

    if(FORCE_PIC_OF_DAY_DOWNLOAD_FOR_DATE == nil){
        // Load default image to ensure something is showing even if no net connection
        // (loads the copy of the bundled default potd which was copied to the cache)
        [self getPictureOfTheDayForDateString:DEFAULT_BUNDLED_PIC_OF_DAY_DATE done:nil];
    }
    
    // Make logo a bit larger on iPad
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad){
        _logoImageView.frame = CGRectInset(_logoImageView.frame, -75.0f, -75.0f);
    }
    
    _logoImageView.alpha = 1.0f;
    _usernameField.alpha = 1.0f;
    _passwordField.alpha = 1.0f;
    _loginButton.alpha = 1.0f;
    
    // Add shadow behind the login text boxes and buttons so they stand out on light background
    [LoginViewController applyShadowToView:self.loginInfoContainer];
    [LoginViewController applyShadowToView:self.aboutButton];    
    [LoginViewController applyShadowToView:self.attributionButton];
    [LoginViewController applyShadowToView:self.recoverPasswordButton];
}

-(void)copyToCacheBundledPotdsNamed:(NSString *)defaultBundledPotdsDates
{
    NSArray *dates = [defaultBundledPotdsDates componentsSeparatedByString:@"|"];
    for (NSString *bundledPotdDateString in dates) {
        // Copy bundled default picture of the day to the cache (if it's not already there)
        // so there's a pic of the day shows even if today's image can't download
        NSString *defaultBundledPotdFileName = [NSString stringWithFormat:@"POTD-%@.dict", bundledPotdDateString];
        NSString *defaultBundledPath = [[NSBundle mainBundle] pathForResource:defaultBundledPotdFileName ofType:nil];
        if (defaultBundledPath){
            //Bundled File Found! See: http://stackoverflow.com/a/7487235
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *cachePotdPath = [[CommonsApp singleton] potdPath:defaultBundledPotdFileName];
            if (![fm fileExistsAtPath:cachePotdPath]) {
                // Cached version of bundle file not found, so copy bundle file to cache!
                [fm copyItemAtPath:defaultBundledPath toPath:cachePotdPath error:nil];
            }
        }
    }
}

-(void)loadArrayOfCachedPotdDateStrings
{
    [cachedPotdDateStrings_ removeAllObjects];
    
    // Get array cachedPotdDateStrings_ of cached potd date strings
    // Uses reverseObjectEnumerator so most recently downloaded images show first
    NSArray *allFileInPotdFolder = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[CommonsApp singleton] potdPath:@""] error:nil];
    for (NSString *fileName in [allFileInPotdFolder reverseObjectEnumerator]) {
        if ([fileName hasPrefix:@"POTD-"]) {
            NSString *dateString2 = [fileName substringWithRange:NSMakeRange(5, 10)];
            [cachedPotdDateStrings_ addObject:dateString2];
        }
    }

    // Move the default bundled image to the end of the array so it doesn't show again
    // until the other images have been cycled through
    [cachedPotdDateStrings_ removeObject:DEFAULT_BUNDLED_PIC_OF_DAY_DATE];
    [cachedPotdDateStrings_ addObject:DEFAULT_BUNDLED_PIC_OF_DAY_DATE];

    //NSLog(@"\n\ncachedPotdDateStrings_ = \n\n%@\n\n", cachedPotdDateStrings_);
}

-(void)cycleNextCachedPotd
{
    if (cachedPotdDateStrings_.count < 2) return;

    if (potdCylerIndex_ > (cachedPotdDateStrings_.count - 1)) potdCylerIndex_ = cachedPotdDateStrings_.count - 1;

    NSString *dateString = cachedPotdDateStrings_[potdCylerIndex_];

    [self getPictureOfTheDayForDateString:dateString done:nil];
    
    potdCylerIndex_ = (potdCylerIndex_ == (cachedPotdDateStrings_.count - 1)) ? 0 : potdCylerIndex_ + 1;
}

-(void)cycleNextCachedPotdFirstTime
{
    [self cycleNextCachedPotd];
    [self stopPotdCyclerTimer];

    if (potdCycler_ == nil){
        potdCycler_ = [NSTimer scheduledTimerWithTimeInterval:(SECONDS_TO_SHOW_EACH_PIC_OF_DAY) target:self
                                                     selector:@selector(cycleNextCachedPotd)
                                                     userInfo:nil
                                                     repeats:YES];
    }
}

-(void)startPotdCyclerTimer
{
    // Added initial call to "cycleNextCachedPotdFirstTime" on a shorter timer because the initial image isn't
    // fading in from a previous image and thus *looks* like it's taking longer even thought it isn't. Since
    // NSTimer can't have its timerInterval changed once it's been created the timer created in this method only
    // fires once ("repeats:NO"). Then the timer kicked off by "cycleNextCachedPotdFirstTime" *does* repeat, but
    // with the full "SECONDS_TO_SHOW_EACH_PIC_OF_DAY" interval
    if (potdCycler_ == nil){
        potdCycler_ = [NSTimer scheduledTimerWithTimeInterval:(SECONDS_TO_SHOW_EACH_PIC_OF_DAY - SECONDS_TO_TRANSITION_EACH_PIC_OF_DAY) target:self
                                                     selector:@selector(cycleNextCachedPotdFirstTime)
                                                     userInfo:nil
                                                     repeats:NO];
    }
}

-(void)stopPotdCyclerTimer
{
    if (potdCycler_ != nil){
        [potdCycler_ invalidate];
        potdCycler_ = nil;
    }
}

-(NSString *)getDateStringForDaysAgo:(int)daysAgo
{
    NSDate *date = [[NSDate alloc] init];
    date = [date dateByAddingTimeInterval: -(86400.0 * daysAgo)];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd"];
    return [formatter stringFromDate:date];
}

-(void)getPictureOfTheDayForDateString:(NSString *)dateString done:(void(^)(void)) done
{
    // Prepare callback block for getting picture of the day
    __weak PictureOfTheDayImageView *weakPotdImageView = self.potdImageView;
    __weak LoginViewController *weakSelf = self;

    // Determine the resolution of the picture of the day to request
    CGSize screenSize = self.view.bounds.size;
    // For now leave scale at one - retina iPads would request too high a resolution otherwise
    CGFloat scale = 1.0f; //[[UIScreen mainScreen] scale];
    
    MWPromise *fetch = [pictureOfTheDayGetter_ fetchPictureOfDay:dateString size:CGSizeMake(screenSize.width * scale, screenSize.height * scale) withQueuePriority:NSOperationQueuePriorityHigh];
    
    [fetch done:^(NSDictionary *dict) {
        if (dict) {
            NSData *imageData = dict[@"image"];
            if (imageData) {
                UIImage *image = [UIImage imageWithData:imageData scale:1.0];

                weakSelf.pictureOfTheDayUser = dict[@"user"];
                weakSelf.pictureOfTheDayDateString = dict[@"potd_date"];
                
                // Briefly hide the attribution label before updating it
                [UIView animateWithDuration:SECONDS_TO_TRANSITION_EACH_PIC_OF_DAY / 4.0
                                      delay:0.0
                                    options: UIViewAnimationCurveLinear
                                 animations:^{
                                     weakSelf.attributionLabel.alpha = 0.0f;
                                 }
                                 completion:^(BOOL finished){
                                     // Update the attribution text
                                     [weakSelf updateAttributionLabelText];
                                     // Make the attribution label encompass the new attribution text
                                     [weakSelf updateAttributionLabelFrame];

                                     //Now show the updated attribution box
                                     [UIView animateWithDuration:SECONDS_TO_TRANSITION_EACH_PIC_OF_DAY / 3.0
                                                           delay:0.0
                                                         options: UIViewAnimationCurveLinear
                                                      animations:^{
                                                          weakSelf.attributionLabel.alpha = 1.0f;
                                                      }
                                                      completion:^(BOOL finished){                                                          
                                                      }];
                                 }];

                // Transistion the picture of the day
                [UIView transitionWithView:weakPotdImageView
                                  duration:SECONDS_TO_TRANSITION_EACH_PIC_OF_DAY
                                   options:UIViewAnimationOptionTransitionCrossDissolve
                                animations:^{
                                    weakPotdImageView.useFilter = NO;
                                    weakPotdImageView.image = image;
                                }completion:^(BOOL finished){
                                    if(done) done();
                                }];
            }
        }
    }];

    // Cycle through cached images even of there was problem downloading a new one
    [fetch fail:^(NSError *error) {
        NSLog(@"PictureOfTheDay Error: %@", error.description);
        if(done) done();
    }];

    [fetch always:^(id obj) {

    }];
}

+ (void)applyShadowToView:(UIView *)view{
    view.layer.shadowColor = [UIColor blackColor].CGColor;
    view.layer.shadowOffset = CGSizeMake(0, 0);
    view.layer.shadowOpacity = 1;
    view.layer.shadowRadius = 6.0;
    view.clipsToBounds = NO;
}

-(NSUInteger)supportedInterfaceOrientations
{
    // Restrict login page orientation to portrait. Needed because the because
    // the picture of the day looks weird on rotation otherwise.
    // Also jarring if the getting started screen is shown as it forces portrait
    return UIInterfaceOrientationMaskPortrait;
}

-(BOOL)shouldAutorotate
{
    // Required for supportedInterfaceOrientations to be called
    return YES;
}

-(NSString *) trimmedUsername{
    // Returns trimmed version of the username as it *presently exists* in the usernameField UITextField
    return [CommonsApp.singleton getTrimmedString:self.usernameField.text];
}

-(NSString *) trimmedPassword{
    // Returns trimmed version of the password as it *presently exists* in the passwordField UITextField
    return [CommonsApp.singleton getTrimmedString:self.passwordField.text];
}

- (void)fadeLoginButtonIfNoCredentials
{
    [self.loginButton setTitleColor:
     (!self.trimmedUsername.length || !self.trimmedPassword.length) ? [UIColor grayColor] : [UIColor blackColor]
                           forState:UIControlStateNormal];
}

- (void)keyboardWillShow:(NSNotification *)notification
{
	// When the keyboard is revealed move the login container to the logo position so the keyboard doesn't occlude
	// the login text boxes and login button
	// Enlarge and Fade the logo partially out when doing so for a nice transistion and to focus attention on the
	// login process while the keyboard is visible
	[UIView animateWithDuration:0.2
						  delay:0.0
						options:UIViewAnimationOptionTransitionNone
					 animations:^{

                        // Prevents the keyboard from covering any of the login container contents, not needed on iPad
                        // Most useful on non-iPads in landscape
                        float yOffset = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) ? 0 : LOGIN_CONTAINER_VERTICAL_OFFSET;
                         
						 // Move login container to logo position (plus a slight vertical offset)
						 _loginInfoContainer.center = CGPointMake(_logoImageView.center.x, _logoImageView.center.y + yOffset);
						 
						 // Enlarge and partially fade out the logo
                         if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad){
                             _logoImageView.transform = CGAffineTransformMakeScale(1.5, 1.5);
                         }else{
                             _logoImageView.transform = CGAffineTransformMakeScale(1.2, 1.2);
                         }
                         
						 _logoImageView.alpha = 0.08;
                         
                         [_logoImageView toGrayscale];
                         
					 }
					 completion:^(BOOL finished){
						 
					 }];
}

- (void)keyboardWillHide:(NSNotification *)notification
{
    doubleTapRecognizer.enabled = NO;

    [self animateLoginInfoContainerAndLogoBackToStoryboardLayout];
}

-(void)animateLoginInfoContainerAndLogoBackToStoryboardLayout{
    // When hiding the keyboard, the login container needs be moved back to its storyboard
    // position (where it was before the keyboard was shown)
	[UIView animateWithDuration:0.2
						  delay:0.0
						options:UIViewAnimationOptionTransitionNone
					 animations:^{

						 // Reset the login container position
						 _loginInfoContainer.center = originalInfoContainerCenter;
						 
						 // Restore the logo alpha and scale as well
						 _logoImageView.alpha = 1.0;
						 
                        [_logoImageView toColor];
                         
						 if (
							 (UI_USER_INTERFACE_IDIOM() != UIUserInterfaceIdiomPad)
							 &&
							 UIInterfaceOrientationIsLandscape(self.interfaceOrientation)
							 ){
							 _logoImageView.transform = CGAffineTransformMakeScale(LOGO_SCALE_NON_IPAD_LANDSCAPE, LOGO_SCALE_NON_IPAD_LANDSCAPE);
						 }else{
							 _logoImageView.transform = CGAffineTransformIdentity;
						 }
					 }
					 completion:^(BOOL finished){
						 
					 }];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewDidUnload {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self setUsernameField:nil];
    [self setPasswordField:nil];
    [super viewDidUnload];
}

-(void)viewWillLayoutSubviews{
	// Position the logo and the login containers centered horizontally and at about one-third and two-thirds
	// the way down the screen vertically respectively
	_logoImageView.center = CGPointMake(self.view.center.x, self.view.frame.size.height / 3.0);
	_loginInfoContainer.center = CGPointMake(self.view.center.x, (self.view.frame.size.height / 2.6) * 2.0);

    // Ensure originalInfoContainerCenter has new _loginInfoContainer.center value
    originalInfoContainerCenter = _loginInfoContainer.center;
    
	// Shrink the logo a bit when the device is held in landscape if the device is not an ipad
    if (
		(UI_USER_INTERFACE_IDIOM() != UIUserInterfaceIdiomPad)
		&&
		UIInterfaceOrientationIsLandscape(self.interfaceOrientation)
	){
		_logoImageView.transform = CGAffineTransformMakeScale(LOGO_SCALE_NON_IPAD_LANDSCAPE, LOGO_SCALE_NON_IPAD_LANDSCAPE);
	}else{
		_logoImageView.transform = CGAffineTransformIdentity;
	}
	
}

- (void)keyboardDidShow:(NSNotification *)notification
{
    doubleTapRecognizer.enabled = YES;
}

-(void)viewDidAppear:(BOOL)animated{
    
    // Enable keyboard show listener only while this view controller's view is visible (this observer is removed
    // in viewDidDisappear. When we didn't remove it in viewDidDisappear this view controller was receiving
    // notifications even when its view wasn't even visible!)
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidShow:)
                                                 name:UIKeyboardDidShowNotification
                                               object:nil];

    
    // Automatically show the getting started pages, but only once and only if no credentials present
    [self showGettingStartedAutomaticallyOnce];
    
    [super viewDidAppear:animated];
}

-(void)showGettingStartedAutomaticallyOnce
{
    // Automatically show the getting started pages, but only once and only if no credentials present
    if(
       ([self trimmedUsername].length == 0)
       &&
       ([self trimmedPassword].length == 0)
       &&
       ![[NSUserDefaults standardUserDefaults] boolForKey:@"GettingStartedWasAutomaticallyShown"]
       )
    {
        GettingStartedViewController *gettingStartedVC = [self.storyboard instantiateViewControllerWithIdentifier:@"GettingStartedViewController"];
        [self presentViewController:gettingStartedVC animated:NO completion:nil];
        
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"GettingStartedWasAutomaticallyShown"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

-(void)viewWillAppear:(BOOL)animated{

    // Because tapping currentUserButton pushes a view controller onto the navigation controller stack
    // the currentUserButton can shuffle offscreen before it completely finishes updating itself from
    // its selected visual state to its unselected visual state. When this happens, when the view
    // which was pushed gets popped, the currentUserButton can appear to be pushed - visually a bit
    // more dark. setNeedsDisplay tells it to draw itself again
    [self.currentUserButton setNeedsDisplay];
    
	[self.navigationController setNavigationBarHidden:YES animated:animated];
    [super viewWillAppear:animated];
	
    // The wikimedia picture of the day urls use yyyy-MM-dd format - get such a string
    NSString *dateString = [self getDateStringForDaysAgo:PIC_OF_THE_DAY_TO_DOWNLOAD_DAYS_AGO];
    
    if(FORCE_PIC_OF_DAY_DOWNLOAD_FOR_DATE != nil){
        dateString = FORCE_PIC_OF_DAY_DOWNLOAD_FOR_DATE;
    }

    // Populate array cachedPotdDateStrings_ with all cached potd file date strings
    [self loadArrayOfCachedPotdDateStrings];
    // If dateString not already in cachedPotdDateStrings_ 
    if (![cachedPotdDateStrings_ containsObject:dateString]) {
        // Download the current PotD!
        [self getPictureOfTheDayForDateString:dateString done:^{
            // Update "cachedPotdDateStrings_" so it contains date string for the newly downloaded file
            [self loadArrayOfCachedPotdDateStrings];
            [self startPotdCyclerTimer];
        }];
    }else{
        [self startPotdCyclerTimer];
    }
}

-(void)viewDidDisappear:(BOOL)animated{

    // Disables keyboard listeners when this view controller's view is not visible
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];

    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];

    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardDidShowNotification object:nil];

    // Ensure keyboard is hidden - sometimes it can hang around otherwise
	[self.usernameField resignFirstResponder];
	[self.passwordField resignFirstResponder];
}

-(void)viewWillDisappear:(BOOL)animated{
	   
	UIBarButtonItem *backButton = [[UIBarButtonItem alloc]
								   initWithTitle: [MWMessage forKey:@"login-title"].text
								   style: UIBarButtonItemStyleBordered
								   target:nil action: nil];
	
	[backButton setTitleTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
										[UIColor colorWithRed:1 green:1 blue:1 alpha:1], UITextAttributeTextColor,
										[NSValue valueWithUIOffset:UIOffsetMake(0.0f, 0.0f)], UITextAttributeTextShadowOffset,
										nil] forState:UIControlStateNormal];
	
	[self.navigationItem setBackBarButtonItem: backButton];

    [self stopPotdCyclerTimer];

    [super viewWillDisappear:animated];
}

-(void)showMyUploadsVC{
    // For pushing the MyUploads view controller on to the navigation controller (used when login
    // credentials have been authenticated)
    MyUploadsViewController *myUploadsVC = [self.storyboard instantiateViewControllerWithIdentifier:@"MyUploadsViewController"];
    [self.navigationController pushViewController:myUploadsVC animated:YES];
    
    // Show logout elementes after slight delay. if the login page is sliding offscreen it looks odd
    // to update its interface elements as it's sliding away - the delay fixes this
    float delayInSeconds = 0.25;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void){
        // Executed on the main queue after delay
        [self showLogout:YES];
    });
}

-(IBAction)pushedCurrentUserButton:(id)sender
{
    [self showMyUploadsVC];
}

-(IBAction)pushedRecoverPasswordButton:(id)sender
{
    CommonsApp *app = CommonsApp.singleton;
    [app openURLWithDefaultBrowser:[NSURL URLWithString:RESET_PASSWORD_URL]];
}

-(void)showLogout:(BOOL)show
{
    self.logoutButton.hidden = !show;
    self.currentUserButton.hidden = !show;
    self.loginButton.hidden = show;
    self.usernameField.hidden = show;
    self.passwordField.hidden = show;
    self.recoverPasswordButton.hidden = show;

    [self.currentUserButton setTitle:[MWMessage forKey:@"login-current-user-button" param:self.usernameField.text].text forState:UIControlStateNormal];
    
    // Size currentUserButton to fix whatever text it now contains
    CGRect f = self.currentUserButton.frame;
    CGSize s = [self.currentUserButton sizeThatFits:self.currentUserButton.frame.size];
    // Add padding to right and left of re-sized currentUserButton's text
    f.size.width = s.width + 40.0f;
    // If resized currentUserButton is narrower than the logout button make it same width as logout button
    f.size.width = (f.size.width < self.logoutButton.frame.size.width) ? self.logoutButton.frame.size.width : f.size.width;
    self.currentUserButton.frame = f;
    // Re-center currentUserButton above logout button
    self.currentUserButton.center = CGPointMake(self.logoutButton.center.x, self.currentUserButton.center.y);
    
}

-(void)revealLoginFieldsWithAnimation
{
    CGPoint origCurrentUserButtonCenter = self.currentUserButton.center;
    self.logoutButton.layer.zPosition = self.currentUserButton.layer.zPosition + 1;
    // Animate currentUserButton to slide down behind logoutButton
    [UIView animateWithDuration:0.15f
                          delay:0.0f
                        options:UIViewAnimationOptionTransitionNone
                     animations:^{
                         self.currentUserButton.center = self.logoutButton.center;
                         self.currentUserButton.alpha = 0.0f;
                     }
                     completion:^(BOOL finished){
                         
                         // Now animate usernameField and passwordField sliding up
                         self.currentUserButton.hidden = YES;
                         self.currentUserButton.center = origCurrentUserButtonCenter;
                         self.loginButton.alpha = 0.0f;
                         self.usernameField.alpha = 0.0f;
                         self.passwordField.alpha = 0.0f;
                         self.recoverPasswordButton.alpha = 0.0f;
                         self.loginButton.hidden = NO;
                         self.usernameField.hidden = NO;
                         self.passwordField.hidden = NO;
                         self.recoverPasswordButton.hidden = NO;

                         CGRect origUsernameFieldFrame = self.usernameField.frame;
                         CGRect origPasswordFieldFrame = self.passwordField.frame;
                         float vOffset = self.loginButton.frame.origin.y - self.usernameField.frame.origin.y;
                         self.usernameField.center = CGPointMake(self.usernameField.center.x, self.usernameField.center.y + vOffset);
                         self.passwordField.center = CGPointMake(self.passwordField.center.x, self.passwordField.center.y + vOffset);
                         [UIView animateWithDuration:0.15f
                                               delay:0.0f
                                             options:UIViewAnimationOptionTransitionNone
                                          animations:^{
                                              
                                              self.usernameField.alpha = 1.0f;
                                              self.passwordField.alpha = 1.0f;
                                              
                                              self.recoverPasswordButton.alpha = 1.0f;
                                              self.loginButton.alpha = 1.0f;
                                              // If either username or password blank fade the login button
                                              [self fadeLoginButtonIfNoCredentials];
                                              
                                              self.logoutButton.alpha = 0.0f;
                                              
                                              self.usernameField.frame = origUsernameFieldFrame;
                                              self.passwordField.frame = origPasswordFieldFrame;
                                          }
                                          completion:^(BOOL finished){
                                              // Reset logout state
                                              [self showLogout:NO];
                                              // Ensure login button isn't stuck drawn selected
                                              [self.loginButton setNeedsDisplay];
                                              // The logout button is hidden by now, but ensure it can be seen the next time it is animated
                                              self.logoutButton.alpha = 1.0f;
                                              self.currentUserButton.alpha = 1.0f;
                                          }];
                     }];
}

- (IBAction)pushedLogoutButton:(id)sender
{
    CommonsApp *app = CommonsApp.singleton;
    [app.fetchDataURLQueue cancelAllOperations];
    [app deleteAllRecords];
    [app clearKeychainCredentials];
    app.debugMode = NO;
    self.usernameField.text = @"";
    self.passwordField.text = @"";

    [self revealLoginFieldsWithAnimation];
}

-(BOOL)setTextInputFocusOnEmptyField
{
    // Sets focus on first empty username or password field returning YES if it does so
    // Returns no if no blank fields found
    UITextField *textFieldInNeedOfInput = [self getTextFieldInNeedOfInput];
    if (textFieldInNeedOfInput) {
        [textFieldInNeedOfInput becomeFirstResponder];
        return YES;
    }else{
        return NO;
    }
}

-(void)handleTap
{
    if (showingPictureOfTheDayAttribution_) {
        [self hideAttributionLabel];
        showingPictureOfTheDayAttribution_ = NO;
        return;
    }
    
    [self setTextInputFocusOnEmptyField];
}

-(void)handleSwipeUp
{
    if (showingPictureOfTheDayAttribution_) return;
    [self setTextInputFocusOnEmptyField];
}

-(void)handleSwipeDown
{
    if (showingPictureOfTheDayAttribution_) return;
    [self hideKeyboard];
}

-(void)handleSwipeLeft
{
    if (self.currentUserButton.hidden) return;
    
    [self showMyUploadsVC];
}

-(void)handleLongPress
{
    // Uncomment for presentation username/pwd auto entry
    /*
    self.usernameField.text = @"";
	self.passwordField.text = @"";

    [self fadeLoginButtonIfNoCredentials];
    */
}

-(void)handleDoubleTap
{
    // Hide the keyboard. Needed because on non-iPad keyboard there is no hide keyboard button
    [self hideKeyboard];
}

-(void)hideKeyboard
{
    [self.usernameField resignFirstResponder];
	[self.passwordField resignFirstResponder];
}

-(UITextField *)getTextFieldInNeedOfInput
{
    // If neither username nor password, return username field
    if(!self.trimmedUsername.length && !self.trimmedPassword.length) return self.usernameField;
    
    // If some username but no password return password field
    if(self.trimmedUsername.length && !self.trimmedPassword.length) return self.passwordField;
    
    // If some password but no username return username field
    if(!self.trimmedUsername.length && self.trimmedPassword.length) return self.usernameField;

    return nil;
}

- (IBAction)pushedLoginButton:(id)sender
{
    // If username or password are blank set focus on the first one which is blank and return
    if ([self setTextInputFocusOnEmptyField]) return;
    
    CommonsApp *app = CommonsApp.singleton;
    
    allowSkippingToMyUploads = NO;

	// Trim leading and trailing white space from user name and password. This is so the isEqualToString:@"" check below
	// will cause the login to be validated (previously if login info was blank it fell past the credential validation
	// check and crashed)
    NSString *username = self.trimmedUsername;
    NSString *password = self.trimmedPassword;
    
    // Only update & validate user credentials if they have been changed
    if (
        ![app.username isEqualToString:username]
		||
		![app.password isEqualToString:password]

		// The two cases below force the validation check to happen even on blank user name and/or password entries so
		// an invalid login alert is still shown if no login credentials were entered
		||
		[app.username isEqualToString:@""]
		||
		[app.password isEqualToString:@""]

        ) {
        
		// Show the loading indicator wheel
		[self.appDelegate.loadingIndicator show];
		
        // Test credentials to make sure they are valid
        MWApi *mwapi = [app startApi];
        
        MWPromise *login = [mwapi loginWithUsername:username
                                        andPassword:password];
        [login done:^(NSDictionary *loginResult) {
            
            if (mwapi.isLoggedIn) {
                // Credentials verified
                [app log:@"MobileAppLoginAttempts" event:@{
                    @"username": username,
                    @"result": @"success"
                }];
                
                // Save credentials
                app.username = username;
                app.password = password;
                [app saveCredentials];
                [app deleteAllRecords];
                
                [self.passwordField resignFirstResponder];
                
                MWPromise *refresh = [app refreshHistoryWithFailureAlert:YES];
                [refresh always:^(id arg) {
                    // Login success! Show MyUploads view
                    [self showMyUploadsVC];
                }];
                
            } else {
                // Credentials invalid
                [app log:@"MobileAppLoginAttempts" event:@{
                    @"username": username,
                    @"result": loginResult[@"login"][@"result"]
                }];
                
                // Erase saved credentials so that the credentials are validated every time they are changed
                app.username = @"";
                app.password = @"";
                [app saveCredentials];
                [app deleteAllRecords];
                
                UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[MWMessage forKey:@"error-bad-password-title"].text
                                                                    message:[MWMessage forKey:@"error-bad-password"].text
                                                                   delegate:nil
                                                          cancelButtonTitle:[MWMessage forKey:@"error-dismiss"].text
                                                          otherButtonTitles:nil];
                [alertView show];
            }
        }];
        [login fail:^(NSError *error) {
            
            [app log:@"MobileAppLoginAttempts" event:@{
                @"username": username,
                @"result": @"network"
            }];
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[MWMessage forKey:@"error-login-fail"].text
                                                                message:[error localizedDescription]
                                                               delegate:nil
                                                      cancelButtonTitle:[MWMessage forKey:@"error-dismiss"].text
                                                      otherButtonTitles:nil];
            [alertView show];
        }];
        
        [login always:^(NSDictionary *loginResult) {
			// Hide the loading indicator wheel
			[self.appDelegate.loadingIndicator hide];
        }];
    }
    else {
    // Credentials have not been changed
        
        NSLog(@"Credentials have not been changed.");
        
        // Dismiss view
               
		//login success!
        [self showMyUploadsVC];
    }
}

- (IBAction)pushedAttributionButton:(id)sender{
    showingPictureOfTheDayAttribution_ = !showingPictureOfTheDayAttribution_;

    if (showingPictureOfTheDayAttribution_) {
        [self showAttributionLabel];
    }else{
        [self hideAttributionLabel];
    }

    NSLog(@"pictureOfTheDayUser_ = %@", self.pictureOfTheDayUser);
    NSLog(@"pictureOfTheDayDateString_ = %@", self.pictureOfTheDayDateString);
}

-(void)updateAttributionLabelText
{
    // Convert the date string to an NSDate
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd"];
    NSDate *date = [dateFormatter dateFromString:self.pictureOfTheDayDateString];
    
    // Now get nice readable date for current locale
    NSString *formatString = [NSDateFormatter dateFormatFromTemplate:@"EdMMMy" options:0 locale:[NSLocale currentLocale]];
    [dateFormatter setDateFormat:formatString];
    
    NSString *prettyDateString = [dateFormatter stringFromDate:date];
    NSString *picOfTheDayText = [MWMessage forKey:@"picture-of-day-label"].text;
    NSString *picOfTheAuthorText = [MWMessage forKey:@"picture-of-day-author"].text;
    self.attributionLabel.text = [NSString stringWithFormat:
                                  @"%@\n%@\n%@ %@",
                                  picOfTheDayText,
                                  prettyDateString,
                                  picOfTheAuthorText,
                                  self.pictureOfTheDayUser];    
}

-(void)updateAttributionLabelFrame
{
    // Ensure the label encompasses its text perfectly
    float fontSize =            (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) ? 38.0f : 15.0f;
    float lineSpacing =         (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) ? 16.0f : 8.0f;
    float backgroundPadding =   (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) ? 30.0f : 10.0f;
    float bottomMargin =        (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) ? 27.0f : 16.0f;
    
    // Style attributes for labels
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = NSTextAlignmentCenter;
    paragraphStyle.lineSpacing = lineSpacing;
    paragraphStyle.lineBreakMode = NSLineBreakByWordWrapping;
    
    // Apply styled attributes to label resizing it to fit the newly styled text (regardless of i18n string length!)
    [self.attributionLabel resizeWithAttributes: @{
                           NSFontAttributeName : [UIFont boldSystemFontOfSize:fontSize],
                 NSParagraphStyleAttributeName : paragraphStyle,
                NSForegroundColorAttributeName : [UIColor colorWithWhite:1.0f alpha:1.0f]
     }];
    // Reposition the resized label to be just above the bottom of the screen
    self.attributionLabel.frame = CGRectInset(self.attributionLabel.frame, -backgroundPadding, -backgroundPadding);
    self.attributionLabel.center = CGPointMake(self.attributionLabel.center.x,
                                               self.view.frame.size.height -
                                               (self.attributionLabel.frame.size.height / 2.0f) -
                                               bottomMargin
                                               );
    
}

-(void)showAttributionLabel
{
    [self updateAttributionLabelText];
    
    [self updateAttributionLabelFrame];
    
    self.attributionLabel.hidden = NO;
    CGPoint prevCenter = self.attributionLabel.center;
    
    // Move attributionLabel off the bottom of the screen
    self.attributionLabel.center = CGPointMake(self.attributionLabel.center.x, self.attributionLabel.center.y + (self.view.frame.size.height - self.attributionLabel.frame.origin.y));
    
    [UIView animateWithDuration:0.2f
                          delay:0.0f
                        options:UIViewAnimationOptionTransitionNone
                     animations:^{
                         self.logoImageView.alpha = 0.0f;
                         self.loginInfoContainer.alpha = 0.0f;
                         self.aboutButton.alpha = 0.0f;
                         
                         // Move attributionLabel back
                         self.attributionLabel.center = prevCenter;
                     }
                     completion:^(BOOL finished){
                         self.logoImageView.hidden = YES;
                         self.loginInfoContainer.hidden = YES;
                         self.aboutButton.hidden = YES;
                     }];
    
    // Apply shadow to text (label is transparent now)
    [LoginViewController applyShadowToView:self.attributionLabel];
    
    self.attributionLabel.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.15f];
    
    // Round label corners
    self.attributionLabel.layer.cornerRadius = 10.0f;
    self.attributionLabel.layer.masksToBounds = YES;
}

-(void)hideAttributionLabel
{
    self.logoImageView.hidden = NO;
    self.loginInfoContainer.hidden = NO;
    self.aboutButton.hidden = NO;
    
    CGPoint prevCenter = self.attributionLabel.center;
    [UIView animateWithDuration:0.2f
                          delay:0.0f
                        options:UIViewAnimationOptionTransitionNone
                     animations:^{
                         self.logoImageView.alpha = 1.0f;
                         self.loginInfoContainer.alpha = 1.0f;
                         self.aboutButton.alpha = 1.0f;
                         // Move attributionLabel off the bottom of the screen
                         self.attributionLabel.center = CGPointMake(self.attributionLabel.center.x, self.attributionLabel.center.y + (self.view.frame.size.height - self.attributionLabel.frame.origin.y));
                     }
                     completion:^(BOOL finished){
                         self.attributionLabel.hidden = YES;
                         // Move attributionLabel back
                         self.attributionLabel.center = prevCenter;
                     }];
}

#pragma mark - Text Field Delegate Methods

/**
 * Advance text field to text field with next tag.
 */
- (BOOL)textFieldShouldReturn:(UITextField *)textField;
{
    NSInteger nextTag = textField.tag + 1;

    UIResponder *nextResponder = [textField.superview viewWithTag:nextTag];
    if (nextResponder) {
        [nextResponder becomeFirstResponder];
    } else if (textField != self.passwordField) {
        [textField resignFirstResponder];
    }
    
    if (textField == self.passwordField) {
        [self pushedLoginButton:textField];
    }

    return NO;
}

@end
