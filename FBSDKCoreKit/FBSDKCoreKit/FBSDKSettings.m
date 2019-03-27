// Copyright (c) 2014-present, Facebook, Inc. All rights reserved.
//
// You are hereby granted a non-exclusive, worldwide, royalty-free license to use,
// copy, modify, and distribute this software in source code or binary form for use
// in connection with the web services and APIs provided by Facebook.
//
// As with any software that integrates with the Facebook platform, your use of
// this software is subject to the Facebook Developer Principles and Policies
// [http://developers.facebook.com/policy/]. This copyright notice shall be
// included in all copies or substantial portions of the software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
// FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
// IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#import "FBSDKSettings+Internal.h"

#import "FBSDKAccessTokenCache.h"
#import "FBSDKAccessTokenExpirer.h"
#import "FBSDKCoreKit.h"

#define FBSDKSETTINGS_PLIST_CONFIGURATION_SETTING_IMPL(TYPE, PLIST_KEY, GETTER, SETTER, DEFAULT_VALUE) \
static TYPE *g_##PLIST_KEY = nil; \
+ (TYPE *)GETTER \
{ \
if (!g_##PLIST_KEY) { \
g_##PLIST_KEY = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@#PLIST_KEY] copy] ?: DEFAULT_VALUE; \
} \
return g_##PLIST_KEY; \
} \
+ (void)SETTER:(TYPE *)value { \
g_##PLIST_KEY = [value copy]; \
}

#define FBSDKSETTINGS_AUTOLOG_APPEVENTS_ENABLED_USER_DEFAULTS_KEY @"com.facebook.sdk:autoLogAppEventsEnabled%@"
#define FBSDKSETTINGS_ADVERTISERID_COLLECTION_ENABLED_USER_DEFAULTS_KEY @"com.facebook.sdk:advertiserIDCollectionEnabled%@"

FBSDKLoggingBehavior FBSDKLoggingBehaviorAccessTokens = @"include_access_tokens";
FBSDKLoggingBehavior FBSDKLoggingBehaviorPerformanceCharacteristics = @"perf_characteristics";
FBSDKLoggingBehavior FBSDKLoggingBehaviorAppEvents = @"app_events";
FBSDKLoggingBehavior FBSDKLoggingBehaviorInformational = @"informational";
FBSDKLoggingBehavior FBSDKLoggingBehaviorCacheErrors = @"cache_errors";
FBSDKLoggingBehavior FBSDKLoggingBehaviorUIControlErrors = @"ui_control_errors";
FBSDKLoggingBehavior FBSDKLoggingBehaviorDeveloperErrors = @"developer_errors";
FBSDKLoggingBehavior FBSDKLoggingBehaviorGraphAPIDebugWarning = @"graph_api_debug_warning";
FBSDKLoggingBehavior FBSDKLoggingBehaviorGraphAPIDebugInfo = @"graph_api_debug_info";
FBSDKLoggingBehavior FBSDKLoggingBehaviorNetworkRequests = @"network_requests";

static NSObject<FBSDKAccessTokenCaching> *g_tokenCache;
static NSMutableSet<FBSDKLoggingBehavior> *g_loggingBehaviors;
static NSString *const FBSDKSettingsLimitEventAndDataUsage = @"com.facebook.sdk:FBSDKSettingsLimitEventAndDataUsage";
static BOOL g_disableErrorRecovery;
static NSString *g_userAgentSuffix;
static NSString *g_defaultGraphAPIVersion;
static FBSDKAccessTokenExpirer *g_accessTokenExpirer;
static NSString *const FBSDKSettingsAutoLogAppEventsEnabled = @"FacebookAutoLogAppEventsEnabled";
static NSString *const FBSDKSettingsAdvertiserIDCollectionEnabled = @"FacebookAdvertiserIDCollectionEnabled";
static NSNumber *g_autoLogAppEventsEnabled;
static NSNumber *g_advertiserIDCollectionEnabled;

@implementation FBSDKSettings

+ (void)initialize
{
  if (self == [FBSDKSettings class]) {
    NSString *appID = [self appID];
    g_tokenCache = [[FBSDKAccessTokenCache alloc] init];
    g_accessTokenExpirer = [[FBSDKAccessTokenExpirer alloc] init];
    // Fetch meta data from plist and overwrite the value with NSUserDefaults if possible
    g_autoLogAppEventsEnabled = [self appEventSettingsForPlistKey:FBSDKSettingsAutoLogAppEventsEnabled defaultValue:@YES];
    g_autoLogAppEventsEnabled = [self appEventSettingsForUserDefaultsKey:[NSString stringWithFormat:FBSDKSETTINGS_AUTOLOG_APPEVENTS_ENABLED_USER_DEFAULTS_KEY, appID] defaultValue:g_autoLogAppEventsEnabled];
    [[NSUserDefaults standardUserDefaults] setObject:g_autoLogAppEventsEnabled forKey:[NSString stringWithFormat:FBSDKSETTINGS_AUTOLOG_APPEVENTS_ENABLED_USER_DEFAULTS_KEY, appID]];
    g_advertiserIDCollectionEnabled = [self appEventSettingsForPlistKey:FBSDKSettingsAdvertiserIDCollectionEnabled defaultValue:@YES];
    g_advertiserIDCollectionEnabled = [self appEventSettingsForUserDefaultsKey:[NSString stringWithFormat:FBSDKSETTINGS_ADVERTISERID_COLLECTION_ENABLED_USER_DEFAULTS_KEY, appID] defaultValue:g_advertiserIDCollectionEnabled];
    [[NSUserDefaults standardUserDefaults] setObject:g_advertiserIDCollectionEnabled forKey:[NSString stringWithFormat:FBSDKSETTINGS_ADVERTISERID_COLLECTION_ENABLED_USER_DEFAULTS_KEY, appID]];
  }
}

