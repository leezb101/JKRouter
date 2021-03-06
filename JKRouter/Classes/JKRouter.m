//
//  JKRouter.m
//  
//
//  Created by nie on 17/1/11.
//  Copyright © 2017年 localadmin. All rights reserved.
//

#import "JKRouter.h"
#import "JKRouterKeys.h"
#import "JKDataHelper.h"

//**********************************************************************************
//*
//*           RouterOptions类
//*           配置跳转时的各种设置
//**********************************************************************************

@interface RouterOptions()

//每个页面所对应的moduleID
@property (nonatomic, copy, readwrite) NSString *moduleID;

@end


@implementation RouterOptions

+ (instancetype)options{
    RouterOptions *options = [RouterOptions new];
    options.theAccessRight = JKRouterAccessRightDefalut;
    options.animated = YES;
    return options;
}

+ (instancetype)optionsWithModuleID:(NSString *)moduleID{

    RouterOptions *options = [RouterOptions options];
    options.moduleID = moduleID;
    return options;
}


+ (instancetype)optionsWithDefaultParams:(NSDictionary *)params{
    
    RouterOptions *options = [RouterOptions options];
    options.defaultParams = params;
    return options;
}

- (instancetype)optionsWithDefaultParams:(NSDictionary *)params{

    self.defaultParams = params;
    return self;
}

@end


@implementation JKouterConfig


@end



//**********************************************************************************
//*
//*           JKRouter类
//*
//**********************************************************************************



@interface JKRouter()

@property (nonatomic, copy, readwrite) NSSet * modules;     ///< 存储路由，moduleID信息，权限配置信息
@property (nonatomic, copy, readwrite) NSSet * specialOptionsSet;     ///< 特殊跳转的页面信息的集合
@property (nonatomic,copy) NSArray<NSString *>*modulesInfoFiles; // 路由配置信息的json文件名数组
@property (nonatomic,copy) NSString *sepcialJumpListFileName; ////跳转时有特殊动画的plist文件名

@property (nonatomic,strong) NSString *URLScheme;//自定义的URL协议名字

@property (nonatomic,strong) NSString *webContainerName;//自定义的URL协议名字


@property (nonatomic,weak) UINavigationController *navigationController; ///< app的导航控制器

@end

@implementation JKRouter


//重写该方法，防止外部修改该类的对象
+ (BOOL)accessInstanceVariablesDirectly{
        
    return NO;
}


static JKRouter *defaultRouter =nil;

/**
 初始化单例
 
 @return JKRouter 的单例对象
 */
+ (instancetype)router{

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaultRouter = [JKRouter new];
    });
    
    return defaultRouter;
}

+ (void)routerWithConfig:(JKouterConfig *)config{
    
    [JKRouter router].modulesInfoFiles = config.modulesInfoFiles;
    [JKRouter router].sepcialJumpListFileName = config.sepcialJumpListFileName;
    [JKRouter router].URLScheme = config.URLScheme;
    [JKRouter router].webContainerName = config.webContainerName;
    [JKRouter router].navigationController = config.navigationController;
    [self configModules];
}

# pragma mark the open functions - - - - - - - - -
+ (void)open:(NSString *)vcClassName{
    
    RouterOptions *options = [RouterOptions options];
    [self open:vcClassName options:options];
}


+ (void)open:(NSString *)vcClassName options:(RouterOptions *)options{

    [self open:vcClassName options:options CallBack:nil];
}


+ (void)open:(NSString *)vcClassName options:(RouterOptions *)options CallBack:(void(^)())callback{
    
    if (!JKSafeStr(vcClassName)) {
        
        NSLog(@"vcClassName is nil or vcClassName is not a string");
        return;
    }
    
    if (!options) {
        options = [RouterOptions options];
        
    }
    options = [JKAccessRightHandler configTheAccessRight:options];
    
    if (![JKAccessRightHandler  validateTheRightToOpenVC:options]) {//权限不够进行别的操作处理
        //根据具体的权限设置决定是否进行跳转，如果没有权限，跳转中断，进行后续处理
        [JKAccessRightHandler handleNoRightToOpenVC:options];
        return;
    }
    
    
    if (!([JKRouter router].navigationController && [[JKRouter router].navigationController isKindOfClass:[UINavigationController class]])) {
        return;
    }
    
    
    UIViewController *vc = [self configVC:vcClassName options:options];
    //根据配置好的VC，options配置进行跳转
    [self routerViewController:vc options:options];
    
    if (callback) {
        callback();
    }
    
}


+ (void)URLOpen:(NSString *)url{
    
    [self URLOpen:url params:nil];
}


