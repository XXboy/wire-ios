// 
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
// 
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
// 


#import <PureLayout.h>
@import MobileCoreServices;
@import AVFoundation;

#import "ConversationInputBarViewController.h"
#import "ConversationInputBarViewController+Private.h"
#import "ConversationInputBarViewController+Files.h"
#import "Analytics+Events.h"
#import "UIAlertView+Zeta.h"
#import <WireExtensionComponents/WireExtensionComponents.h>
#import "ConfirmAssetViewController.h"
#import "TextView.h"
#import "CameraViewController.h"
#import "SketchViewController.h"
#import "UIView+Borders.h"
#import "UIViewController+Errors.h"

#import "ZClientViewController.h"
#import "Analytics+iOS.h"
#import "AnalyticsTracker+Sketchpad.h"
#import "AnalyticsTracker+FileTransfer.h"
#import "Wire-Swift.h"


#import "ZMUserSession+Additions.h"
#import "zmessaging+iOS.h"
#import "ZMUser+Additions.h"
#import "avs+iOS.h"
#import "Constants.h"
#import "Settings.h"
#import "GiphyViewController.h"
#import "ConversationInputBarSendController.h"
#import "FLAnimatedImage.h"
#import "MediaAsset.h"
#import "UIView+WR_ExtendedBlockAnimations.h"
#import "UIView+Borders.h"
#import "ImageMessageCell.h"
#import "WAZUIMagic.h"


@interface ConversationInputBarViewController (Commands)

- (void)runCommand:(NSArray *)args;

@end



@interface ConversationInputBarViewController (CameraViewController)
- (void)cameraButtonPressed:(id)sender;
- (void)videoButtonPressed:(id)sender;
@end

@interface ConversationInputBarViewController (Ping)

- (void)pingButtonPressed:(UIButton *)button;

@end

@interface ConversationInputBarViewController (Location) <LocationSelectionViewControllerDelegate>

- (void)locationButtonPressed:(IconButton *)sender;

@end

@interface ConversationInputBarViewController (ZMConversationObserver) <ZMConversationObserver>
@end

@interface ConversationInputBarViewController (ZMTypingChangeObserver) <ZMTypingChangeObserver>
@end

@interface ConversationInputBarViewController (Giphy)

- (void)giphyButtonPressed:(id)sender;

@end

@interface ConversationInputBarViewController (Sending)

- (void)sendButtonPressed:(id)sender;

@end

@interface  ConversationInputBarViewController (UIGestureRecognizerDelegate) <UIGestureRecognizerDelegate>

@end

@interface ConversationInputBarViewController (GiphySearchViewController) <GiphySearchViewControllerDelegate>

@end



@interface ConversationInputBarViewController ()

@property (nonatomic) IconButton *audioButton;
@property (nonatomic) IconButton *videoButton;
@property (nonatomic) IconButton *photoButton;
@property (nonatomic) IconButton *uploadFileButton;
@property (nonatomic) IconButton *sketchButton;
@property (nonatomic) IconButton *pingButton;
@property (nonatomic) IconButton *locationButton;
@property (nonatomic) IconButton *sendButton;
@property (nonatomic) IconButton *emojiButton;
@property (nonatomic) IconButton *gifButton;

@property (nonatomic) UIGestureRecognizer *singleTapGestureRecognizer;

@property (nonatomic) UserImageView *authorImageView;
@property (nonatomic) NSLayoutConstraint *collapseViewConstraint;
@property (nonatomic) TypingIndicatorView *typingIndicatorView;

@property (nonatomic) InputBar *inputBar;
@property (nonatomic) ZMConversation *conversation;

@property (nonatomic) NSSet *typingUsers;
@property (nonatomic) id <ZMConversationObserverOpaqueToken> conversationObserverToken;

@property (nonatomic) UIViewController *inputController;

@property (nonatomic) BOOL inRotation;
@end


@implementation ConversationInputBarViewController