#pragma mark - Plist Configuration Settings

FBSDKSETTINGS_PLIST_CONFIGURATION_SETTING_IMPL(NSString, FacebookAppID, appID, setAppID, nil);
FBSDKSETTINGS_PLIST_CONFIGURATION_SETTING_IMPL(NSString, FacebookUrlSchemeSuffix, appURLSchemeSuffix, setAppURLSchemeSuffix, nil);
FBSDKSETTINGS_PLIST_CONFIGURATION_SETTING_IMPL(NSString, FacebookClientToken, clientToken, setClientToken, nil);
FBSDKSETTINGS_PLIST_CONFIGURATION_SETTING_IMPL(NSString, FacebookDisplayName, displayName, setDisplayName, nil);
FBSDKSETTINGS_PLIST_CONFIGURATION_SETTING_IMPL(NSString, FacebookDomainPart, facebookDomainPart, setFacebookDomainPart, nil);
FBSDKSETTINGS_PLIST_CONFIGURATION_SETTING_IMPL(NSNumber, FacebookJpegCompressionQuality, _JPEGCompressionQualityNumber, _setJPEGCompressionQualityNumber, @0.9);
FBSDKSETTINGS_PLIST_CONFIGURATION_SETTING_IMPL(NSNumber, FacebookCodelessDebugLogEnabled, _codelessDebugLogEnabled,
                                               _setCodelessDebugLogEnabled, @0);

+ (BOOL)isGraphErrorRecoveryEnabled
{
  return !g_disableErrorRecovery;
}

+ (void)setGraphErrorRecoveryEnabled:(BOOL)graphErrorRecoveryEnabled
{
  g_disableErrorRecovery = !graphErrorRecoveryEnabled;
}

+ (CGFloat)JPEGCompressionQuality
{
  return [self _JPEGCompressionQualityNumber].floatValue;
}

+ (void)setJPEGCompressionQuality:(CGFloat)JPEGCompressionQuality
{
  [self _setJPEGCompressionQualityNumber:@(JPEGCompressionQuality)];
}

+ (BOOL)isCodelessDebugLogEnabled
{
  return [self _codelessDebugLogEnabled].boolValue;
}

+ (void)setCodelessDebugLogEnabled:(BOOL)codelessDebugLogEnabled
{
  [self _setCodelessDebugLogEnabled:@(codelessDebugLogEnabled)];
}

+ (BOOL)isAutoLogAppEventsEnabled
{
  return g_autoLogAppEventsEnabled.boolValue;
}

+ (void)setAutoLogAppEventsEnabled:(BOOL)autoLogAppEventsEnabled
{
  if ([g_autoLogAppEventsEnabled isEqual:@(autoLogAppEventsEnabled)]) {
    return;
  }
  
  g_autoLogAppEventsEnabled = @(autoLogAppEventsEnabled);
  [[NSUserDefaults standardUserDefaults] setObject:g_autoLogAppEventsEnabled forKey:[NSString stringWithFormat:FBSDKSETTINGS_AUTOLOG_APPEVENTS_ENABLED_USER_DEFAULTS_KEY, [self appID]]];
}

+ (BOOL)isAdvertiserIDCollectionEnabled
{
  return g_advertiserIDCollectionEnabled.boolValue;
}

+ (void)setAdvertiserIDCollectionEnabled:(BOOL)advertiserIDCollectionEnabled
{
  if ([g_advertiserIDCollectionEnabled isEqual:@(advertiserIDCollectionEnabled)]) {
    return;
  }
  
  g_advertiserIDCollectionEnabled = @(advertiserIDCollectionEnabled);
  [[NSUserDefaults standardUserDefaults] setObject:g_advertiserIDCollectionEnabled forKey:[NSString stringWithFormat:FBSDKSETTINGS_ADVERTISERID_COLLECTION_ENABLED_USER_DEFAULTS_KEY, [self appID]]];
}

