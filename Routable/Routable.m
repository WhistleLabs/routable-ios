//
//  Routable.m
//  Routable
//
//  Created by Clay Allsopp on 4/3/13.
//  Copyright (c) 2013 TurboProp Inc. All rights reserved.
//

#import "Routable.h"

@implementation Routable

+ (UPRouter *)sharedRouter {
  static UPRouter *_sharedRouter = nil;
  static dispatch_once_t oncePredicate;
  dispatch_once(&oncePredicate, ^{
    _sharedRouter = [self newRouter];
  });
  
  return _sharedRouter;
}

+ (UPRouter *)newRouter {
  return [UPRouter new];
}

@end

@interface RouterParams : NSObject
@property (readwrite, nonatomic, strong) UPRouterOptions *routerOptions;
@property (readwrite, nonatomic, strong) NSDictionary *extraDefaultParams;
@property (readwrite, nonatomic, strong) NSDictionary *openParams;
@end

@implementation RouterParams
@synthesize routerOptions = _routerOptions;
@synthesize extraDefaultParams = _extraDefaultParams;
@synthesize openParams = _openParams;

- (NSDictionary *)getControllerParams {
  NSMutableDictionary *controllerParams = [NSMutableDictionary new];
  
  [controllerParams addEntriesFromDictionary:self.routerOptions.defaultParams];
  [controllerParams addEntriesFromDictionary:self.extraDefaultParams];
  [controllerParams addEntriesFromDictionary:self.openParams];
  
  return controllerParams;
}

@end

@interface UPRouterOptions ()
@property (readwrite, nonatomic, strong) Class openClass;
@property (readwrite, nonatomic, copy) RouterOpenCallback callback;
@property (readwrite, nonatomic, strong) NSMutableArray *navigationControllers;
@end

@implementation UPRouterOptions

@synthesize modal = _modal;
@synthesize defaultParams = _defaultParams;
@synthesize openClass = _openClass;
@synthesize callback = _callback;

+ (UPRouterOptions *)modal {
  return [[UPRouterOptions new] modal];
}

+ (UPRouterOptions *)withPresentationStyle:(UIModalPresentationStyle)style {
  return [[UPRouterOptions new] withPresentationStyle:style];
}

+ (UPRouterOptions *)withTransitionStyle:(UIModalTransitionStyle)style {
  return [[UPRouterOptions new] withTransitionStyle:style];
}

+ (UPRouterOptions *)withPopupEntranceStyle:(DZPopupTransitionStyle)entranceStyle
                                  exitStyle:(DZPopupTransitionStyle)exitStyle {
  return [[UPRouterOptions new] withPopupEntranceStyle:entranceStyle exitStyle:exitStyle];
}

+ (UPRouterOptions *)forDefaultParams:(NSDictionary *)defaultParams {
  return [[UPRouterOptions new] forDefaultParams:defaultParams];
}

- (UPRouterOptions *)modal {
  self.modal = true;
  return self;
}

- (UPRouterOptions *)withPresentationStyle:(UIModalPresentationStyle)style {
  self.presentationStyle = style;
  return self;
}

- (UPRouterOptions *)withTransitionStyle:(UIModalTransitionStyle)style {
  self.transitionStyle = style;
  return self;
}

- (UPRouterOptions *)popup {
  self.popup = true;
  return self;
}

- (UPRouterOptions *)withPopupEdgeInsets:(UIEdgeInsets)edgeInsets {
  self.popupEdgeInsets = edgeInsets;
  return self;
}

- (UPRouterOptions *)withPopupEntranceStyle:(DZPopupTransitionStyle)entranceStyle
                                  exitStyle:(DZPopupTransitionStyle)exitStyle {
  self.popupEntranceStyle = entranceStyle;
  self.popupExitStyle = exitStyle;
  return self;
}

- (UPRouterOptions *)forDefaultParams:(NSDictionary *)defaultParams {
  self.defaultParams = defaultParams;
  return self;
}


@end

@interface UPRouter ()

// Map of URL format NSString -> RouterOptions
// i.e. "users/:id"
@property (readwrite, nonatomic, strong) NSMutableDictionary *routes;
// Map of final URL NSStrings -> RouterParams
// i.e. "users/16"
@property (readwrite, nonatomic, strong) NSMutableDictionary *cachedRoutes;
@property (readwrite, nonatomic, strong) NSMutableArray *navigationControllers;
@property (readwrite, nonatomic, strong) DZPopupSheetController *popupSheet;

@end

#define ROUTE_NOT_FOUND_FORMAT @"No route found for URL %@"
#define INVALID_CONTROLLER_FORMAT @"Your controller class %@ needs to implement %@"

#define CONTROLLER_SELECTOR @selector(initWithRouterParams:)