- (instancetype)initWithConversation:(ZMConversation *)conversation
{
    self = [super init];
    if (self) {
        self.conversation = conversation;
        self.sendController = [[ConversationInputBarSendController alloc] initWithConversation:self.conversation];
        self.conversationObserverToken = [self.conversation addConversationObserver:self];
        
        if ([self.conversation shouldDisplayIsTyping]) {
            [conversation addTypingObserver:self];
            self.typingUsers = conversation.typingUsers;
        }
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardDidHide:) name:UIKeyboardDidHideNotification object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [ZMConversation removeConversationObserverForToken:self.conversationObserverToken];
    if ([self.conversation shouldDisplayIsTyping]) {
        [ZMConversation removeTypingObserver:self];
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self createSingleTapGestureRecognizer];
    
    [self createInputBar]; // Creates all input bar buttons
    [self createSendButton];
    [self createEmojiButton];
    [self createTypingIndicatorView];
    
    if (self.conversation.hasDraftMessageText) {
        self.inputBar.textView.text = self.conversation.draftMessageText;
    }
    
    [self configureAudioButton:self.audioButton];
    [self configureEmojiButton:self.emojiButton];
    
    [self.sendButton addTarget:self action:@selector(sendButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.photoButton addTarget:self action:@selector(cameraButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.videoButton addTarget:self action:@selector(videoButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.sketchButton addTarget:self action:@selector(sketchButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.uploadFileButton addTarget:self action:@selector(docUploadPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.pingButton addTarget:self action:@selector(pingButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.gifButton addTarget:self action:@selector(giphyButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.locationButton addTarget:self action:@selector(locationButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    
    if (self.conversationObserverToken == nil) {
        self.conversationObserverToken = [self.conversation addConversationObserver:self];
    }
    
    [self updateAccessoryViews];
    [self updateInputBarVisibility];
    [self updateSeparatorLineVisibility];
    [self updateTypingIndicatorVisibility];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self updateSendButtonVisibility];
    [self.inputBar updateReturnKey];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self.inputBar.textView endEditing:YES];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    [self endEditingMessageIfNeeded];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    self.inRotation = YES;
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        
    } completion:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        self.inRotation = NO;
    }];
}

- (void)setAnalyticsTracker:(AnalyticsTracker *)analyticsTracker
{
    _analyticsTracker = analyticsTracker;
    self.sendController.analyticsTracker = analyticsTracker;
}

- (void)createInputBar
{
    self.audioButton = [[IconButton alloc] init];
    self.audioButton.hitAreaPadding = CGSizeZero;
    self.audioButton.accessibilityIdentifier = @"audioButton";
    [self.audioButton setIcon:ZetaIconTypeMicrophone withSize:ZetaIconSizeTiny forState:UIControlStateNormal];
    [self.audioButton setIconColor:[UIColor accentColor] forState:UIControlStateSelected];

    self.videoButton = [[IconButton alloc] init];
    self.videoButton.hitAreaPadding = CGSizeZero;
    self.videoButton.accessibilityIdentifier = @"videoButton";
    [self.videoButton setIcon:ZetaIconTypeVideoMessage withSize:ZetaIconSizeTiny forState:UIControlStateNormal];
    
    self.photoButton = [[IconButton alloc] init];
    self.photoButton.hitAreaPadding = CGSizeZero;
    self.photoButton.accessibilityIdentifier = @"photoButton";
    [self.photoButton setIcon:ZetaIconTypeCameraLens withSize:ZetaIconSizeTiny forState:UIControlStateNormal];
    [self.photoButton setIconColor:[UIColor accentColor] forState:UIControlStateSelected];

    self.uploadFileButton = [[IconButton alloc] init];
    self.uploadFileButton.hitAreaPadding = CGSizeZero;
    self.uploadFileButton.accessibilityIdentifier = @"uploadFileButton";
    [self.uploadFileButton setIcon:ZetaIconTypePaperclip withSize:ZetaIconSizeTiny forState:UIControlStateNormal];
    
    self.sketchButton = [[IconButton alloc] init];
    self.sketchButton.hitAreaPadding = CGSizeZero;
    self.sketchButton.accessibilityIdentifier = @"sketchButton";
    [self.sketchButton setIcon:ZetaIconTypeBrush withSize:ZetaIconSizeTiny forState:UIControlStateNormal];
    
    self.pingButton = [[IconButton alloc] init];
    self.pingButton.hitAreaPadding = CGSizeZero;
    self.pingButton.accessibilityIdentifier = @"pingButton";
    [self.pingButton setIcon:ZetaIconTypePing withSize:ZetaIconSizeTiny forState:UIControlStateNormal];
    
    self.locationButton = [[IconButton alloc] init];
    self.locationButton.hitAreaPadding = CGSizeZero;
    self.locationButton.accessibilityIdentifier = @"locationButton";
    [self.locationButton setIcon:ZetaIconTypeLocationPin withSize:ZetaIconSizeTiny forState:UIControlStateNormal];
    
    self.gifButton = [[IconButton alloc] init];
    self.gifButton.hitAreaPadding = CGSizeZero;
    self.gifButton.accessibilityIdentifier = @"gifButton";
    [self.gifButton setIcon:ZetaIconTypeGif withSize:ZetaIconSizeTiny forState:UIControlStateNormal];
    
    self.inputBar = [[InputBar alloc] initWithButtons:@[self.photoButton, self.videoButton, self.sketchButton, self.gifButton, self.audioButton, self.pingButton, self.uploadFileButton, self.locationButton]];
    self.inputBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.inputBar.textView.delegate = self;
    
    [self.view addSubview:self.inputBar];
    [self.inputBar autoPinEdgesToSuperviewEdges];
    self.inputBar.editingView.delegate = self;
}

- (void)createSingleTapGestureRecognizer
{
    self.singleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onSingleTap:)];
    self.singleTapGestureRecognizer.enabled = NO;
    self.singleTapGestureRecognizer.delegate = self;
    self.singleTapGestureRecognizer.cancelsTouchesInView = YES;
    [self.view addGestureRecognizer:self.singleTapGestureRecognizer];
}

- (void)createAudioRecordViewController
{
    self.audioRecordViewController = [[AudioRecordViewController alloc] init];
    self.audioRecordViewController.view.translatesAutoresizingMaskIntoConstraints = NO;
    self.audioRecordViewController.view.hidden = true;
    self.audioRecordViewController.delegate = self;
    
    [self addChildViewController:self.audioRecordViewController];
    [self.inputBar addSubview:self.audioRecordViewController.view];
    [self.audioRecordViewController.view autoPinEdge:ALEdgeLeading toEdge:ALEdgeLeading ofView:self.inputBar.buttonContainer];
    
    CGRect recordButtonFrame = [self.inputBar convertRect:self.audioButton.bounds fromView:self.audioButton];
    CGFloat width = CGRectGetMaxX(recordButtonFrame) + 60;
    [self.audioRecordViewController.view autoSetDimension:ALDimensionWidth toSize:width];
    [self.audioRecordViewController.view autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [self.audioRecordViewController.view autoPinEdge:ALEdgeTop toEdge:ALEdgeTop ofView:self.inputBar withOffset:0.5];
}

- (void)createSendButton
{
    self.sendButton = [IconButton iconButtonDefault];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sendButton setIcon:ZetaIconTypeSend withSize:ZetaIconSizeTiny forState:UIControlStateNormal renderingMode:UIImageRenderingModeAlwaysTemplate];
    self.sendButton.accessibilityIdentifier = @"sendButton";
    self.sendButton.adjustsImageWhenHighlighted = NO;

    [self.inputBar.rightAccessoryView addSubview:self.sendButton];
    CGFloat edgeLength = 28;
    [self.sendButton autoSetDimensionsToSize:CGSizeMake(edgeLength, edgeLength)];
    CGFloat rightInset = ([WAZUIMagic cgFloatForIdentifier:@"content.left_margin"] - edgeLength) / 2;
    [self.sendButton autoPinEdgesToSuperviewEdgesWithInsets:UIEdgeInsetsMake(14, 0, 0, rightInset - 16) excludingEdge:ALEdgeBottom];
}

- (void)createEmojiButton
{
    const CGFloat senderDiameter = [WAZUIMagic floatForIdentifier:@"content.sender_image_tile_diameter"];
    
    self.emojiButton = IconButton.iconButtonCircular;
    self.emojiButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.emojiButton setIcon:ZetaIconTypeEmoji withSize:ZetaIconSizeTiny forState:UIControlStateNormal];
    self.emojiButton.accessibilityIdentifier = @"emojiButton";

    [self.inputBar.leftAccessoryView addSubview:self.emojiButton];
    [self.emojiButton autoAlignAxisToSuperviewAxis:ALAxisVertical];
    [self.emojiButton autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:14];
    [self.emojiButton autoSetDimensionsToSize:CGSizeMake(senderDiameter, senderDiameter)];
}

- (void)createTypingIndicatorView
{
    self.typingIndicatorView = [[TypingIndicatorView alloc] init];
    self.typingIndicatorView.translatesAutoresizingMaskIntoConstraints = NO;
    self.typingIndicatorView.accessibilityIdentifier = @"typingIndicator";
    self.typingIndicatorView.typingUsers = self.typingUsers.allObjects;
    [self.typingIndicatorView setHidden:YES animated:NO];
    
    [self.inputBar  addSubview:self.typingIndicatorView];
    [self.typingIndicatorView  autoConstrainAttribute:(ALAttribute)ALAxisHorizontal toAttribute:ALAttributeTop ofView:self.inputBar];
    [self.typingIndicatorView autoAlignAxisToSuperviewAxis:ALAxisVertical];
    [self.typingIndicatorView autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:48 relation:NSLayoutRelationGreaterThanOrEqual];
    [self.typingIndicatorView autoPinEdgeToSuperviewEdge:ALEdgeRight withInset:48 relation:NSLayoutRelationGreaterThanOrEqual];
}

- (void)updateNewButtonTitleLabel
{
    self.photoButton.titleLabel.hidden = self.inputBar.textView.isFirstResponder;
}

- (void)updateLeftAccessoryView
{
    self.authorImageView.alpha = self.inputBar.textView.isFirstResponder ? 1 : 0;
}

- (void)updateSendButtonVisibility
{
    NSString *trimmed = [self.inputBar.textView.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    const NSUInteger textLength = trimmed.length;
    BOOL hideSendButton = Settings.sharedSettings.disableSendButton && self.mode != ConversationInputBarViewControllerModeEmojiInput;
    BOOL editing = nil != self.editingMessage;
    self.sendButton.hidden = textLength == 0 || hideSendButton || editing;
}

- (void)updateAccessoryViews
{
    [self updateLeftAccessoryView];
    [self updateSendButtonVisibility];
}

- (void)clearInputBar
{
    self.inputBar.textView.text = @"";
    [self updateSendButtonVisibility];
}

- (void)setInputBarOverlapsContent:(BOOL)inputBarOverlapsContent
{
    _inputBarOverlapsContent = inputBarOverlapsContent;
    
    [self updateSeparatorLineVisibility];
}

- (void)setTypingUsers:(NSSet *)typingUsers
{
    _typingUsers = typingUsers;
    
    [self updateSeparatorLineVisibility];
    [self updateTypingIndicatorVisibility];
}

- (void)updateTypingIndicatorVisibility
{
    if (self.typingUsers.count > 0) {
        self.typingIndicatorView.typingUsers = self.typingUsers.allObjects;
        [self.typingIndicatorView layoutIfNeeded];
    }
    
    [self.typingIndicatorView setHidden:self.typingUsers.count == 0 animated: true];
}

- (void)updateSeparatorLineVisibility
{
    self.inputBar.separatorEnabled = self.inputBarOverlapsContent || self.typingUsers.count > 0;
}

- (void)updateInputBarVisibility
{
    if (self.conversation.isReadOnly && self.inputBar.superview != nil) {
        [self.inputBar removeFromSuperview];
        self.collapseViewConstraint = [self.view autoSetDimension:ALDimensionHeight toSize:0];
    } else if (! self.conversation.isReadOnly && self.inputBar.superview == nil) {
        [self.view removeConstraint:self.collapseViewConstraint];
        [self.view addSubview:self.inputBar];
        [self.inputBar autoPinEdgesToSuperviewEdges];
    }
}

#pragma mark - Input views handling

- (void)onSingleTap:(UITapGestureRecognizer *)recognier
{
    if (recognier.state == UIGestureRecognizerStateRecognized && self.mode != ConversationInputBarViewControllerModeEmojiInput) {
        self.mode = ConversationInputBarViewControllerModeTextInput;
    }
}

- (void)setMode:(ConversationInputBarViewControllerMode)mode
{
    if (_mode == mode) {
        return;
    }
    _mode = mode;

    switch (mode) {
        case ConversationInputBarViewControllerModeTextInput:
            self.inputController = nil;
            self.singleTapGestureRecognizer.enabled = NO;
            [self selectInputControllerButton:nil];
            break;
    
        case ConversationInputBarViewControllerModeAudioRecord:
            [self clearTextInputAssistentItemIfNeeded];
            
            if (self.inputController == nil || self.inputController != self.audioRecordKeyboardViewController) {
                if (self.audioRecordKeyboardViewController == nil) {
                    self.audioRecordKeyboardViewController = [[AudioRecordKeyboardViewController alloc] init];
                    self.audioRecordKeyboardViewController.delegate = self;
                }
                self.cameraKeyboardViewController = nil;
                self.emojiKeyboardViewController = nil;
                self.inputController = self.audioRecordKeyboardViewController;
            }
            [Analytics.shared tagMediaAction:ConversationMediaActionAudioMessage inConversation:self.conversation];

            self.singleTapGestureRecognizer.enabled = YES;
            [self selectInputControllerButton:self.audioButton];
            break;
            
        case ConversationInputBarViewControllerModeCamera:
            [self clearTextInputAssistentItemIfNeeded];
            
            if (self.inputController == nil || self.inputController != self.cameraKeyboardViewController) {
                if (self.cameraKeyboardViewController == nil) {
                    [self createCameraKeyboardViewController];
                }
                self.audioRecordViewController = nil;
                self.emojiKeyboardViewController = nil;
                self.inputController = self.cameraKeyboardViewController;
            }
            
            self.singleTapGestureRecognizer.enabled = YES;
            [self selectInputControllerButton:self.photoButton];
            break;
            
        case ConversationInputBarViewControllerModeEmojiInput:
            [self clearTextInputAssistentItemIfNeeded];
            
            if (self.inputController == nil || self.inputController != self.emojiKeyboardViewController) {
                if (self.emojiKeyboardViewController == nil) {
                    [self createEmojiKeyboardViewController];
                }
                
                self.audioRecordViewController = nil;
                self.cameraKeyboardViewController = nil;
                
                self.inputController = self.emojiKeyboardViewController;
            }

            self.singleTapGestureRecognizer.enabled = YES;
            [self selectInputControllerButton:self.emojiButton];
            [Analytics.shared tagEmojiKeyboardOpenend:self.conversation];
            break;
    }
    
    [self updateSendButtonVisibility];
}

- (void)selectInputControllerButton:(IconButton *)button
{
    for (IconButton *otherButton in @[self.photoButton, self.audioButton]) {
        otherButton.selected = [button isEqual:otherButton];
    }

    [self updateEmojiButton:self.emojiButton];
}

- (void)clearTextInputAssistentItemIfNeeded
{
    if (nil != [UITextInputAssistantItem class]) {
        UITextInputAssistantItem *item = self.inputBar.textView.inputAssistantItem;
        item.leadingBarButtonGroups = @[];
        item.trailingBarButtonGroups = @[];
    }
}

- (void)setInputController:(UIViewController *)inputController
{
    [_inputController.view removeFromSuperview];
    
    _inputController = inputController;
    
    if (inputController != nil) {
        CGSize inputViewSize = [UIView wr_lastKeyboardSize];

        CGRect inputViewFrame = (CGRect) {CGPointZero, inputViewSize};
        UIInputView *inputView = [[UIInputView alloc] initWithFrame:inputViewFrame
                                                     inputViewStyle:UIInputViewStyleKeyboard];
        if (@selector(allowsSelfSizing) != nil && [inputView respondsToSelector:@selector(allowsSelfSizing)]) {
            inputView.allowsSelfSizing = YES;
        }

        inputView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        inputController.view.frame = inputView.frame;
        inputController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [inputView addSubview:inputController.view];

        self.inputBar.textView.inputView = inputView;
    }
    else {
        self.inputBar.textView.inputView = nil;
    }
    
    [self.inputBar.textView reloadInputViews];
}

- (void)keyboardDidHide:(NSNotification *)notification
{
    if (!self.inRotation) {
        self.mode = ConversationInputBarViewControllerModeTextInput;
    }
}

- (void)sendOrEditText:(NSString *)text
{
    NSString *candidateText = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    BOOL conversationWasNotDeleted = self.conversation.managedObjectContext != nil;
    
    if (self.inputBar.isEditing && nil != self.editingMessage) {
        NSString *previousText = [self.editingMessage.textMessageData.messageText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (![candidateText isEqualToString:previousText]) {
            [self sendEditedMessageAndUpdateStateWithText:candidateText];
        }
        
        return;
    }
    
    if (candidateText.length && conversationWasNotDeleted) {
        
        [self clearInputBar];
        
        NSArray *args = candidateText.args;
        if(args.count > 0) {
            [self runCommand:args];
        }
        else {
            [self.sendController sendTextMessage:candidateText];
        }
    }
}

#pragma mark - Animations

- (void)bounceCameraIcon;
{
    CGAffineTransform scaleTransform = CGAffineTransformMakeScale(1.3, 1.3);
    
    dispatch_block_t scaleUp = ^{
        self.photoButton.transform = scaleTransform;
    };
    
    dispatch_block_t scaleDown = ^{
        self.photoButton.transform = CGAffineTransformIdentity;
    };

    [UIView animateWithDuration:0.1 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:scaleUp completion:^(__unused BOOL finished) {
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:0.6 options:UIViewAnimationOptionCurveEaseOut animations:scaleDown completion:nil];
    }];
}

@end

#pragma mark - Categories

@implementation ConversationInputBarViewController (UITextViewDelegate)

- (void)textViewDidChange:(UITextView *)textView
{
    // In case the conversation isDeleted
    if (self.conversation.managedObjectContext == nil)  {
        return;
    }
    
    if ([self.conversation shouldDisplayIsTyping]) {
        if (textView.text.length > 0) {
            [self.conversation setIsTyping:YES];
        }
        else {
            [self.conversation setIsTyping:NO];
        }
    }
    
    [self updateSendButtonVisibility];
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    if (!Settings.sharedSettings.disableSendButton) {
        // The send button is not disabled, we allow newlines and don't send.
        return YES;
    }

    if ([text isEqualToString:@"\n"]) {
        [self sendOrEditText:textView.text];
        return NO;
    }
    
    return YES;
}

- (BOOL)textViewShouldBeginEditing:(UITextView *)textView
{
    if (self.mode == ConversationInputBarViewControllerModeAudioRecord) {
        return YES;
    }
    else if ([self.delegate respondsToSelector:@selector(conversationInputBarViewControllerShouldBeginEditing:isEditingMessage:)]) {
        return [self.delegate conversationInputBarViewControllerShouldBeginEditing:self isEditingMessage:(nil != self.editingMessage)];
    }
    else {
        return YES;
    }
}

- (void)textViewDidBeginEditing:(UITextView *)textView
{
    [self updateAccessoryViews];
    [self updateNewButtonTitleLabel];
    [[ZMUserSession sharedSession] checkNetworkAndFlashIndicatorIfNecessary];
}

- (BOOL)textViewShouldEndEditing:(UITextView *)textView
{
    if ([self.delegate respondsToSelector:@selector(conversationInputBarViewControllerShouldEndEditing:)]) {
        return [self.delegate conversationInputBarViewControllerShouldEndEditing:self];
    }
    
    return YES;
}

- (void)textViewDidEndEditing:(UITextView *)textView
{
    [[ZMUserSession sharedSession] enqueueChanges:^{
        self.conversation.draftMessageText = textView.text;
    }];
}

#pragma mark - Informal TextView delegate methods

- (void)textView:(UITextView *)textView hasImageToPaste:(id<MediaAsset>)image
{
    ConfirmAssetViewController *confirmImageViewController = [[ConfirmAssetViewController alloc] init];
    confirmImageViewController.image = image;
    confirmImageViewController.previewTitle = [self.conversation.displayName uppercasedWithCurrentLocale];
    
    @weakify(self);
    
    confirmImageViewController.onConfirm = ^{
        @strongify(self);
        [self dismissViewControllerAnimated:NO completion:nil];
        [self postImage:image];
    };
    
    confirmImageViewController.onCancel = ^() {
        @strongify(self);
        [self dismissViewControllerAnimated:NO completion:nil];
    };
    
    [self presentViewController:confirmImageViewController animated:NO completion:nil];
}

- (void)textView:(UITextView *)textView firstResponderChanged:(NSNumber *)resigned
{
    [self updateAccessoryViews];
    [self updateNewButtonTitleLabel];
}

- (void)postImage:(id<MediaAsset>)image
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [self.sendController sendMessageWithImageData:image.data completion:^() {
            [[Analytics shared] tagMediaSentPictureSourceOtherInConversation:self.conversation source:ConversationMediaPictureSourcePaste];
        }];
    });
}

