/*
 * Apache 2.0 License
 *
 * Copyright (c) Sebastian Katzer 2017
 *
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apache License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://opensource.org/licenses/Apache-2.0/ and read it before using this
 * file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 */

// codebeat:disable[TOO_MANY_FUNCTIONS]

#import "APPLocalNotification.h"
#import "APPNotificationContent.h"
#import "APPNotificationOptions.h"
#import "APPNotificationCategory.h"
#import "UNUserNotificationCenter+APPLocalNotification.h"
#import "UNNotificationRequest+APPLocalNotification.h"

@interface APPLocalNotification ()

@property (strong, nonatomic) UNUserNotificationCenter* center;
@property (NS_NONATOMIC_IOSONLY, nullable, weak) id <UNUserNotificationCenterDelegate> delegate;
@property (readwrite, assign) BOOL deviceready;
@property (readwrite, assign) BOOL isActive;
@property (readonly, nonatomic, retain) NSArray* launchDetails;
@property (readonly, nonatomic, retain) NSMutableArray* eventQueue;

@end

@implementation APPLocalNotification

UNNotificationPresentationOptions const OptionNone  = UNNotificationPresentationOptionNone;
UNNotificationPresentationOptions const OptionBadge = UNNotificationPresentationOptionBadge;
UNNotificationPresentationOptions const OptionSound = UNNotificationPresentationOptionSound;
UNNotificationPresentationOptions const OptionAlert = UNNotificationPresentationOptionAlert;

@synthesize deviceready, isActive, eventQueue;

#pragma mark -
#pragma mark Life Cycle

/**
 * Registers obervers after plugin was initialized.
 */
- (void) pluginInitialize
{
    NSLog(@"LocalNotification: pluginInitialize");
    eventQueue = [[NSMutableArray alloc] init];
    _center = [UNUserNotificationCenter currentNotificationCenter];
    _delegate = _center.delegate;

    _center.delegate = self;
    [_center registerGeneralNotificationCategory];

    [self monitorAppStateChanges];
}

/**
 * Monitor changes of the app state and update the _isActive flag.
 */
- (void) monitorAppStateChanges
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [center addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:NULL queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *e) { self->isActive = YES; }];

    [center addObserverForName:UIApplicationDidEnterBackgroundNotification
                        object:NULL queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *e) { self->isActive = NO; }];
}

#pragma mark -
#pragma mark Interface


/**
 * Set launchDetails object.
 */
- (void) launch:(CDVInvokedUrlCommand*)command
{
    if (!_launchDetails) return;

    [self.commandDelegate evalJs:[NSString
        stringWithFormat:@"cordova.plugins.notification.local.launchDetails = {id:%@, action:'%@'}",
        _launchDetails[0], _launchDetails[1]]];

    _launchDetails = NULL;
}

/**
 * Execute all queued events.
 */
- (void) ready:(CDVInvokedUrlCommand*)command
{
    deviceready = YES;

    [self.commandDelegate runInBackground:^{
        for (NSString* js in self->eventQueue) {
            [self.commandDelegate evalJs:js];
        }
        [self->eventQueue removeAllObjects];
    }];
}

/**
 * Schedule notifications.
 */
- (void) schedule:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        for (NSDictionary* options in command.arguments) {
            [self scheduleNotification:[[APPNotificationContent alloc] initWithOptions:options]];
        }

        [self check:command];
    }];
}

/**
 * Update notifications.
 */
- (void) update:(CDVInvokedUrlCommand*)command
{
    NSArray* notifications = command.arguments;

    [self.commandDelegate runInBackground:^{
        for (NSDictionary* options in notifications) {
            NSNumber* id = [options objectForKey:@"id"];
            UNNotificationRequest* notification;

            notification = [self->_center getNotificationWithId:id];

            if (!notification)
                continue;

            [self updateNotification:[notification copy]
                         withOptions:options];

            [self fireEvent:@"update" notification:notification];
        }

        [self check:command];
    }];
}

/**
 * Clear notifications by id.
 * @param command Contains the IDs of the notifications to clear.
 */