@implementation UPRouter

@synthesize rootNavigationController = _rootNavigationController;
@synthesize routes = _routes;
@synthesize cachedRoutes = _cachedRoutes;

- (id)init {
  if ((self = [super init])) {
    self.routes = [NSMutableDictionary new];
    self.cachedRoutes = [NSMutableDictionary new];
    self.navigationControllers = [NSMutableArray new];
  }

  return self;
}

- (UINavigationController *)currentNavigationController {
    NSUInteger count = [self.navigationControllers count];
    return count > 0 ? [self.navigationControllers objectAtIndex:count - 1] : self.rootNavigationController;
}

- (void)map:(NSString *)format toCallback:(RouterOpenCallback)callback {
  [self map:format toCallback:callback withOptions:nil];
}

- (void)map:(NSString *)format toCallback:(RouterOpenCallback)callback withOptions:(UPRouterOptions *)options {
  if (!options) {
    options = [UPRouterOptions new];
  }
  options.callback = callback;
  [self.routes setObject:options forKey:format];
}

- (void)map:(NSString *)format toController:(Class)controllerClass {
  [self map:format toController:controllerClass withOptions:nil];
}

- (void)map:(NSString *)format toController:(Class)controllerClass withOptions:(UPRouterOptions *)options {
  if (!options) {
    options = [UPRouterOptions new];
  }
  options.openClass = controllerClass;
  [self.routes setObject:options forKey:format];
}