@end


@implementation ConversationInputBarViewController (CameraViewController)

- (void)cameraButtonPressed:(id)sender
{
    if (self.mode == ConversationInputBarViewControllerModeCamera) {
        [self.inputBar.textView resignFirstResponder];
        self.cameraKeyboardViewController = nil;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.mode = ConversationInputBarViewControllerModeTextInput;
        });
    }
    else {
        [UIApplication wr_requestOrWarnAboutVideoAccess:^(BOOL granted) {
            [self executeWithCameraRollPermission:^(BOOL success){
                self.mode = ConversationInputBarViewControllerModeCamera;
                [self.inputBar.textView becomeFirstResponder];
            }];
        }];
    }
}

- (void)videoButtonPressed:(IconButton *)sender
{
    [Analytics.shared tagMediaAction:ConversationMediaActionVideoMessage inConversation:self.conversation];
    self.videoSendContext = ConversationMediaVideoContextCursorButton;
    [self presentImagePickerWithSourceType:UIImagePickerControllerSourceTypeCamera mediaTypes:@[(id)kUTTypeMovie] allowsEditing:false];
}

#pragma mark - Video save callback

- (void)video:(NSString *)videoPath didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo
{
    if (nil != error) {
        DDLogError(@"Error saving video: %@", error);
    }
}

