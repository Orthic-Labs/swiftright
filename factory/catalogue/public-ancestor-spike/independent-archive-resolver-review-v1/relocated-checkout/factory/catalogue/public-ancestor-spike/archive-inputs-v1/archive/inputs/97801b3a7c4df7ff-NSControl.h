/*
	NSControl.h
	Application Kit
	Copyright (c) 1994-2024, Apple Inc.
	All rights reserved.
*/

#import <Foundation/NSArray.h>
#import <AppKit/NSView.h>
#import <AppKit/NSText.h>
#import <AppKit/NSCell.h>
#import <AppKit/AppKitDefines.h>

NS_HEADER_AUDIT_BEGIN(nullability, sendability)
APPKIT_API_UNAVAILABLE_BEGIN_MACCATALYST

@class NSCell, NSFont, NSTextView, NSNotification, NSAttributedString, NSFormatter;

@interface NSControl : NSView

- (instancetype)initWithFrame:(NSRect)frameRect NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@property (nullable, weak) id target; // Target is weak for zeroing-weak compatible objects in apps linked on 10.10 or later. Otherwise the behavior of this property is 'assign’.
@property (nullable) SEL action;
@property NSInteger tag;
@property BOOL ignoresMultiClick;
@property (getter=isContinuous) BOOL continuous;
@property (getter=isEnabled) BOOL enabled;
@property BOOL refusesFirstResponder;
@property (getter=isHighlighted) BOOL highlighted API_AVAILABLE(macos(10.10));
@property NSControlSize controlSize API_AVAILABLE(macos(10.10));
@property (nullable, strong) __kindof NSFormatter *formatter;

@property (nullable, copy) id  /* id<NSCopying> */ objectValue;
@property (copy) NSString *stringValue;
@property (copy) NSAttributedString *attributedStringValue;
@property int intValue;
@property NSInteger integerValue;
@property float floatValue;
@property double doubleValue;

- (NSSize)sizeThatFits:(NSSize)size API_AVAILABLE(macos(10.10));
- (void)sizeToFit;

- (NSInteger)sendActionOn:(NSEventMask)mask;

- (BOOL)sendAction:(nullable SEL)action to:(nullable id)target;
- (void)takeIntValueFrom:(nullable id)sender;
- (void)takeFloatValueFrom:(nullable id)sender;
- (void)takeDoubleValueFrom:(nullable id)sender;
- (void)takeStringValueFrom:(nullable id)sender;
- (void)takeObjectValueFrom:(nullable id)sender;
- (void)takeIntegerValueFrom:(nullable id)sender API_AVAILABLE(macos(10.5));

- (void)performClick:(nullable id)sender;

/* The following methods apply only to controls with apparent textual content of some sort (buttons with labels, textfields, etc.).
 */
@property (nullable, copy) NSFont *font;

@property BOOL usesSingleLineMode API_AVAILABLE(macos(10.10));

#if !TARGET_OS_IPHONE
@property NSLineBreakMode lineBreakMode API_AVAILABLE(macos(10.10));
@property NSTextAlignment alignment;
@property NSWritingDirection baseWritingDirection;
#endif

/* Gets and sets the ability for expansion tool tips to be shown or not. Expansion tooltips are automatically shown when the cell can not show the full content. This is controlled by the NSCell API expansionFrameWithFrame:inView: and is drawn by drawWithExpansionFrame:inView:. The default value is NO.
    This value is encoded along with the control. In general, it is recommended to turn this on for NSTextFields in a View Based NSTableView.
 */
@property BOOL allowsExpansionToolTips API_AVAILABLE(macos(10.8));

/*  Allows the control to return an expansion tool tip frame if contentFrame is too small for the entire contents in the view. When the mouse is hovered over the text in certain controls, the full contents will be shown in a special floating tool tip view. If the frame is not too small, return an empty rect, and no expansion tool tip view will be shown. By default, NSControl returns NSZeroRect, while some subclasses (such as NSTextField) will return the proper frame when required.
 */
- (NSRect)expansionFrameWithFrame:(NSRect)contentFrame API_AVAILABLE(macos(10.10));

/* Allows the control to perform custom expansion tool tip drawing. Note that the view may be different from the original view that the text appeared in.
 */