+ (void)URLOpen:(NSString *)url params:(NSDictionary *)params{
    
    if (![JKAccessRightHandler safeValidateURL:url]) {
        return;
    }
    
    url = [url stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSURL *tempURL = [NSURL URLWithString:url];
    NSString *scheme =tempURL.scheme;
    NSString *resourceSpecifier = tempURL.resourceSpecifier;
    if (![scheme isEqualToString:[JKRouter router].URLScheme]) {
        if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
            
            [self httpOpen:url];
            return;
            
        }else{
            
            scheme = [JKRouter router].URLScheme;
            
        }
    }
    url = [NSString stringWithFormat:@"%@:%@",scheme,resourceSpecifier];
    
    //拼接后最终的URL
    NSURL *targetURL = [NSURL URLWithString:url];
    
    //URL的端口号作为moduleID
    NSNumber *moduleID = targetURL.port;
    NSString *path =targetURL.path;
    
    
    if (JKSafeStr(path)&& ![path isEqualToString:@""]) {//路径
        
        if (!JKSafeDic(params)) {
            NSString *directory = [JKJSONHandler searchDirectoryWithModuleID:moduleID specifiedPath:path];
            RouterOptions *options = [RouterOptions optionsWithModuleID:[NSString stringWithFormat:@"%@",moduleID]];
            options = [JKAccessRightHandler configTheAccessRight:options];
            [self jumpToHttpWeb:directory options:options];
            return;
        }
        
        NSAssert(NO, @"有路径path的话参数通过URL携带，不支持额外传入params参数");
        
    }else{
        NSString *parameterStr = [[targetURL query] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        if (JKSafeStr(parameterStr)) {
            
            NSMutableDictionary *dic = [NSMutableDictionary dictionary];
            NSArray *parameterArr = [parameterStr componentsSeparatedByString:@"&"];
            for (NSString *parameter in parameterArr) {
                NSArray *parameterBoby = [parameter componentsSeparatedByString:@"="];
                if (parameterBoby.count == 2) {
                    [dic setObject:parameterBoby[1] forKey:parameterBoby[0]];
                }else
                {
                    NSLog(@"参数不完整");
                }
            }
            
            //执行页面的跳转
            [self openVCWithModuleID:[moduleID integerValue] params:[dic copy]];
            return;
        }else{
            
            //执行页面的跳转
            [self openVCWithModuleID:[moduleID integerValue] params:[params copy]];
            return;
        }
        
    }
    
}

/**
 查询并配置相关参数，执行页面的跳转
 
 @param moduleID 模块的ID
 @param params 跳转时要传入的参数
 */
+ (void)openVCWithModuleID:(NSInteger)moduleID params:(NSDictionary *)params{
    
    NSEnumerator * enumerator = [[JKRouter router].modules objectEnumerator];
    NSDictionary *module =nil;
    while (module = [enumerator nextObject]) {
        NSEnumerator * specailEnumerator = [[JKRouter router].specialOptionsSet objectEnumerator];
        NSDictionary *specialModule =nil;
        NSString *vcClassName =[JKJSONHandler searchVcClassNameWithModuleID:moduleID];
        
        while (specialModule = [specailEnumerator nextObject]) {
            
            if ([JKJSONHandler validateSpecialJump:specialModule moduleID:moduleID]) {
                RouterOptions *options = [RouterOptions optionsWithDefaultParams:params];
                options = [JKAccessRightHandler configTheAccessRight:options];
                options.moduleID = [NSString stringWithFormat:@"%d",(int)moduleID];
                options.isModal = YES;
                [self open:vcClassName options:options];
                return;
            }
            
        }
        //  此时不存在特殊跳转的情况
        RouterOptions *options = [RouterOptions optionsWithDefaultParams:params];
        options = [JKAccessRightHandler configTheAccessRight:options];
        options.moduleID = [NSString stringWithFormat:@"%d",(int)moduleID];
        [self open:vcClassName options:options];
        return;
    }
    
}



+ (void)httpOpen:(NSString *)url{
    RouterOptions *options = [RouterOptions options];
    options = [JKAccessRightHandler configTheAccessRight:options];
    [self jumpToHttpWeb:url options:options];
}


/**
 根据路径跳转到指定的httpWeb页面
 
 @param directory 指定的路径
 */
+ (void)jumpToHttpWeb:(NSString *)directory options:(RouterOptions *)options{
    if (!JKSafeStr(directory)) {
        NSLog(@"路径不存在");
        return;
    }
    
    if ([JKAccessRightHandler validateTheRightToOpenVC:options]) {
        NSDictionary *params = @{jkWebURLKey:directory};
        options.defaultParams =params;
        [self open:[JKRouter router].webContainerName options:options];
        
    }else{
        NSLog(@"没有权限打开相关页面");
        [JKAccessRightHandler handleNoRightToOpenVC:options];
    }
    
}


- (void)openExternal:(NSString *)url {
    NSURL *targetURL = [NSURL URLWithString:url];
    if ([targetURL.scheme isEqualToString:@"http"] ||[targetURL.scheme isEqualToString:@"https"]) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
    }else{
        NSAssert(NO, @"请打开http／https协议的url地址");
    }
    
}


