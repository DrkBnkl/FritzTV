#import <Foundation/Foundation.h>

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