- (void)drawWithExpansionFrame:(NSRect)contentFrame inView:(NSView *)view API_AVAILABLE(macos(10.10));

@end

/* The following category applies only to controls with editable text, like NSTextField.
 */
@interface NSControl(NSControlEditableTextMethods)
- (nullable NSText *)currentEditor;
- (BOOL)abortEditing;
- (void)validateEditing;

- (void)editWithFrame:(NSRect)rect editor:(NSText *)textObj delegate:(nullable id)delegate event:(NSEvent *)event API_AVAILABLE(macos(10.10));
- (void)selectWithFrame:(NSRect)rect editor:(NSText *)textObj delegate:(nullable id)delegate start:(NSInteger)selStart length:(NSInteger)selLength API_AVAILABLE(macos(10.10));
- (void)endEditing:(NSText *)textObj API_AVAILABLE(macos(10.10));
@end

@protocol NSControlTextEditingDelegate <NSObject>
@optional

- (void)controlTextDidBeginEditing:(NSNotification *)obj NS_SWIFT_UI_ACTOR;
- (void)controlTextDidEndEditing:(NSNotification *)obj NS_SWIFT_UI_ACTOR;
- (void)controlTextDidChange:(NSNotification *)obj NS_SWIFT_UI_ACTOR;

// These delegate and notification methods are sent from NSControl subclasses that allow text editing such as NSTextField and NSMatrix.  The classes that need to send these have delegates.  NSControl does not.
- (BOOL)control:(NSControl *)control textShouldBeginEditing:(NSText *)fieldEditor NS_SWIFT_UI_ACTOR;
- (BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)fieldEditor NS_SWIFT_UI_ACTOR;
- (BOOL)control:(NSControl *)control didFailToFormatString:(NSString *)string errorDescription:(nullable NSString *)error NS_SWIFT_UI_ACTOR;
- (void)control:(NSControl *)control didFailToValidatePartialString:(NSString *)string errorDescription:(nullable NSString *)error NS_SWIFT_UI_ACTOR;
- (BOOL)control:(NSControl *)control isValidObject:(nullable id)obj NS_SWIFT_UI_ACTOR;

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector NS_SWIFT_UI_ACTOR;
- (NSArray<NSString *> *)control:(NSControl *)control textView:(NSTextView *)textView completions:(NSArray<NSString *> *)words forPartialWordRange:(NSRange)charRange indexOfSelectedItem:(NSInteger *)index NS_SWIFT_UI_ACTOR;
@end

                                                                    // userInfo keys:
APPKIT_EXTERN NSNotificationName NSControlTextDidBeginEditingNotification;	//	@"NSFieldEditor"
APPKIT_EXTERN NSNotificationName NSControlTextDidEndEditingNotification;	//	@"NSFieldEditor"
APPKIT_EXTERN NSNotificationName NSControlTextDidChangeNotification;		//	@"NSFieldEditor"


@interface NSControl (NSDeprecated)

// Use formatters instead.  See -[NSControl formatter] and -[NSControl setFormatter:].
- (void)setFloatingPointFormat:(BOOL)autoRange left:(NSUInteger)leftDigits right:(NSUInteger)rightDigits API_DEPRECATED("", macos(10.0,10.0));

@property (class, nullable) Class cellClass;

@property (nullable, strong) __kindof NSCell *cell;

- (nullable __kindof NSCell *)selectedCell;
- (NSInteger)selectedTag;

- (void)setNeedsDisplay API_DEPRECATED("Set the needsDisplay property to YES instead", macos(10.0,10.14));
- (void)calcSize API_DEPRECATED("Override -layout instead. This method should never be called", macos(10.0,10.14));

- (void)updateCell:(NSCell *)cell;
- (void)updateCellInside:(NSCell *)cell;
- (void)drawCellInside:(NSCell *)cell;
- (void)drawCell:(NSCell *)cell;
- (void)selectCell:(NSCell *)cell;

@end

