//
//  BrowserHelper.m
//  Commons-iOS
//
//  Created by Brion on 2/1/13.

#import "BrowserHelper.h"

@interface BrowserHelper ()

- (void)populateBrowserSettings;

@end

@implementation BrowserHelper
{
    NSMutableDictionary *browserSettings;
}

- (id)init
{
    self = [super init];
    if (self) {
        browserSettings = [[NSMutableDictionary alloc] init];
        [self populateBrowserSettings];
    }
    return self;
}

- (void)populateBrowserSettings
{    
    // To open URLs in specific browsers the urls must be formatted according to a scheme specific to
    // that browser. These schemes are not consistent between browsers. The "browserSettings"
    // dictionary lets us specify, for each browser, which url scheme keywords are used with which
    // protocols (by setting "httpScheme", "httpsScheme" or even "ftpScheme" key-value pairs). The
    // formatting can also be specified by setting the "urlFormat" key-value pair.
    browserSettings[@"Chrome"] =    @{
                                      @"httpScheme":@"googlechrome",
                                      @"httpsScheme":@"googlechromes",
                                      @"urlFormat": @"[scheme]://[url]"
                                      };
    
    browserSettings[@"Dolphin"] =   @{
                                      @"httpScheme":@"dolphin",
                                      @"httpsScheme":@"dolphin",
                                      @"urlFormat": @"[scheme]://[proto]://[url]"
                                      };

    browserSettings[@"Opera"] =     @{
                                      @"httpScheme":@"ohttp",
                                      @"httpsScheme":@"ohttps",
                                      @"urlFormat": @"[scheme]://[url]"
                                      };
    
    browserSettings[@"Safari"] =    @{
                                      @"httpScheme":@"http",
                                      @"httpsScheme":@"https",
                                      @"urlFormat": @"[scheme]://[url]"
                                      };
}

-(bool)isBrowserInstalled:(NSString *)browserName
{
    if (![browserSettings objectForKey:browserName]) return NO;
    
    return ([[UIApplication sharedApplication] canOpenURL: [self formatURL:[NSURL URLWithString:@"http://"] forBrowser:browserName]]);
}
    
-(NSArray *)getInstalledSupportedBrowserNames
{
    // Get array of just the installed supported browsers
    NSArray *browsers = [[browserSettings allKeys] filteredArrayUsingPredicate: [NSPredicate predicateWithBlock: ^BOOL(NSString *browserName, NSDictionary *bind){
        return [self isBrowserInstalled:browserName];
    }]];
        
    // Return the array of installed browser names, but sort it first
    return [browsers sortedArrayUsingComparator:^(NSString* a, NSString* b) {
        return [a compare:b options:nil];
    }];
}

- (NSURL *)formatURL:(NSURL*) urlWithProtocol forBrowser:(NSString *)browser
{   // Returns url formatted for opening in specified browser. Assumes the url
    // it is passed includes protocol

    // Special case if "browser" is Chrome and it supports googlechrome-x-callback scheme
    // This is to enable support for a "Commons" back button in Chrome to allow quick return
    // to this app after opening link in Chrome. Reminder: an addition to the app's plist
    // file had to be made to allow this "googlechrome-x-callback" url scheme to work - see
    // the "CFBundleURLTypes" key in the plist
    if([browser isEqualToString:@"Chrome"]){
        // Ensure installed chome version supports googlechrome-x-callback before using it,
        // "getURLFormattedForChromeCallbackFromURL:" will return nil if the installed Chrome
        // browser does not support googlechrome-x-callback
        NSString *chromeCallbackURL = [self getURLFormattedForChromeCallbackFromURL:[urlWithProtocol absoluteString]];
        if (chromeCallbackURL) return [NSURL URLWithString:chromeCallbackURL];
    }

    NSString *urlStr = [urlWithProtocol absoluteString];
    NSDictionary *settings = [browserSettings objectForKey:browser];
    NSInteger colonPosition = [urlStr rangeOfString:@"://"].location;
    NSString *urlStrNoProtocol, *protocol = nil;
    if (colonPosition != NSNotFound){
        urlStrNoProtocol = [urlStr substringFromIndex:colonPosition + 3];
        protocol = [urlStr substringToIndex:colonPosition];
    }
    
    NSString *urlFormat = settings[@"urlFormat"];
    NSString *settingsScheme = [protocol stringByAppendingString:@"Scheme"];
    if ([settings objectForKey:settingsScheme]) {
        urlFormat = [urlFormat stringByReplacingOccurrencesOfString:@"[scheme]" withString:settings[settingsScheme]];
    }
    
    urlFormat = [urlFormat stringByReplacingOccurrencesOfString:@"[url]" withString:urlStrNoProtocol];
    urlFormat = [urlFormat stringByReplacingOccurrencesOfString:@"[proto]" withString:protocol];
    
    return [NSURL URLWithString:urlFormat];
}

-(NSString *)getURLFormattedForChromeCallbackFromURL:(NSString *)url
{
    // See https://github.com/GoogleChrome/OpenInChrome for sample app using "googlechrome-x-callback"
    if ([[UIApplication sharedApplication] canOpenURL: [NSURL URLWithString:@"googlechrome-x-callback://"]]){
        return [NSString stringWithFormat:
                         @"googlechrome-x-callback://x-callback-url/open/?x-source=%@&url=%@&x-success=%@&create-new-tab",
                         [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"],
                         url,
                         @"wikimedia-commons%3A%2F%2F"
                         ];
    }
    return nil;
}

@end
