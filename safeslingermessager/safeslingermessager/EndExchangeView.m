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

#import "EndExchangeView.h"
#import "Utility.h"
#import "ErrorLogger.h"
#import "AppDelegate.h"
#import "SafeSlingerDB.h"
#import "BackupCloud.h"

@interface EndExchangeView ()

@end

@implementation EndExchangeView

@synthesize selectionTable, contactList, selections;
@synthesize delegate, Hint, ImportBtn;

- (void)viewDidLoad {
    [super viewDidLoad];
    
    delegate = (AppDelegate*)[[UIApplication sharedApplication]delegate];
    
    // Do any additional setup after loading the view.
    [ImportBtn setTitle:NSLocalizedString(@"btn_Import", @"Import") forState: UIControlStateNormal];
    
    // setup hint message
    [Hint setText: NSLocalizedString(@"label_SaveInstruct", @"Exchange Complete!  Select member data to save to your Address Book:")];
}

- (void)viewWillAppear:(BOOL)animated{
	if (selections != NULL) free(selections);
	selections = malloc(sizeof(BOOL) * [contactList count]);
	for (int i = 0; i < [contactList count]; i++)
		selections[i] = YES;
	[selectionTable reloadData];
}

- (IBAction)DisplayHow:(id)sender {
    UIAlertView *message = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"title_save", @"End Exchange")
                                                      message:NSLocalizedString(@"help_save", @"When finished, the protocol will reveal a list of the identity data exchanged. Select the contacts you wish to save and press 'Import'.";)
                                                     delegate:nil
                                            cancelButtonTitle:NSLocalizedString(@"btn_Close", @"Close")
                                            otherButtonTitles:nil];
    [message show];
}

- (IBAction)Import:(id)sender {
    NSMutableDictionary *mapping = [NSMutableDictionary dictionary];
    int importedcount = 0;
	
	
	if(ABAddressBookGetAuthorizationStatus() == kABAuthorizationStatusAuthorized) {
		// contact permission is enabled, update address book.
		CFErrorRef error = NULL;
		ABAddressBookRef aBook = NULL;
		aBook = ABAddressBookCreateWithOptions(NULL, &error);
		ABAddressBookRequestAccessWithCompletion(aBook, ^(bool granted, CFErrorRef error) {
			if (!granted) {
			}
		});
		
		CFArrayRef allPeople = ABAddressBookCopyArrayOfAllPeople(aBook);
		// remove old duplicates
		
		[UtilityFunc RemoveDuplicates:aBook AdressList:allPeople CompareArray:mapping];
		
		// add one by one
		if (selections) {
			for (int i = 0; i < [contactList count]; i++) {
				if (selections[i]) {
					if(![UtilityFunc AddContactEntry:aBook TargetRecord:(__bridge ABRecordRef)([contactList objectAtIndex:i])]) {
						[[[[iToast makeText: NSLocalizedString(@"error_ContactInsertFailed", @"Contact insert failed.")]
						   setGravity:iToastGravityCenter] setDuration:iToastDurationNormal] show];
					}
				}
			}
		}
		
		if(!ABAddressBookSave(aBook, &error)) {
			[ErrorLogger ERRORDEBUG:[NSString stringWithFormat:@"ERROR: Unable to Save ABAddressBook. Error = %@", CFErrorCopyDescription(error)]];
		}
		
		if(allPeople)CFRelease(allPeople);
		if(aBook)CFRelease(aBook);
	}
	
    // update keys and tokens
    for (int i = 0; i < [contactList count]; i++) {
		ContactEntry *contact = [ContactEntry new];
        NSData *keyelement = nil;
        NSData *token = nil;
        NSString *comparedtoken = nil;
		
        ABRecordRef aRecord = (__bridge ABRecordRef)[contactList objectAtIndex:i];
        contact.firstName = (__bridge_transfer NSString*)ABRecordCopyValue(aRecord, kABPersonFirstNameProperty);
        contact.lastName = (__bridge_transfer NSString*)ABRecordCopyValue(aRecord, kABPersonLastNameProperty);
		contact.recordId = ABRecordGetRecordID(aRecord);
        if(contact.firstName == nil && contact.lastName == nil) {
            [[[[iToast makeText: NSLocalizedString(@"error_VcardParseFailure", @"vCard parse failed.")]
               setGravity:iToastGravityCenter] setDuration:iToastDurationNormal] show];
            continue;
        }
        
        // Get SafeSlinger Fields
        ABMultiValueRef allIMPP = ABRecordCopyValue(aRecord, kABPersonInstantMessageProperty);
        for (CFIndex i = 0; i < ABMultiValueGetCount(allIMPP); i++) {
            CFDictionaryRef anIMPP = ABMultiValueCopyValueAtIndex(allIMPP, i);
            CFStringRef service = CFDictionaryGetValue(anIMPP, kABPersonInstantMessageServiceKey);
			
            if ([(__bridge NSString*)service caseInsensitiveCompare:@"SafeSlinger-PubKey"] == NSOrderedSame) {
                keyelement = [Base64 decode:(NSString *)CFDictionaryGetValue(anIMPP, kABPersonInstantMessageUsernameKey)];
                keyelement = [NSData dataWithBytes:[keyelement bytes] length:[keyelement length]];
            } else if([(__bridge NSString*)service caseInsensitiveCompare:@"SafeSlinger-Push"] == NSOrderedSame) {
                comparedtoken = (NSString *)CFDictionaryGetValue(anIMPP, kABPersonInstantMessageUsernameKey);
                token = [Base64 decode:comparedtoken];
            }
			
            if(anIMPP)CFRelease(anIMPP);
        }
		
        if(allIMPP)CFRelease(allIMPP);
        
        if([keyelement length]==0) {
            [[[[iToast makeText: NSLocalizedString(@"error_AllMembersMustUpgradeBadKeyFormat", @"All members must upgrade, some are using older key formats.")] setGravity:iToastGravityCenter] setDuration:iToastDurationNormal] show];
            continue;
        }
        
        if([token length]==0) {
            [[[[iToast makeText: NSLocalizedString(@"error_AllMembersMustUpgradeBadPushToken", @"All members must upgrade, some are using older push token formats.")] setGravity:iToastGravityCenter] setDuration:iToastDurationNormal] show];
            continue;
        }
		
		[contact setKeyInfo:keyelement];
        
        int offset = 0, tokenlen = 0;
        const char* p = [token bytes];
		
		contact.devType = ntohl(*(int *)(p+offset));
        offset += 4;
        
        tokenlen = ntohl(*(int *)(p+offset));
        offset += 4;
		
        contact.pushToken = [[NSString stringWithCString:[[NSData dataWithBytes:p+offset length:tokenlen]bytes] encoding:NSASCIIStringEncoding] substringToIndex:tokenlen];
        
        // get photo if possible
        if(ABPersonHasImageData(aRecord)) {
            CFDataRef photo = ABPersonCopyImageDataWithFormat(aRecord, kABPersonImageFormatThumbnail);
            contact.photo = UIImageJPEGRepresentation([UIImage imageWithData:(__bridge NSData *)photo], 0.9);
            CFRelease(photo);
        }
		
		contact.exchangeType = Exchanged;
        
        // update token
        if(contact.pushToken) {
            // update or insert entry for new recipient
            if(![delegate.DbInstance addNewRecipient:contact]) {
                [[[[iToast makeText: NSLocalizedString(@"error_UnableToUpdateRecipientInDB", @"Unable to update the recipient database.")]
                   setGravity:iToastGravityCenter] setDuration:iToastDurationNormal] show];
                continue;
            }
            
            importedcount++;
            // add to temp structure for address book update
			if (selections[i]) {
                [mapping setObject:[NSString vcardnstring:contact.firstName withLastName:contact.lastName] forKey:comparedtoken];
			}
        } else {
            DEBUGMSG(@"recipient's token is missing.");
            [[[[iToast makeText: NSLocalizedString(@"error_UnableToUpdateRecipientInDB", @"Unable to update the recipient database.")]
               setGravity:iToastGravityCenter] setDuration:iToastDurationNormal] show];
            continue;
        }
    }
    
    free(selections);
    
    DEBUGMSG(@"imported count = %d", importedcount);
    
    [[[[iToast makeText: [NSString stringWithFormat: NSLocalizedString(@"state_SomeContactsImported", @"%@ contacts imported."), [NSString stringWithFormat:@"%d", importedcount]]]
       setGravity:iToastGravityCenter] setDuration:iToastDurationNormal] show];
    
    if(importedcount>0) {
        // Try to backup
        [delegate.BackupSys RecheckCapability];
        [delegate.BackupSys PerformBackup];
    }
    
    [UtilityFunc PopToMainPanel:self.navigationController];
}