#if __swift__ < 40200
@interface NSObject(NSControlSubclassNotifications)
- (void)controlTextDidBeginEditing:(NSNotification *)obj API_DEPRECATED("This is now an optional method of the NSControlTextEditingDelegate protocol.", macos(10.0, 11.0));
- (void)controlTextDidEndEditing:(NSNotification *)obj API_DEPRECATED("This is now an optional method of the NSControlTextEditingDelegate protocol.", macos(10.0, 11.0));
- (void)controlTextDidChange:(NSNotification *)obj API_DEPRECATED("This is now an optional method of the NSControlTextEditingDelegate protocol.", macos(10.0, 11.0));
@end
#endif

typedef NS_ENUM(NSInteger, NSControlBorderShape) {
    /// The control will resolve this to an appropriate shape for the given control size and context
    NSControlBorderShapeAutomatic,
    NSControlBorderShapeCapsule,
    NSControlBorderShapeRoundedRectangle,
    NSControlBorderShapeCircle
} API_AVAILABLE(macos(26.0)) NS_SWIFT_NAME(NSControl.BorderShape);

/// Constants describing the types of events possible for controls.
///
/// Associate both a target and action with one or more control events by calling
/// ``addTarget(_:action:for:)`` for each target-action pair you want to specify.
typedef NS_OPTIONS(NSUInteger, NSControlEvents) {
    /// A tracking began event in the control.
    NSControlEventTrackingBegan           = 1 <<  0,
    /// A repeated tracking began event in the control. For this event the click count is greater than one.
    NSControlEventTrackingRepeated         API_AVAILABLE(macos(27.0)) = 1 <<  1,
    /// An event where the pointer or touch moves inside the bounds of the control.
    NSControlEventTrackingInside          = 1 <<  2,
    /// An event where the pointer or touch moves outside the bounds of the control.
    NSControlEventTrackingOutside         = 1 <<  3,
    /// An event where tracking transitions from outside to inside the bounds of the control.
    NSControlEventTrackingEntered         = 1 <<  4,
    /// An event where tracking transitions from inside to outside the bounds of the control.
    NSControlEventTrackingExited          = 1 <<  5,
    /// A tracking ended event where the pointer or touch is inside the bounds of the control.
    NSControlEventTrackingEndedInside     = 1 <<  6,
    /// A tracking ended event where the pointer or touch is outside the bounds of the control.
    NSControlEventTrackingEndedOutside    = 1 <<  7,
    /// A system event canceling the current tracking for the control.
    NSControlEventTrackingCancelled       = 1 <<  8,

    /// An event where dragging or otherwise manipulating a control causes it to emit a series of different values.
    NSControlEventValueChanged            API_AVAILABLE(macos(27.0)) = 1 << 12,
    /// A semantic action triggered by buttons.
    NSControlEventPrimaryActionTriggered  API_AVAILABLE(macos(27.0)) = 1 << 13,
    /// A menu action has triggered prior to the menu being presented.
    NSControlEventMenuActionTriggered     API_AVAILABLE(macos(27.0)) = 1 << 14,

    /// All tracking events.
    NSControlEventAllTrackingEvents       = 0x00000FFF,
    /// A range of control-event values available for app use.
    NSControlEventApplicationReserved      API_AVAILABLE(macos(27.0)) = 0x0F000000,
    /// A range of control-event values reserved for internal framework use.
    NSControlEventSystemReserved          = 0xF0000000,
    /// All events, including system events.
    NSControlEventAllEvents               = 0xFFFFFFFF
} API_AVAILABLE(macos(11.0)) NS_SWIFT_NAME(NSControl.Events);

@interface NSControl(NSControlEvents)
/// Associates a target object and action method with one or more control events.
///
/// You can call this method multiple times to specify multiple target-action pairs for a
/// particular event. Passing `nil` as the target routes the action message up the responder
/// chain. The control does not retain the target.
- (void)addTarget:(nullable id)target action:(SEL)action forControlEvents:(NSControlEvents)controlEvents API_AVAILABLE(macos(11.0));

/// Stops the delivery of the specified events to the given target object.
///
/// Pass `nil` as the action to remove all actions for the target.
- (void)removeTarget:(nullable id)target action:(nullable SEL)action forControlEvents:(NSControlEvents)controlEvents API_AVAILABLE(macos(11.0));
@end

API_UNAVAILABLE_END
NS_HEADER_AUDIT_END(nullability, sendability)