- (void) clear:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        for (NSNumber* id in command.arguments) {
            UNNotificationRequest* notification = [self->_center getNotificationWithId:id];
            if (!notification) continue;
            [self->_center clearNotification:notification];
            [self fireEvent:@"clear" notification:notification];
        }

        [self execCallback:command];
    }];
}

/**
 * Clear all local notifications.
 */
- (void) clearAll:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        [self->_center clearNotifications];
        [self clearApplicationIconBadgeNumber];
        [self fireEvent:@"clearall"];
        [self execCallback:command];
    }];
}

/**
 * Cancel notifications by id.
 * @param command Contains the IDs of the notifications to clear.
 */
- (void) cancel:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        for (NSNumber* id in command.arguments) {
            UNNotificationRequest* notification = [self->_center getNotificationWithId:id];
            if (!notification) continue;
            [self->_center cancelNotification:notification];
            [self fireEvent:@"cancel" notification:notification];
        }

        [self execCallback:command];
    }];
}

/**
 * Cancel all local notifications.
 */
- (void) cancelAll:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        [self->_center cancelNotifications];
        [self clearApplicationIconBadgeNumber];
        [self fireEvent:@"cancelall"];
        [self execCallback:command];
    }];
}

/**
 * Get type of notification.
 * @param command Contains the type to check.
 */
- (void) type:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        NSString* type;

        switch ([self->_center getTypeOfNotificationWithId:[command argumentAtIndex:0]]) {
            case NotifcationTypeScheduled:
                type = @"scheduled";
                break;
            case NotifcationTypeTriggered:
                type = @"triggered";
                break;
            default:
                type = @"unknown";
        }

        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                 messageAsString:type]
                                    callbackId:command.callbackId];
    }];
}

/**
 * List of notification IDs by type.
 */
- (void) ids:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        APPNotificationType type = NotifcationTypeUnknown;

        switch ([command.arguments[0] intValue]) {
            case 0:
                type = NotifcationTypeAll;
                break;
            case 1:
                type = NotifcationTypeScheduled;
                break;
            case 2:
                type = NotifcationTypeTriggered;
                break;
        }

        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                  messageAsArray:[self->_center getNotificationIdsByType:type]]
                                    callbackId:command.callbackId];
    }];
}

/**
 * Notification by id.
 * @param command Contains the id of the notification to return.
 */
- (void) notification:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        // command.arguments is a list of ids
        NSArray* notifications = [self->_center getNotificationOptionsById:command.arguments];
        
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                             messageAsDictionary:[notifications firstObject]]
                                    callbackId:command.callbackId];
    }];
}

/**
 * Get notifications by type or ids.
 * @param command Contains the ids of the notifications to return.
 */
- (void) notifications:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        APPNotificationType type = NotifcationTypeUnknown;
        NSArray* notifications;

        switch ([command.arguments[0] intValue]) {
            case 0:
                type = NotifcationTypeAll;
                break;
            case 1:
                type = NotifcationTypeScheduled;
                break;
            case 2:
                type = NotifcationTypeTriggered;
                break;
                
                // Get notifications by ids
            case 3:
                notifications = [self->_center getNotificationOptionsById:command.arguments[1]];
                break;
        }
        
        // Get notifications by type
        if (notifications == nil) {
            notifications = [self->_center getNotificationOptionsByType:type];
        }

        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                  messageAsArray:notifications]
                                    callbackId:command.callbackId];
    }];
}

/**
 * Check for permission to show notifications.
 */
- (void) check:(CDVInvokedUrlCommand*)command
{
    [_center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* settings) {
        BOOL authorized = settings.authorizationStatus == UNAuthorizationStatusAuthorized;
        BOOL enabled = settings.notificationCenterSetting == UNNotificationSettingEnabled;
        [self execCallback:command arg:authorized && enabled];
    }];
}

/**
 * Request for permission to show notifcations.
 */