@end

@implementation ConversationInputBarViewController (Sketch)

- (void)sketchButtonPressed:(id)sender
{
    [self.inputBar.textView resignFirstResponder];
    [Analytics.shared tagMediaAction:ConversationMediaActionSketch inConversation:self.conversation];
    
    SketchViewController *viewController = [[SketchViewController alloc] init];
    viewController.sketchTitle = self.conversation.displayName;
    viewController.delegate = self;
    viewController.source = ConversationMediaSketchSourceSketchButton;
    
    ZMUser *lastSender = self.conversation.lastMessageSender;
    [self.parentViewController presentViewController:viewController animated:YES completion:^{
        [viewController.backgroundViewController setUser:lastSender animated:NO];
        [self.analyticsTracker tagNavigationViewEnteredSketchpad];
    }];
}

- (void)sketchViewControllerDidCancel:(SketchViewController *)controller
{
    [self.parentViewController dismissViewControllerAnimated:YES completion:^{
        [self.analyticsTracker tagNavigationViewSkippedSketchpad];
    }];
}

- (void)sketchViewController:(SketchViewController *)controller didSketchImage:(UIImage *)image
{
    @weakify(self);
    [self hideCameraKeyboardViewController:^{
        @strongify(self);
        [self.parentViewController dismissViewControllerAnimated:YES completion:nil];
        if (image) {
            NSData *imageData = UIImagePNGRepresentation(image);
            [self.sendController sendMessageWithImageData:imageData completion:^{
                   [[Analytics shared] tagMediaSentPictureSourceSketchInConversation:self.conversation sketchSource:controller.source];
            }];
        }
    }];
}