- (IBAction)Cancel:(id)sender {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle: NSLocalizedString(@"title_Question", @"Question")
                                                    message: NSLocalizedString(@"ask_QuitConfirmation", @"Quit? Are you sure?")
                                                   delegate: self
                                          cancelButtonTitle: NSLocalizedString(@"btn_No", @"No")
                                          otherButtonTitles: NSLocalizedString(@"btn_Yes", @"Yes"), nil];
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if(buttonIndex!=alertView.cancelButtonIndex) {
        contactList = nil;
        free(selections);
        [UtilityFunc PopToMainPanel:self.navigationController];
    }
}

#pragma mark UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath: [tableView indexPathForSelectedRow] animated: NO];
    if(ABAddressBookGetAuthorizationStatus()==kABAuthorizationStatusAuthorized) {
        NSInteger row = [indexPath row];
        UITableViewCell *cell = [tableView cellForRowAtIndexPath: indexPath];
        if (cell.accessoryType == UITableViewCellAccessoryNone) {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
            selections[row] = YES;
        } else if (cell.accessoryType == UITableViewCellAccessoryCheckmark) {
            cell.accessoryType = UITableViewCellAccessoryNone;
            selections[row] = NO;
        }
    }
}

#pragma mark UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [contactList count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"SaveSelectionIdentifier";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
    }
    
	NSInteger row = [indexPath row];
	ABRecordRef aRecord = (__bridge ABRecordRef)([contactList objectAtIndex:row]);
	
    NSString* fn = (__bridge NSString*)ABRecordCopyValue(aRecord, kABPersonFirstNameProperty);
    NSString* ln = (__bridge NSString*)ABRecordCopyValue(aRecord, kABPersonLastNameProperty);
    cell.textLabel.text = [NSString compositeName:fn withLastName:ln];
	
    if(ABPersonHasImageData(aRecord)) {
        CFDataRef imageData = ABPersonCopyImageDataWithFormat(aRecord, kABPersonImageFormatThumbnail);
        UIImage *image = [UIImage imageWithData: (__bridge NSData *)imageData];
        cell.imageView.image = image;
        CFRelease(imageData);
    } else {
        [cell.imageView setImage: [UIImage imageNamed:@"blank_contact.png"]];
    }
    
    if(ABAddressBookGetAuthorizationStatus() == kABAuthorizationStatusAuthorized) {
		if (selections[row]) {
			cell.accessoryType = UITableViewCellAccessoryCheckmark;
		} else {
			cell.accessoryType = UITableViewCellAccessoryNone;
		}
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    
	return cell;
}

@end