#pragma mark  the pop functions - - - - - - - - - -


+ (void)pop{

    [self pop:YES];
}

+ (void)pop:(BOOL)animated{

    [self pop:nil :animated];
}

+ (void)pop:(NSDictionary *)params :(BOOL)animated{
    
    NSArray *vcArray = [JKRouter router].navigationController.viewControllers;
    NSUInteger count = vcArray.count;
    UIViewController *vc= nil;
    if (vcArray.count>1) {
        vc = vcArray[count-2];
    }else{
        //已经是根视图，不再执行pop操作  可以执行dismiss操作
        [self popToSpecifiedVC:nil animated:animated];

        return;
    }
    RouterOptions *options = [RouterOptions optionsWithDefaultParams:params];
    [self configTheVC:vc options:options];
    [self popToSpecifiedVC:vc animated:animated];

}


+ (void)popToSpecifiedVC:(UIViewController *)vc{

    [self popToSpecifiedVC:vc animated:YES];
}

+ (void)popToSpecifiedVC:(UIViewController *)vc animated:(BOOL)animated{

    if ([JKRouter router].navigationController.presentedViewController) {
        
        [[JKRouter router].navigationController dismissViewControllerAnimated:animated completion:nil];
    }
    else {
        
        [[JKRouter router].navigationController popToViewController:vc animated:animated];
    }
}



+ (void)popWithSpecifiedModuleID:(NSString *)moduleID{

    [self popWithSpecifiedModuleID:moduleID :nil :YES];
}

+ (void)popWithSpecifiedModuleID:(NSString *)moduleID :(NSDictionary *)params :(BOOL)animated{
    
    UIViewController *popVC = [JKJSONHandler searchExistViewControllerWithModuleID:moduleID];
    if (JKSafeObj(popVC)) {
        
        RouterOptions *options = [RouterOptions optionsWithDefaultParams:params];
        [self configTheVC:popVC options:options];
        [self popToSpecifiedVC:popVC animated:animated];
    }
    
}


#pragma mark  the tool functions - - - - - - - -


//如果modules信息不存在，将信息导入内存中
+ (void)configModules{

    
        NSArray *moudulesArr =[JKJSONHandler getModulesFromJsonFile:[JKRouter router].modulesInfoFiles];
        [JKRouter router].modules = [NSSet setWithArray:moudulesArr];
        
        NSString *path = [[NSBundle mainBundle] pathForResource:[JKRouter router].sepcialJumpListFileName ofType:nil];
        NSArray  *specialOptionsArr = [NSArray arrayWithContentsOfFile:path];
        [JKRouter router].specialOptionsSet = [NSSet setWithArray:specialOptionsArr];

}


//为ViewController 的属性赋值
+ (UIViewController *)configVC:(NSString *)vcClassName options:(RouterOptions *)options {

    Class VCClass = NSClassFromString(vcClassName);
    UIViewController *vc = [VCClass new];
    [vc setValue:options.moduleID forKey:@"moduleID"];
    
    [JKRouter configTheVC:vc options:options];
    
    return vc;
}


/**
 对于已经创建的vc进行赋值操作

 @param vc 对象
 @param params 赋值的参数
 */
+ (void)configTheVC:(UIViewController *)vc options:(RouterOptions *)options{

    if (JKSafeDic(options.defaultParams)) {
        NSArray *propertyNames = [options.defaultParams allKeys];
        for (NSString *key in propertyNames) {
            id value =options.defaultParams[key];
            [vc setValue:value forKey:key];
            
        }

    }

}

//根据相关的options配置，进行跳转
+ (void)routerViewController:(UIViewController *)vc options:(RouterOptions *)options{

    if ([JKRouter router].navigationController.presentationController) {
        
        [[JKRouter router].navigationController dismissViewControllerAnimated:options.animated completion:nil];
    }
    
    if (options.isModal) {
        
        [[JKRouter router].navigationController presentViewController:vc
                                                             animated:options.animated
                                                        completion:nil];
    }else{
        
        [[JKRouter router].navigationController pushViewController:vc animated:options.animated];
    }

}



@end