@end

@implementation ConversationInputBarViewController (Location)

- (void)locationButtonPressed:(IconButton *)sender
{
    [[Analytics shared] tagMediaAction:ConversationMediaActionLocation inConversation:self.conversation];
    
    LocationSelectionViewController *locationSelectionViewController = [[LocationSelectionViewController alloc] initForPopoverPresentation:IS_IPAD];
    locationSelectionViewController.modalPresentationStyle = UIModalPresentationPopover;
    UIPopoverPresentationController* popoverPresentationController = locationSelectionViewController.popoverPresentationController;
    popoverPresentationController.sourceView = sender.superview;
    popoverPresentationController.sourceRect = sender.frame;
    locationSelectionViewController.title = self.conversation.displayName;
    locationSelectionViewController.delegate = self;
    [self.parentViewController presentViewController:locationSelectionViewController animated:YES completion:nil];
}

- (void)locationSelectionViewController:(LocationSelectionViewController *)viewController didSelectLocationWithData:(ZMLocationData *)locationData
{
    [ZMUserSession.sharedSession enqueueChanges:^{
        [self.conversation appendMessageWithLocationData:locationData];
        [[Analytics shared] tagMediaActionCompleted:ConversationMediaActionLocation inConversation:self.conversation];
    }];
    
    [self.parentViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)locationSelectionViewControllerDidCancel:(LocationSelectionViewController *)viewController
{
    [self.parentViewController dismissViewControllerAnimated:YES completion:nil];
}

@end


@implementation ConversationInputBarViewController (Giphy)

- (void)giphyButtonPressed:(id)sender
{
    
    [[ZMUserSession sharedSession] checkNetworkAndFlashIndicatorIfNecessary];
    
    if ([ZMUserSession sharedSession].networkState != ZMNetworkStateOffline) {
        
        [Analytics.shared tagMediaAction:ConversationMediaActionGif inConversation:self.conversation];
    
        NSString *searchTerm = [self.inputBar.textView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        GiphySearchViewController *giphySearchViewController = [[GiphySearchViewController alloc] initWithSearchTerm:searchTerm conversation:self.conversation];
        giphySearchViewController.delegate = self;
        [[ZClientViewController sharedZClientViewController] presentViewController:[giphySearchViewController wrapInsideNavigationController] animated:YES completion:nil];
        
    }
}

@end



#pragma mark - SendButton

@implementation ConversationInputBarViewController (Sending)

- (void)sendButtonPressed:(id)sender
{
    [self sendOrEditText:self.inputBar.textView.text];
}

@end



#pragma mark - PingButton

@implementation ConversationInputBarViewController (Ping)

- (void)pingButtonPressed:(UIButton *)button
{
    [self appendKnock];
}

- (void)appendKnock
{
    [[ZMUserSession sharedSession] enqueueChanges:^{
        id<ZMConversationMessage> knockMessage = [self.conversation appendKnock];
        if (knockMessage) {
            [Analytics.shared tagMediaAction:ConversationMediaActionPing inConversation:self.conversation];
            [Analytics.shared tagMediaActionCompleted:ConversationMediaActionPing inConversation:self.conversation];
            Analytics.shared.sessionSummary.pingsSent++;
            
            [[[AVSProvider shared] mediaManager] playSound:MediaManagerSoundOutgoingKnockSound];
        }
    }];
    
    self.pingButton.enabled = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.pingButton.enabled = YES;
    });
}

