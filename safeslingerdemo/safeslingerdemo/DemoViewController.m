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

#import "DemoViewController.h"

@interface DemoViewController ()

@end

@implementation DemoViewController

@synthesize infoPanel, exchangeButton, secretData, hostField, hostLabel, secretLabel, proto, scrollView;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.navigationItem setTitle:NSLocalizedString(@"demo_app_name", @"SafeSlinger Exchange Demo")];
    // Do any additional setup after loading the view from its nib.
    [self.infoPanel setText: NSLocalizedString(@"demo_note", @"NOTE: This is a simple demo using the SafeSlinger Exchange library for software developers. If you want to experience a full implementation of the exchange, try the SafeSlinger Messenger app on <a href=\"market://details?id=edu.cmu.cylab.starslinger\">Google Play</a>. Full source code is available on <a href=\"http://github.com/safeslingerproject\">GitHub</a>.")];
    [self.secretLabel setText: NSLocalizedString(@"demo_secret_title", @"My Secret")];
    [self.hostLabel setText: NSLocalizedString(@"demo_hostname_title", @"Server Host Name")];
    [self.secretData setPlaceholder: NSLocalizedString(@"demo_secret_hint", @"i.e. key, password, anything")];
    [self.hostField setPlaceholder: NSLocalizedString(@"demo_hostname_hint", @"i.e. myappengine.appspot.com")];
    _originalFrame = self.view.frame;
}


-(IBAction)ShowHelp:(id)sender
{
    UIAlertView *help = [[UIAlertView alloc] initWithTitle: NSLocalizedString(@"demo_app_name", @"SafeSlinger Exchange Demo")
                                                    message:NSLocalizedString(@"demo_instruct", @"DEMO:\nYou may build and run your own server, OR use ours: slinger-demo.appspot.com. A host name and a secret are required.")
                                                   delegate: nil
                                          cancelButtonTitle: NSLocalizedString(@"btn_OK", @"OK")
                                          otherButtonTitles: nil];
    [help show];
    help = nil;
}

- (void)viewWillAppear:(BOOL)animated
{
    [hostField resignFirstResponder];
    [secretData resignFirstResponder];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShown:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [hostField resignFirstResponder];
    [secretData resignFirstResponder];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIKeyboardWillShowNotification
                                                  object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIKeyboardWillHideNotification
                                                  object:nil];
}

- (void)keyboardWillShown:(NSNotification *)notification
{
    scrollView.contentSize = CGSizeMake(_originalFrame.size.width,_originalFrame.size.height*1.5);
}

- (void)keyboardWillHide:(NSNotification *)notification
{
    scrollView.contentSize = CGSizeMake(_originalFrame.size.width,_originalFrame.size.height);
}

-(IBAction)BegineExchange:(id)sender
{
    proto = [[safeslingerexchange alloc]init];
    if([proto SetupExchange: self ServerHost:hostField.text VersionNumber:@"1.7.0"])
        [proto BeginExchange: [secretData.text dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma UITextFieldDelegate Methods
- (void)textFieldDidBeginEditing:(UITextField *)textField
{
    
}
- (void)textFieldDidEndEditing:(UITextField *)textField
{
    
}
- (BOOL)textFieldShouldEndEditing:(UITextField *)textField
{
    return YES;
}
- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return NO;
}

#pragma SafeSlingerDelegate Methods
- (void)EndExchange:(int)status_code ErrorString:(NSString*)error_str ExchangeSet: (NSArray*)exchange_set
{
    [self.navigationController popToRootViewControllerAnimated:YES];
    switch(status_code)
    {
        case RESULT_EXCHANGE_OK:
            // parse the exchanged data
            [self ParseData:exchange_set];
            break;
        case RESULT_EXCHANGE_CANCELED:
            // handle canceled result
            {
                NSLog(@"Exchange Error: %@", error_str);
            }
            break;
        default:
            break;
    }
}

- (void)ParseData: (NSArray*)exchangeset
{
    NSString *title = [NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"demo_results", @"Results"), NSLocalizedString(@"demo_result_success", @"Success")];
    
    int i = 0;
    NSMutableString *result = [NSMutableString string];
    [result appendFormat: NSLocalizedString(@"demo_result_mine", @"secret %d (mine): %@"), i, secretData.text];
    [result appendString: _NEWLINE];
    
    for (i =0; i<[exchangeset count];i++)
    {
        [result appendFormat: NSLocalizedString(@"demo_result_theirs", @"secret %d (theirs): %@"), i+1, [[NSString alloc] initWithData:[exchangeset objectAtIndex:i] encoding:NSUTF8StringEncoding]];
        [result appendString: _NEWLINE];
    }
    
    // Display using UIAlertView
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle: title
                                                    message: result
                                                   delegate: nil
                                          cancelButtonTitle: NSLocalizedString(@"btn_OK", @"OK")
                                          otherButtonTitles: nil];
    [alert show];
    alert = nil;
}


@end
