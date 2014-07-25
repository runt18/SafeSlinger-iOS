/*
 * The MIT License (MIT)
 *
 * Copyright (c) 2010-2014 Carnegie Mellon University
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import "AppDelegate.h"
#import "SafeSlingerDB.h"
#import "Utility.h"
#import "BackupCloud.h"
#import "ContactCellView.h"
#import "MessageReceiver.h"
#import "SSEngine.h"
#import "IdleHandler.h"
#import "UniversalDB.h"
#import "ErrorLogger.h"
#import "FunctionView.h"

#import <AddressBook/AddressBook.h>
#import <Crashlytics/Crashlytics.h>
#import <UAirship.h>
#import <UAPush.h>
#import <UAAnalytics.h>
#import <UAConfig.h>

@implementation AppDelegate

@synthesize DbInstance, UDbInstance, tempralPINCode;
@synthesize IdentityName, IdentityNum, RootPath, IdentityImage;
@synthesize BackupSys, SelectContact, MessageInBox, bgTask;

-(NSString*) getVersionNumber
{
#ifdef BETA
    return [NSString stringWithFormat:@"%@-beta", [[[NSBundle mainBundle] infoDictionary]objectForKey: @"CFBundleVersion"]];
#else
    return [[[NSBundle mainBundle] infoDictionary]objectForKey: @"CFBundleVersion"];
#endif
}

-(int) getVersionNumberByInt
{
    NSArray *versionArray = [[[[NSBundle mainBundle] infoDictionary]objectForKey: @"CFBundleVersion"] componentsSeparatedByString:@"."];
    
    int version = 0;
    for(int i=0;i<[versionArray count];i++)
    {
        NSString* tmp = [versionArray objectAtIndex:i];
        version = version | ([tmp intValue] << (8*(3-i)));
    }
    return version;
}


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [Crashlytics startWithAPIKey:@"a9f2629c171299fa2ff44a07abafb7652f4e1d5c"];
    [[Crashlytics sharedInstance]setDebugMode:YES];
    
    // get root path
	NSArray *arr = [[NSArray alloc] initWithArray: NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES)];
	RootPath = [arr objectAtIndex: 0];
    DEBUGMSG(@"RootPath = %@", RootPath);
    
    // Prepare Database Object
    DbInstance = [[SafeSlingerDB alloc]init];
    
    NSInteger DB_KEY_INDEX = [[NSUserDefaults standardUserDefaults] integerForKey: kDEFAULT_DB_KEY];
    DEBUGMSG(@"DB_KEY_INDEX = %ld", (long)DB_KEY_INDEX);
    if(DB_KEY_INDEX>0){
        [DbInstance LoadDBFromStorage: [NSString stringWithFormat:@"%@-%ld", DATABASE_NAME, (long)DB_KEY_INDEX]];
    }else{
        [DbInstance LoadDBFromStorage: nil];
    }
    
    UDbInstance = [[UniversalDB alloc]init];
    [UDbInstance LoadDBFromStorage];
    
    if([DbInstance GetProfileName]&&[[NSUserDefaults standardUserDefaults] integerForKey:kAPPVERSION]<[self getVersionNumberByInt])
    {
        DEBUGMSG(@"Apply Version 1.7 Changes ...");
        [self ApplyChangeForV17];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey: kRequirePushNotification];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey: kRequireMicrophonePrivacy];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey: kRequirePushNotification];
    }
    
    [[NSUserDefaults standardUserDefaults] setInteger:[self getVersionNumberByInt] forKey: kAPPVERSION];
    
    if ([[UIApplication sharedApplication] enabledRemoteNotificationTypes] != UIRemoteNotificationTypeNone)
    {
        [UAirship setLogLevel:UALogLevelTrace];
        UAConfig *config = [UAConfig defaultConfig];
        
        // Call takeOff (which creates the UAirship singleton)
        [UAirship takeOff: config];
        [UAirship setLogLevel:UALogLevelError];
        [[UAPush shared]setAutobadgeEnabled:YES];
        [UAPush shared].notificationTypes = (UIRemoteNotificationTypeBadge |
                                             UIRemoteNotificationTypeAlert);
    }
    
    // message receiver
    MessageInBox = [[MessageReceiver alloc]init:DbInstance UniveralTable:UDbInstance Version:[self getVersionNumberByInt]];
    
    // backup system
    BackupSys = [[BackupCloudUtility alloc]init];
    
    return YES;
}

- (void)registerPushToken
{
    DEBUGMSG(@"registerPushToken");
    
    [UAirship setLogLevel:UALogLevelTrace];
    
    UAConfig *config = [UAConfig defaultConfig];
    DEBUGMSG(@"config: %@", [config description]);
    
    // Call takeOff (which creates the UAirship singleton)
    [UAirship takeOff: config];
    [UAirship setLogLevel:UALogLevelError];
    [[UAPush shared]setAutobadgeEnabled:YES];
    [UAPush shared].notificationTypes = (UIRemoteNotificationTypeBadge |
                                         UIRemoteNotificationTypeAlert);
    [[UAPush shared]registerForRemoteNotifications];
}

- (void) removeContactLink
{
    int ContactID = NonLink;
    NSData *contact = [NSData dataWithBytes:&ContactID length:sizeof(ContactID)];
    [DbInstance InsertOrUpdateConfig:contact withTag:@"IdentityNum"];
}

-(void) saveConactDataWithoutChaningName: (int)ContactID
{
    if(ContactID == NonExist) return;
    self.IdentityNum = ContactID;
    NSData *contact = [NSData dataWithBytes:&ContactID length:sizeof(ContactID)];
    [DbInstance InsertOrUpdateConfig:contact withTag:@"IdentityNum"];
    
    // Try to backup
    [BackupSys RecheckCapability];
    [BackupSys PerformBackup];
}

-(void) saveConactData: (int)ContactID Firstname:(NSString*)FN Lastname:(NSString*)LN
{
	if(ContactID == NonExist) return;
 
    NSString* oldValue = [DbInstance GetProfileName];
                       
    if(FN)
    {
        [DbInstance InsertOrUpdateConfig:[FN dataUsingEncoding:NSUTF8StringEncoding] withTag:@"Profile_FN"];
    }else{
        [DbInstance RemoveConfigTag:@"Profile_FN"];
    }
    
    if(LN)
    {
        [DbInstance InsertOrUpdateConfig:[LN dataUsingEncoding:NSUTF8StringEncoding] withTag:@"Profile_LN"];
    }else{
        [DbInstance RemoveConfigTag:@"Profile_LN"];
    }
    
    NSString* newValue = [DbInstance GetProfileName];
    if(![oldValue isEqualToString:newValue])
    {
        //change information for kDB_LIST
        NSArray *infoarr = [[NSUserDefaults standardUserDefaults] stringArrayForKey: kDB_LIST];
        NSInteger index = [[NSUserDefaults standardUserDefaults] integerForKey: kDEFAULT_DB_KEY];
        
        NSMutableArray *arr = [NSMutableArray arrayWithArray:infoarr];
        
        NSString *keyinfo = [NSString stringWithFormat:@"%@\n%@ %@", [NSString composite_name:FN withLastName:LN], NSLocalizedString(@"label_Key", @"Key:"), [NSString ChangeGMT2Local:[SSEngine getSelfGenKeyDate] GMTFormat:DATABASE_TIMESTR LocalFormat: @"yyyy-MM-dd HH:mm:ss"]];
        
        [arr setObject:keyinfo atIndexedSubscript:index];
        [[NSUserDefaults standardUserDefaults] setObject:arr forKey: kDB_LIST];
    }
    
    self.IdentityName = [NSString composite_name:FN withLastName:LN];
	[self saveConactDataWithoutChaningName:ContactID];
}

-(void)ApplyChangeForV17
{
    if([DbInstance PatchForTokenStoreTable])
        DEBUGMSG(@"Patch done...");
    
    // save contact index to database
    if([DbInstance GetProfileName]&&([DbInstance GetConfig:@"IdentityNum"]==nil))
    {
        DEBUGMSG(@"ApplyChangeForV17");
        int contact_id = NonLink;
        NSString *contactsFile = [NSString stringWithFormat: @"%@/contact", RootPath];
        if ([[NSFileManager defaultManager] fileExistsAtPath: contactsFile])
        {
            NSData *data = [[NSFileManager defaultManager] contentsAtPath: contactsFile];
            const char *bytes = [data bytes];
            bytes += 8;
            contact_id = *(int *)bytes;
            DEBUGMSG(@"contact_id = %d", contact_id);
        }
        
        NSData *contact = [NSData dataWithBytes:&contact_id length:sizeof(contact_id)];
        [DbInstance InsertOrUpdateConfig:contact withTag:@"IdentityNum"];
    }
    
    // backup keys into database
    if(![DbInstance GetConfig:@"KEYID"])
    {
        NSString *floc = [NSString stringWithFormat: @"%@/gendate.dat", RootPath];
        if ([[NSFileManager defaultManager] fileExistsAtPath: floc])
        {
            NSData *data = [[NSFileManager defaultManager] contentsAtPath: floc];
            DEBUGMSG(@"data = %s", [data bytes]);
            [DbInstance InsertOrUpdateConfig:data withTag:@"KEYID"];
        }
    }
    
    if(![DbInstance GetConfig:@"KEYGENDATE"])
    {
        NSString *floc = [NSString stringWithFormat: @"%@/gendate.txt", RootPath];
        if ([[NSFileManager defaultManager] fileExistsAtPath: floc])
        {
            NSData *data = [[NSFileManager defaultManager] contentsAtPath: floc];
            DEBUGMSG(@"data = %s", [data bytes]);
            [DbInstance InsertOrUpdateConfig:data withTag:@"KEYGENDATE"];
        }
    }
    
    if(![DbInstance GetConfig:@"ENCPUB"])
    {
        NSString *floc = [NSString stringWithFormat: @"%@/pubkey.pem", RootPath];
        if ([[NSFileManager defaultManager] fileExistsAtPath: floc])
        {
            NSData *data = [[NSFileManager defaultManager] contentsAtPath: floc];
            DEBUGMSG(@"data = %s", [data bytes]);
            [DbInstance InsertOrUpdateConfig:data withTag:@"ENCPUB"];
        }
    }
    
    if(![DbInstance GetConfig:@"SIGNPUB"])
    {
        NSString *floc = [NSString stringWithFormat: @"%@/spubkey.pem", RootPath];
        if ([[NSFileManager defaultManager] fileExistsAtPath: floc])
        {
            NSData *data = [[NSFileManager defaultManager] contentsAtPath: floc];
            DEBUGMSG(@"data = %s", [data bytes]);
            [DbInstance InsertOrUpdateConfig:data withTag:@"SIGNPUB"];
        }
    }
    
    if(![DbInstance GetConfig:@"ENCPRI"])
    {
        NSString *floc = [NSString stringWithFormat: @"%@/prikey.pem", RootPath];
        if ([[NSFileManager defaultManager] fileExistsAtPath: floc])
        {
            NSData *data = [[NSFileManager defaultManager] contentsAtPath: floc];
            DEBUGMSG(@"data(%lu) = %@", (unsigned long)[data length], data);
            [DbInstance InsertOrUpdateConfig:data withTag:@"ENCPRI"];
        }
    }
    
    if(![DbInstance GetConfig:@"SIGNPRI"])
    {
        NSString *floc = [NSString stringWithFormat: @"%@/sprikey.pem", RootPath];
        if ([[NSFileManager defaultManager] fileExistsAtPath: floc])
        {
            NSData *data = [[NSFileManager defaultManager] contentsAtPath: floc];
            DEBUGMSG(@"data(%lu) = %@", (unsigned long)[data length], data);
            [DbInstance InsertOrUpdateConfig:data withTag:@"SIGNPRI"];
        }
    }
    
    // Register Default
    if([DbInstance GetProfileName]&&![[NSUserDefaults standardUserDefaults] stringArrayForKey: kDB_KEY])
    {
        DEBUGMSG(@"Apply patch for DB_KEY...");
        // Add default setting
        NSArray *arr = [NSArray arrayWithObjects: DATABASE_NAME, nil];
        [[NSUserDefaults standardUserDefaults] setObject:arr forKey: kDB_KEY];
        NSString *keyinfo = [NSString stringWithFormat:@"%@\n%@ %@", [DbInstance GetProfileName], NSLocalizedString(@"label_Key", @"Key:"), [NSString ChangeGMT2Local:[SSEngine getSelfGenKeyDate] GMTFormat:DATABASE_TIMESTR LocalFormat: @"yyyy-MM-dd HH:mm:ss"]];
        arr = [NSArray arrayWithObjects: keyinfo, nil];
        [[NSUserDefaults standardUserDefaults] setObject:arr forKey: kDB_LIST];
        [[NSUserDefaults standardUserDefaults] setInteger:0 forKey: kDEFAULT_DB_KEY];
    }
    
    DEBUGMSG(@"Error log: %@", [ErrorLogger GetLogs]);
}

-(BOOL)checkIdentity
{
    DEBUGMSG(@"checkIdentity");
    BOOL ret = NO;
    
    // Identity checking, check if conact is linked
    NSData* contact_data = [DbInstance GetConfig:@"IdentityNum"];
    if(contact_data)
    {
        [contact_data getBytes:&IdentityNum];
    }else{
        IdentityNum = NonExist;
    }
    
    DEBUGMSG(@"IdentityNum = %d", IdentityNum);
    
    switch (IdentityNum) {
        case NonExist:
            break;
        case NonLink:
            IdentityName = [DbInstance GetProfileName];
            ret = YES;
            break;
        default:
            IdentityName = [DbInstance GetProfileName];
            // get self photo cache
            if ([UtilityFunc checkContactPermission])
            {
                // get self photo first, cached.
                CFErrorRef error = NULL;
                ABAddressBookRef aBook = ABAddressBookCreateWithOptions(NULL, &error);
                ABAddressBookRequestAccessWithCompletion(aBook, ^(bool granted, CFErrorRef error) {
                    if (!granted) {
                    }
                });
        
                ABRecordRef aRecord = ABAddressBookGetPersonWithRecordID(aBook, IdentityNum);
        
                // set self photo
                CFDataRef imgData = ABPersonCopyImageData(aRecord);
                if(imgData)
                {
                    IdentityImage = UIImageJPEGRepresentation([[UIImage imageWithData:(__bridge NSData *)imgData]scaleToSize: CGSizeMake(45.0f, 45.0f)], 0.9);
                    CFRelease(imgData);
                }
                if(aBook)CFRelease(aBook);
                ret = YES;
            }
            break;
    }
    
    DEBUGMSG(@"IdentityName = %@, IdentityNum = %d", IdentityName, IdentityNum);
    
    return ret;
}


#pragma mark Handle Push Notifications
- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo
{
    DEBUGMSG(@"didReceiveRemoteNotification: fetchCompletionHandler");
    
    if([self checkIdentity])
    {
        if ([UIApplication sharedApplication].applicationIconBadgeNumber>0) {
            NSString* nonce = [[[userInfo objectForKey:@"aps"]objectForKey:@"nonce"]stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            DEBUGMSG(@"incoming nonce: %@", nonce);
            [MessageInBox FetchSingleMessage:nonce];
        }
    }
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result))handler
{
    DEBUGMSG(@"didReceiveRemoteNotification: fetchCompletionHandler");
    
    if([self checkIdentity])
    {
        if ([UIApplication sharedApplication].applicationIconBadgeNumber>0) {
            NSString* nonce = [[[userInfo objectForKey:@"aps"]objectForKey:@"nonce"]stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            DEBUGMSG(@"incoming nonce: %@", nonce);
            [MessageInBox FetchSingleMessage:nonce];
        }
    }
}

- (void)application:(UIApplication *)app didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    UALOG(@"APN device token: %@", deviceToken);
    // Updates the device token and registers the token with UA
    [[UAPush shared] registerDeviceToken:deviceToken];
    // Sets the alias. It will be sent to the server on registration.
    [UAPush shared].alias = [UIDevice currentDevice].name;
    // Add AppVer tag
    [[UAPush shared]addTagToCurrentDevice:[NSString stringWithFormat:@"AppVer = %@", [self getVersionNumber]]];
    [[UAPush shared]updateRegistration];
    
    //Do something when notifications are disabled altogther
    if ([app enabledRemoteNotificationTypes] == UIRemoteNotificationTypeNone) {
        UALOG(@"iOS Registered a device token, but nothing is enabled!");
        //only alert if this is the first registration, or if push has just been
        //re-enabled
        if ([UAirship shared].deviceToken != nil) { //already been set this session
            DEBUGMSG(NSLocalizedString(@"iOS_notificationError1", @"Unable to turn on notifications. Use the \"Settings\" app to enable notifications."));
        }
        //Do something when some notification types are disabled
    } else if ([app enabledRemoteNotificationTypes] != [UAPush shared].notificationTypes) {
        
        DEBUGMSG(@"Failed to register a device token with the requested services. Your notifications may be turned off.");
        //only alert if this is the first registration, or if push has just been
        //re-enabled
    }
}

- (void)application:(UIApplication *)app didFailToRegisterForRemoteNotificationsWithError:(NSError *)err
{
    DEBUGMSG(@"Failed To Register For Remote Notifications With Error: %@", err);
}
							
- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    DEBUGMSG(@"BadgeNumber = %ld", (long)[UIApplication sharedApplication].applicationIconBadgeNumber);
    
    if([self checkIdentity])
    {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidTimeout:) name:KSDIdlingWindowTimeoutNotification object:nil];
        
        if ([UIApplication sharedApplication].applicationIconBadgeNumber>0) {
            DEBUGMSG(@"Fetch %ld messages...", (long)[UIApplication sharedApplication].applicationIconBadgeNumber);
            [MessageInBox FetchMessageNonces: (int)[UIApplication sharedApplication].applicationIconBadgeNumber];
        }
    }
}

-(void)applicationDidTimeout: (NSNotification *)notification
{
    DEBUGMSG (@"time exceeded!!");
    if([self.window.rootViewController isMemberOfClass:[UINavigationController class]])
    {
        UINavigationController* nag = (UINavigationController*)self.window.rootViewController;
        if([nag.visibleViewController isMemberOfClass:[FunctionView class]])
        {
            FunctionView* view = (FunctionView*)nag.visibleViewController;
            [view performSegueWithIdentifier:@"Logout" sender:self];
        }
    }
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    [DbInstance CloseDB];
    DbInstance = nil;
    [UDbInstance CloseDB];
    UDbInstance = nil;
}

@end