@end


@implementation ConversationInputBarViewController (ZMConversationObserver)

- (void)conversationDidChange:(ConversationChangeInfo *)change
{    
    if (change.participantsChanged || change.connectionStateChanged) {
        [self updateInputBarVisibility];
    }
}

@end


@implementation ConversationInputBarViewController (Commands)

- (void)runCommand:(NSArray *)args
{
    if (args.count == 0) {
        return;
    }
    
    [self.sendController sendTextMessage:[NSString stringWithFormat:@"/%@", [args componentsJoinedByString:@" "]]];
}

@end


@implementation ConversationInputBarViewController (ZMTypingChangeObserver)

- (void)typingDidChange:(ZMTypingChangeNotification *)note
{
    NSPredicate *filterSelfUserPredicate = [NSPredicate predicateWithFormat:@"SELF != %@", [ZMUser selfUser]];
    NSSet *filteredSet = [note.typingUsers filteredSetUsingPredicate:filterSelfUserPredicate];
    
    self.typingUsers = filteredSet;
}

@end


@implementation ConversationInputBarViewController (UIGestureRecognizerDelegate)

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    if (self.singleTapGestureRecognizer == gestureRecognizer || self.singleTapGestureRecognizer == otherGestureRecognizer) {
        return YES;
    }
    else {
        return NO;
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
       shouldReceiveTouch:(UITouch *)touch
{
    if (self.singleTapGestureRecognizer == gestureRecognizer) {
        return YES;
    }
    else {
        return CGRectContainsPoint(gestureRecognizer.view.bounds, [touch locationInView:gestureRecognizer.view]);
    }
}

@end

@implementation ConversationInputBarViewController (GiphySearchViewControllerDelegate)

- (void)giphySearchViewController:(GiphySearchViewController *)giphySearchViewController didSelectImageData:(NSData *)imageData searchTerm:(NSString *)searchTerm
{
    [[Analytics shared] tagMediaSentPictureSourceOtherInConversation:self.conversation source:ConversationMediaPictureSourceGiphy];
    [self clearInputBar];
    [self dismissViewControllerAnimated:YES completion:nil];
    
    
    
    NSString *messageText = nil;
    
    if ([searchTerm isEqualToString:@""]) {
        messageText = [NSString stringWithFormat:NSLocalizedString(@"giphy.conversation.random_message", nil), searchTerm];
    } else {
        messageText = [NSString stringWithFormat:NSLocalizedString(@"giphy.conversation.message", nil), searchTerm];
    }
    
    [self.sendController sendTextMessage:messageText withImageData:imageData];
}

@end
