#import <Foundation/Foundation.h>
#import <Security/Security.h>

/// Führt einen Block aus und fängt etwaige Objective-C-Ausnahmen (NSException) ab,
/// damit sie nicht zu einem fatalen Absturz (SIGABRT) in Swift führen.
static inline BOOL SafeObjCExecute(void (^ _Nonnull block)(void)) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
}

/// Erzeugt eine SecAccessRef mit deaktivierter Abfrage (promptSelector.flags = 0), damit
/// ad-hoc signierte macOS-Builds das Kennwort ohne ständige macOS-Schlüsselbundabfrage lesen können.
static inline SecAccessRef _Nullable CF_RETURNS_RETAINED CreateUnrestrictedKeychainAccess(NSString * _Nonnull label) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    SecAccessRef access = NULL;
    OSStatus status = SecAccessCreate((__bridge CFStringRef)label, NULL, &access);
    if (status != errSecSuccess || !access) {
        return NULL;
    }
    CFArrayRef aclList = NULL;
    if (SecAccessCopyACLList(access, &aclList) == errSecSuccess && aclList) {
        CFIndex count = CFArrayGetCount(aclList);
        for (CFIndex i = 0; i < count; i++) {
            SecACLRef acl = (SecACLRef)CFArrayGetValueAtIndex(aclList, i);
            CFArrayRef appList = NULL;
            CFStringRef promptDesc = NULL;
            CSSM_ACL_KEYCHAIN_PROMPT_SELECTOR promptSelector;
            if (SecACLCopySimpleContents(acl, &appList, &promptDesc, &promptSelector) == errSecSuccess) {
                promptSelector.flags = 0;
                SecACLSetSimpleContents(acl, NULL, promptDesc, &promptSelector);
                if (appList) CFRelease(appList);
                if (promptDesc) CFRelease(promptDesc);
            }
        }
        CFRelease(aclList);
    }
    return access;
#pragma clang diagnostic pop
}