- (void) requestPermission:(CDVInvokedUrlCommand*)command
{
    [_center requestAuthorizationWithOptions:(UNAuthorizationOptionBadge | UNAuthorizationOptionSound | UNAuthorizationOptionAlert)
                           completionHandler:^(BOOL granted, NSError* e) {
                               [self check:command];
                           }
    ];
}

/**
 * Register/update an action group.
 */
- (void) actions:(CDVInvokedUrlCommand *)command
{
    [self.commandDelegate runInBackground:^{
        NSString* identifier = [command argumentAtIndex:1];
        NSArray* actions = [command argumentAtIndex:2];

        switch ([command.arguments[0] intValue]) {
            case 0:
                [self->_center addActionGroup:[APPNotificationCategory parse:actions withId:identifier]];
                [self execCallback:command];
                break;
            case 1:
                [self->_center removeActionGroup:identifier];
                [self execCallback:command];
                break;
            case 2:
                [self execCallback:command arg:[self->_center hasActionGroup:identifier]];
                break;
        }
    }];
}

/**
 * Open native settings to enable notifications.
 * In iOS it's not possible to open the notification settings, only the app settings.
 */
- (void) openNotificationSettings:(CDVInvokedUrlCommand*)command
{
    @try {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]
                                           options:@{}
                                 completionHandler:^(BOOL success) {
            if (success) {
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                            callbackId:command.callbackId];
            } else {
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR]
                                            callbackId:command.callbackId];
            }
        }];
    }
    @catch (NSException *exception) {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                                 messageAsString:exception.reason]
                                    callbackId:command.callbackId];
    }
}

/**
 * Clear the badge number on the app icon. Called from JavaScript.
 */
- (void) clearBadge:(CDVInvokedUrlCommand*)command
{
    [self clearApplicationIconBadgeNumber];
    [self execCallback:command];
}

#pragma mark -
#pragma mark Private

/**
 * Schedule the local notification.
 * @param notification The notification to schedule.
 */
- (void) scheduleNotification:(APPNotificationContent*)notification
{
    __weak APPLocalNotification* weakSelf = self;
    UNNotificationRequest* request = notification.request;
    NSString* event = [request wasUpdated] ? @"update" : @"add";
    
    NSLog(@"Schedule notification, event=%@, trigger=%@, options=%@", event, request.trigger, notification.options);
    
    [_center addNotificationRequest:request
              withCompletionHandler:^(NSError* e) {
                __strong APPLocalNotification* strongSelf = weakSelf;
                [strongSelf fireEvent:event notification:request];
              }
    ];
}

/**
 * Update the local notification.
 * @param notification The notification to update.
 * @param newOptions The options to update.
 */
- (void) updateNotification:(UNNotificationRequest*)notification
                withOptions:(NSDictionary*)newOptions
{
    NSMutableDictionary* options = [notification.content.userInfo mutableCopy];

    [options addEntriesFromDictionary:newOptions];
    [options setObject:[NSDate date] forKey:@"updatedAt"];

    [self scheduleNotification:[[APPNotificationContent alloc] initWithOptions:options]];
}

#pragma mark -
#pragma mark UNUserNotificationCenterDelegate

/**
 * The method will be called on the delegate only if the application is in the foreground.
 */
- (void) userNotificationCenter:(UNUserNotificationCenter *)center
        willPresentNotification:(UNNotification *)notification
          withCompletionHandler:(void (^)(UNNotificationPresentationOptions))handler
{
    [_delegate userNotificationCenter:center
              willPresentNotification:notification
                withCompletionHandler:handler];

    if ([notification.request.trigger isKindOfClass:UNPushNotificationTrigger.class]) return;
    
    APPNotificationOptions* options = notification.request.options;
    NSLog(@"Handle notification while app is in foreground: %@", options);
    
    if (![notification.request wasUpdated]) {
        [self fireEvent:@"trigger" notification:notification.request];
    }

    if (options.silent) {
        handler(OptionNone);
    
    // Display notification only if the app is in background,
    // or if explicitly set by "iOSForeground" option.
    } else if (!isActive || options.iOSForeground) {
        handler(OptionBadge|OptionSound|OptionAlert);
    } else {
        handler(OptionBadge|OptionSound);
    }
}