+ (BOOL)shouldLimitEventAndDataUsage
{
  NSNumber *storedValue = [[NSUserDefaults standardUserDefaults] objectForKey:FBSDKSettingsLimitEventAndDataUsage];
  if (storedValue == nil) {
    return NO;
  }
  return storedValue.boolValue;
}

+ (void)setLimitEventAndDataUsage:(BOOL)limitEventAndDataUsage
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setObject:@(limitEventAndDataUsage) forKey:FBSDKSettingsLimitEventAndDataUsage];
  [defaults synchronize];
}

+ (NSSet<FBSDKLoggingBehavior> *)loggingBehaviors
{
  if (!g_loggingBehaviors) {
    NSArray<FBSDKLoggingBehavior> *bundleLoggingBehaviors = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"FacebookLoggingBehavior"];
    if (bundleLoggingBehaviors) {
      g_loggingBehaviors = [[NSMutableSet alloc] initWithArray:bundleLoggingBehaviors];
    } else {
      // Establish set of default enabled logging behaviors.  You can completely disable logging by
      // specifying an empty array for FacebookLoggingBehavior in your Info.plist.
      g_loggingBehaviors = [[NSMutableSet alloc] initWithObjects:FBSDKLoggingBehaviorDeveloperErrors, nil];
    }
  }
  return [g_loggingBehaviors copy];
}

+ (void)setLoggingBehaviors:(NSSet<FBSDKLoggingBehavior> *)loggingBehaviors
{
  if (![g_loggingBehaviors isEqualToSet:loggingBehaviors]) {
    g_loggingBehaviors = [loggingBehaviors mutableCopy];
    
    [self updateGraphAPIDebugBehavior];
  }
}

+ (void)enableLoggingBehavior:(FBSDKLoggingBehavior)loggingBehavior
{
  if (!g_loggingBehaviors) {
    [self loggingBehaviors];
  }
  [g_loggingBehaviors addObject:loggingBehavior];
  [self updateGraphAPIDebugBehavior];
}

+ (void)disableLoggingBehavior:(FBSDKLoggingBehavior)loggingBehavior
{
  if (!g_loggingBehaviors) {
    [self loggingBehaviors];
  }
  [g_loggingBehaviors removeObject:loggingBehavior];
  [self updateGraphAPIDebugBehavior];
}

#pragma mark - Readonly Configuration Settings

+ (NSString *)sdkVersion
{
  return FBSDK_VERSION_STRING;
}

#pragma mark - Internal

+ (NSObject<FBSDKAccessTokenCaching> *)accessTokenCache
{
  return g_tokenCache;
}

+ (void)setAccessTokenCache:(NSObject<FBSDKAccessTokenCaching> *)cache
{
  if (g_tokenCache != cache) {
    g_tokenCache = cache;
  }
}

+ (NSString *)userAgentSuffix
{
  return g_userAgentSuffix;
}

+ (void)setUserAgentSuffix:(NSString *)suffix
{
  if (![g_userAgentSuffix isEqualToString:suffix]) {
    g_userAgentSuffix = suffix;
  }
}

+ (void)setGraphAPIVersion:(NSString *)version
{
  if (![g_defaultGraphAPIVersion isEqualToString:version])
  {
    g_defaultGraphAPIVersion = version;
  }
}

+ (NSString *)defaultGraphAPIVersion
{
  return FBSDK_TARGET_PLATFORM_VERSION;
}

+ (NSString *)graphAPIVersion
{
  return g_defaultGraphAPIVersion ?: self.defaultGraphAPIVersion;
}

+ (NSNumber *)appEventSettingsForPlistKey:(NSString *)plistKey
                             defaultValue:(NSNumber *)defaultValue
{
  return [[[NSBundle mainBundle] objectForInfoDictionaryKey:plistKey] copy] ?: defaultValue;
}

+ (NSNumber *)appEventSettingsForUserDefaultsKey:(NSString *)userDefaultsKey
                                    defaultValue:(NSNumber *)defaultValue
{
  NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:userDefaultsKey];
  if ([data isKindOfClass:[NSNumber class]]) {
    return (NSNumber *)data;
  }
  return defaultValue;
}

#pragma mark - Internal - Graph API Debug

+ (void)updateGraphAPIDebugBehavior
{
  // Enable Warnings everytime Info is enabled
  if ([g_loggingBehaviors containsObject:FBSDKLoggingBehaviorGraphAPIDebugInfo]
      && ![g_loggingBehaviors containsObject:FBSDKLoggingBehaviorGraphAPIDebugWarning]) {
    [g_loggingBehaviors addObject:FBSDKLoggingBehaviorGraphAPIDebugWarning];
  }
}

+ (NSString *)graphAPIDebugParamValue
{
  if ([[self loggingBehaviors] containsObject:FBSDKLoggingBehaviorGraphAPIDebugInfo]) {
    return @"info";
  } else if ([[self loggingBehaviors] containsObject:FBSDKLoggingBehaviorGraphAPIDebugWarning]) {
    return @"warning";
  }
  
  return nil;
}

@end