- (void)openExternal:(NSString *)url {
  [[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
}

- (UIViewController *)open:(NSString *)url {
  return [self open:url animated:YES extraDefaultParams:nil];
}

- (UIViewController *)open:(NSString *)url animated:(BOOL)animated {
  return [self open:url animated:animated extraDefaultParams:nil];
}

- (UIViewController *)open:(NSString *)url animated:(BOOL)animated extraDefaultParams:(NSDictionary *)extraDefaultParams {
  RouterParams *params = [self routerParamsForUrl:url extraDefaultParams:extraDefaultParams];
  UPRouterOptions *options = params.routerOptions;
  
  if (options.callback) {
    RouterOpenCallback callback = options.callback;
    callback([params getControllerParams]);
    return nil;
  }
  
  if (!self.rootNavigationController) {
    @throw [NSException exceptionWithName:@"NavigationControllerNotProvided"
                                   reason:@"Router#rootNavigationController has not been set to a UINavigationController instance"
                                 userInfo:nil];
  }
  
  UIViewController *controller = [self controllerForRouterParams:params];

  if ([options isModal]) {
    if ([controller.class isSubclassOfClass:UINavigationController.class]) {
      [self.currentNavigationController presentViewController:controller
                                                     animated:animated
                                                   completion:nil];
      [self.navigationControllers addObject:controller];
    }
    else {
      UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:controller];
      navigationController.modalPresentationStyle = controller.modalPresentationStyle;
      navigationController.modalTransitionStyle = controller.modalTransitionStyle;
      [self.currentNavigationController presentViewController:navigationController
                                                     animated:animated
                                                   completion:nil];
      [self.navigationControllers addObject:navigationController];
    }
  }
  else if ([options isPopup]) {
    if (self.popupSheet) {
      [self popPopupSheet];
      self.popupSheet = nil;
    }
      
    UINavigationController *navigationController = [[UINavigationController alloc]
                                                    initWithRootViewController:controller];
    [navigationController setNavigationBarHidden:YES];
    self.popupSheet = [[DZPopupSheetController alloc] initWithContentViewController:navigationController];
    self.popupSheet.frameStyle = DZPopupSheetFrameStyleNone;
    self.popupSheet.entranceStyle = [options popupEntranceStyle];
    self.popupSheet.exitStyle = [options popupExitStyle];
    self.popupSheet.frameEdgeInsets = [options popupEdgeInsets];
    [self.popupSheet present];

    [self.navigationControllers addObject:navigationController];
  }
  else {
    [self.currentNavigationController pushViewController:controller animated:animated];
  }
  return controller;
}

- (void)pop {
  [self pop:YES];
}

- (void)pop:(BOOL)animated {
  if ([self.currentNavigationController.viewControllers count] <= 1) {
    [self popModalViewController:animated];
  }
  else {
    [self.currentNavigationController popViewControllerAnimated:animated];
  }
}

- (void)popModalViewController:(BOOL)animated {
  [self popModalViewController:animated completion:nil];
}

- (void)popModalViewController:(BOOL)animated completion:(void(^)(void))completion {
  [self.currentNavigationController dismissViewControllerAnimated:animated completion:completion];
  if ([self.navigationControllers count] > 0) {
    [self.navigationControllers removeObjectAtIndex:[self.navigationControllers count] - 1];
  }
}

- (void)popPopupSheet {
  [self popPopupSheetWithCompletion:nil];
}

- (void)popPopupSheetWithCompletion:(void(^)(void))completion {
  [self.popupSheet dismissWithCompletion:completion];
  if ([self.navigationControllers count] > 0) {
    [self.navigationControllers removeObjectAtIndex:[self.navigationControllers count] - 1];
  }
}

- (UIViewController *)controllerForURL:(NSString *)url {
  RouterParams *params = [self routerParamsForUrl:url extraDefaultParams:nil];
  UPRouterOptions *options = params.routerOptions;
  if (options.callback) {
    return nil;
  }
  return [self controllerForRouterParams:params];
}

///////

- (RouterParams *)routerParamsForUrl:(NSString *)url extraDefaultParams:(NSDictionary *)extraDefaultParams {
  if ([self.cachedRoutes objectForKey:url] && [extraDefaultParams count] == 0) {
    return [self.cachedRoutes objectForKey:url];
  }
  
  NSArray *pathAndQueryParams = [url componentsSeparatedByString:@"?"];
  NSString *path = [pathAndQueryParams objectAtIndex:0];
    
  NSArray *givenParts = [path componentsSeparatedByString:@"/"];
  
  RouterParams *openParams = nil;
  for (NSString *routerUrl in self.routes.allKeys) {
    UPRouterOptions *routerOptions = (UPRouterOptions *)[self.routes objectForKey:routerUrl];
    NSArray *routerParts = [routerUrl componentsSeparatedByString:@"/"];
    
    if (routerParts.count != givenParts.count) {
      continue;
    }
    
    NSDictionary *givenParams = [self paramsForUrlComponents:givenParts withRouterUrlComponents:routerParts];
    if (!givenParams) {
      continue;
    }
    
    openParams = [RouterParams new];
    openParams.openParams = givenParams;
    openParams.routerOptions = routerOptions;
    openParams.extraDefaultParams = extraDefaultParams;
    break;
  }
  
  if (!openParams) {
    @throw [NSException exceptionWithName:@"RouteNotFoundException"
                                   reason:[NSString stringWithFormat:ROUTE_NOT_FOUND_FORMAT, url]
                                 userInfo:nil];
  }
    
  if ([pathAndQueryParams count] > 1) {
    NSMutableDictionary *givenParams = [openParams.openParams mutableCopy];
    NSArray *queryParams = [[pathAndQueryParams objectAtIndex:1] componentsSeparatedByString:@"@"];
    for (NSString *param in queryParams) {
      NSArray *keyAndValue = [param componentsSeparatedByString:@"="];
      if ([keyAndValue count] < 2) {
        continue;
      }
      [givenParams setObject:[keyAndValue objectAtIndex:1]
                      forKey:[keyAndValue objectAtIndex:0]];
    }
    openParams.openParams = givenParams;
  }
  
  [self.cachedRoutes setObject:openParams forKey:url];
  
  return openParams;
}

- (NSDictionary *)paramsForUrlComponents:(NSArray *)givenUrlComponents
                 withRouterUrlComponents:(NSArray *)routerUrlComponents {
  NSMutableDictionary *params = [NSMutableDictionary new];

  [params setObject:[routerUrlComponents componentsJoinedByString:@"/"]
             forKey:@"routeURL"];
  
  for (int i = 0; i < routerUrlComponents.count; i++) {
    NSString *routerComponent = routerUrlComponents[i];
    NSString *givenComponent = givenUrlComponents[i];
    
    if ([[routerComponent substringToIndex:1] isEqualToString:@":"]) {
      NSString *key = [routerComponent substringFromIndex:1];
      [params setObject:givenComponent forKey:key];
      continue;
    }
    
    if (![routerComponent isEqualToString:givenComponent]) {
      return nil;
    }
  }
  
  return params;
}

- (UIViewController *)controllerForRouterParams:(RouterParams *)params {
  UIViewController *controller = [params.routerOptions.openClass alloc];
  
  if ([controller respondsToSelector:CONTROLLER_SELECTOR]) {
    controller = [controller performSelector:CONTROLLER_SELECTOR withObject:[params getControllerParams]];
  }
  else {
    @throw [NSException exceptionWithName:@"RoutableInitializerNotFound"
                                   reason:[NSString stringWithFormat:INVALID_CONTROLLER_FORMAT, NSStringFromClass([controller class]), NSStringFromSelector(CONTROLLER_SELECTOR)]
                                 userInfo:nil];
  }
  
  controller.modalTransitionStyle = params.routerOptions.transitionStyle;
  controller.modalPresentationStyle = params.routerOptions.presentationStyle;
  
  return controller;
}

@end