/**
 * Called to let your app know which action was selected by the user for a given
 * notification.
 */
- (void) userNotificationCenter:(UNUserNotificationCenter *)center
 didReceiveNotificationResponse:(UNNotificationResponse *)response
          withCompletionHandler:(void (^)(void))handler
{
    UNNotificationRequest* toast = response.notification.request;

    [_delegate userNotificationCenter:center
       didReceiveNotificationResponse:response
                withCompletionHandler:handler];

    handler();

    if ([toast.trigger isKindOfClass:UNPushNotificationTrigger.class]) return;

    NSString* action = response.actionIdentifier;
    NSString* event = action;

    if ([action isEqualToString:UNNotificationDefaultActionIdentifier]) {
        event = @"click";
    } else
    if ([action isEqualToString:UNNotificationDismissActionIdentifier]) {
        event = @"clear";
    }

    if (!deviceready && [event isEqualToString:@"click"]) {
        _launchDetails = @[toast.options.id, event];
    }

    if (![event isEqualToString:@"clear"]) {
        [self fireEvent:@"clear" notification:toast];
    }

    NSMutableDictionary* data = [[NSMutableDictionary alloc] init];

    if ([response isKindOfClass:UNTextInputNotificationResponse.class]) {
        [data setObject:((UNTextInputNotificationResponse*) response).userText
                 forKey:@"text"];
    }

    [self fireEvent:event notification:toast data:data];
}

#pragma mark -
#pragma mark Helper

/**
 * Removes the badge number from the app icon.
 */
- (void) clearApplicationIconBadgeNumber
{
    NSLog(@"LocalNotification: clear application badge");
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].applicationIconBadgeNumber = 0;
    });
}

/**
 * Invokes the callback without any parameter.
 */
- (void) execCallback:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId:command.callbackId];
}

/**
 * Invokes the callback with a single boolean parameter.
 */
- (void) execCallback:(CDVInvokedUrlCommand*)command arg:(BOOL)arg
{
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                               messageAsBool:arg]
                                callbackId:command.callbackId];
}

/**
 * Fire general event.
 * @param event The name of the event to fire.
 */
- (void) fireEvent:(NSString*)event
{
    [self fireEvent:event notification:NULL data:[[NSMutableDictionary alloc] init]];
}

/**
 * Fire event for about a local notification.
 * @param event The name of the event to fire.
 * @param notificationRequest The UNNotificationRequest
 */
- (void) fireEvent:(NSString*)event
      notification:(UNNotificationRequest*)notificationRequest
{
    [self fireEvent:event notification:notificationRequest data:[[NSMutableDictionary alloc] init]];
}

/**
 * Fire event for about a local notification.
 * @param event The name of the event to fire.
 * @param notificationRequest The UNNotificationRequest
 * @param data Event object with additional data.
 */
- (void) fireEvent:(NSString*)event
      notification:(UNNotificationRequest*)notificationRequest
              data:(NSMutableDictionary*)data
{
    [data setObject:event forKey:@"event"];
    [data setObject:@(isActive) forKey:@"foreground"];
    [data setObject:@(!deviceready) forKey:@"queued"];
    
    if (notificationRequest) {
        [data setObject:notificationRequest.options.id forKey:@"notification"];
    }

    NSString *params;
    NSString *dataAsJSON = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:data
                                                                                          options:0
                                                                                            error:NULL]
                                                 encoding:NSUTF8StringEncoding];
    
    if (notificationRequest) {
        params = [NSString stringWithFormat:@"%@,%@", [notificationRequest encodeToJSON], dataAsJSON];
    } else {
        params = [NSString stringWithFormat:@"%@", dataAsJSON];
    }

    NSString *js = [NSString stringWithFormat:@"cordova.plugins.notification.local.fireEvent('%@', %@)", event, params];

    if (deviceready) {
        [self.commandDelegate evalJs:js];
    } else {
        [self.eventQueue addObject:js];
    }
}

@end

// codebeat:enable[TOO_MANY_FUNCTIONS]
