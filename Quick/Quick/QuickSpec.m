//
//  QCKSpec.m
//  Quick
//
//  Created by Brian Ivan Gesiak on 6/6/14.
//  Copyright (c) 2014 Brian Ivan Gesiak. All rights reserved.
//

#import "QuickSpec.h"
#import "NSString+QCKSelectorName.h"
#import <Quick/Quick-Swift.h>
#import <objc/runtime.h>

const void * const QCKExampleKey = &QCKExampleKey;

@interface QuickSpec ()
@property (nonatomic, strong) Example *example;
@end

@implementation QuickSpec

#pragma mark - XCTestCase Overrides

/**
 The runtime sends initialize to each class in a program just before the class, or any class
 that inherits from it, is sent its first message from within the program. QuickSpec hooks into
 this event to compile the example groups for this spec subclass.

 If an exception occurs when compiling the examples, report it to the user. Chances are they
 included an expectation outside of a "it", "describe", or "context" block.
 */
+ (void)initialize {
    [World setCurrentExampleGroup:[World rootExampleGroupForSpecClass:[self class]]];
    QuickSpec *spec = [self new];

    @try {
        [spec spec];
    }
    @catch (NSException *exception) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"An exception occurred when building Quick's example groups.\n"
                           @"Perhaps an 'expect(...).to' expectation was evaluated outside of "
                           @"an 'it', 'context', or 'describe' block?\nHere's the original "
                           @"exception: '%@', reason: '%@', userInfo: '%@'",
                           exception.name, exception.reason, exception.userInfo];
    }
}

/**
 Invocations for each test method in the test case. QuickSpec overrides this method to define a
 new method for each example defined in +[QuickSpec spec].

 @return An array of invocations that execute the newly defined example methods.
 */
+ (NSArray *)testInvocations {
    NSArray *examples = [World rootExampleGroupForSpecClass:[self class]].examples;
    NSMutableArray *invocations = [NSMutableArray arrayWithCapacity:[examples count]];

    for (Example *example in examples) {
        SEL selector = [self addInstanceMethodForExample:example];
        NSInvocation *invocation = [self invocationForInstanceMethodWithSelector:selector
                                                                         example:example];
        [invocations addObject:invocation];
    }

    return invocations;
}

/**
 XCTest sets the invocation for the current test case instance using this setter.
 QuickSpec hooks into this event to give the test case a reference to the current example.
 It will need this reference to correctly report its name to XCTest.
 */
- (void)setInvocation:(NSInvocation *)invocation {
    self.example = objc_getAssociatedObject(invocation, QCKExampleKey);
    [super setInvocation:invocation];
}

/**
 The test's name. XCTest expects this to be overridden by subclasses. By default, this
 uses the invocation's selector's name (i.e.: "-[WinterTests testWinterIsComing]").
 QuickSpec overrides this method to provide the name of the test class, along with a
 string made up of the example group and example descriptions.

 @return A string to be displayed in the log navigator as the test is being run.
 */
- (NSString *)name {
    return [NSString stringWithFormat:@"%@: %@",
            NSStringFromClass([self class]), self.example.name];
}

#pragma mark - Public Interface

- (void)spec { }

#pragma mark - Internal Methods

/**
 QuickSpec uses this method to dynamically define a new instance method for the
 given example. The instance method runs the example, catching any exceptions.
 The exceptions are then reported as test failures.

 In order to report the correct file and line number, examples must raise exceptions
 containing following keys in their userInfo:

 - "SenTestFilenameKey": A String representing the file name
 - "SenTestLineNumberKey": An Int representing the line number

 These keys used to be used by SenTestingKit, and are still used by some testing tools
 in the wild. See: https://github.com/modocache/Quick/pull/41

 @return The selector of the newly defined instance method.
 */
+ (SEL)addInstanceMethodForExample:(Example *)example {
    IMP implementation = imp_implementationWithBlock(^(id self){
        @try {
            [example run];
        }
        @catch (NSException *exception) {
            Callsite *callsite = exception.qck_callsite ? exception.qck_callsite : example.callsite;
            Failure *failure = [Failure failureWithException:exception
                                                    callsite:callsite];
            [self recordFailure:failure];
        }
    });
    const char *types = [[NSString stringWithFormat:@"%s%s%s", @encode(id), @encode(id), @encode(SEL)] UTF8String];
    SEL selector = NSSelectorFromString(example.name.qck_selectorName);
    class_addMethod(self, selector, implementation, types);

    return selector;
}

+ (NSInvocation *)invocationForInstanceMethodWithSelector:(SEL)selector
                                                  example:(Example *)example {
    NSMethodSignature *signature = [self instanceMethodSignatureForSelector:selector];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.selector = selector;
    objc_setAssociatedObject(invocation,
                             QCKExampleKey,
                             example,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return invocation;
}

/**
 This method is used to record failures, whether they represent example
 expectations that were not met, or exceptions raised during test setup
 and teardown. By default, the failure will be reported as an
 XCTest failure, and the example will be highlighted in Xcode.
 */
- (void)recordFailure:(Failure *)failure {
    [self recordFailureWithDescription:failure.exception.reason
                                inFile:failure.callsite.file
                                atLine:failure.callsite.line
                              expected:NO];
}

@end
