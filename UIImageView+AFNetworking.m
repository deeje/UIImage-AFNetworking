// UIImageView+AFNetworking.m
//
// Copyright (c) 2011 Gowalla (http://gowalla.com/)
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>

#if __IPHONE_OS_VERSION_MIN_REQUIRED
#import "UIImageView+AFNetworking.h"
#import "ImageHelpers.h"

@interface AFImageCache : NSCache
@property (strong, nonatomic)   NSString    *cachePath;
@property (strong, nonatomic)   NSDate      *lastCompress;
@property (nonatomic)           BOOL        compressing;
- (UIImage *)cachedImageForPath:(NSString*)path;
- (UIImage *)cachedImageForRequest:(NSURLRequest *)request;
- (void)cacheImageData:(NSData *)imageData
               forPath:(NSString *)path;
- (void)cacheImageData:(NSData *)imageData
            forRequest:(NSURLRequest *)request;
- (void)cacheImage:(UIImage*)anImage
           forPath:(NSString*)path;
@end


#pragma mark -


static char kAFImageRequestOperationObjectKey;
static char kAFImagePathObjectKey;


@interface UIImageView (_AFNetworking)
@property (readwrite, nonatomic, retain, setter = af_setImagePath:) NSString* af_imagePath;
@property (readwrite, nonatomic, retain, setter = af_setImageRequestOperation:) AFImageRequestOperation *af_imageRequestOperation;
@end


@implementation UIImageView (_AFNetworking)
@dynamic af_imagePath;
@dynamic af_imageRequestOperation;
@end


#pragma mark -


@implementation UIImageView (AFNetworking)

- (AFHTTPRequestOperation *)af_imageRequestOperation
{
    return (AFHTTPRequestOperation *)objc_getAssociatedObject(self, &kAFImageRequestOperationObjectKey);
}


- (void)af_setImageRequestOperation:(AFImageRequestOperation *)imageRequestOperation
{
    objc_setAssociatedObject(self, &kAFImageRequestOperationObjectKey, imageRequestOperation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}


- (NSString*)af_imagePath
{
    return (NSString*)objc_getAssociatedObject(self, &kAFImagePathObjectKey);
}


- (void)af_setImagePath:(NSString *)imagePath
{
    objc_setAssociatedObject(self, &kAFImagePathObjectKey, imagePath, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}


+ (NSOperationQueue *)af_sharedImageRequestOperationQueue
{
    static NSOperationQueue *_af_imageRequestOperationQueue = nil;
    
    static dispatch_once_t onceSharedImageRequestOperationQueuePredicate;
    dispatch_once(&onceSharedImageRequestOperationQueuePredicate, ^
                  {
                      _af_imageRequestOperationQueue = [[NSOperationQueue alloc] init];
                      [_af_imageRequestOperationQueue setMaxConcurrentOperationCount:2];
                  });
    
    return _af_imageRequestOperationQueue;
}


+ (AFImageCache *)af_sharedImageCache
{
    static AFImageCache *_af_imageCache = nil;
    static dispatch_once_t onceSharedImageCachePredicate;
    dispatch_once(&onceSharedImageCachePredicate, ^
                  {
                      _af_imageCache = [[AFImageCache alloc] init];
                      
                      
                  });
    
    return _af_imageCache;
}


+ (dispatch_queue_t)sharedScalerQueue
{
    static dispatch_queue_t _sharedScalerQueue = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^
      {
          _sharedScalerQueue = dispatch_queue_create("com.thirstlabs.thirst.imageScaler", DISPATCH_QUEUE_CONCURRENT);
      });
    
    return _sharedScalerQueue;
}


#pragma mark -

- (void)setImageWithURL:(NSURL *)url
{
    [self setImageWithURL:url placeholderImage:nil];
}


- (void)setImageWithURL:(NSURL *)url 
       placeholderImage:(UIImage *)placeholderImage
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0];
    [request setHTTPShouldHandleCookies:NO];
    [request setHTTPShouldUsePipelining:YES];
    
    [self setImageWithURLRequest:request placeholderImage:placeholderImage success:nil failure:nil];
}


- (void)setImageWithURLRequest:(NSURLRequest *)urlRequest 
              placeholderImage:(UIImage *)placeholderImage 
                       success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, UIImage *image))success
                       failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error))failure
{
    NSString    *requestPath = [[urlRequest URL] absoluteString];
    if ([self.af_imagePath isEqualToString:requestPath] && self.image)
        return;
    
    if ([urlRequest URL])
    {
        self.af_imagePath = requestPath;
    }
    else
    {
        self.af_imagePath = nil;
        return;
    }
    
    [self cancelImageRequestOperation];
    
    CGSize  targetSize = self.frame.size;
    if (!targetSize.width || !targetSize.height)
        return;
        
    self.image = nil;
    
    dispatch_async([[self class] sharedScalerQueue], ^(void)
    {
        NSString    *scaledImagePath = [[[urlRequest URL] URLByAppendingPathComponent:[NSString stringWithFormat:@"(%fx%f)", targetSize.width, targetSize.height]] absoluteString];
        UIImage     *prescaledImage = [[[self class] af_sharedImageCache] cachedImageForPath:scaledImagePath];
        if (prescaledImage)
        {
            dispatch_async(dispatch_get_main_queue(), ^
                           {
                               self.image = prescaledImage;
                               if (success)
                               {
                                   success(nil, nil, prescaledImage);
                               }
                           });
            
            self.af_imageRequestOperation = nil;
        }
        else
        {
            UIImage *cachedImage = [[[self class] af_sharedImageCache] cachedImageForRequest:urlRequest];
            if (cachedImage)
            {
                UIImage *scaledImage = [cachedImage aspectScaleToSize:targetSize];
                                
                dispatch_async(dispatch_get_main_queue(), ^
                   {
                       self.alpha = 0.0;
                       self.image = scaledImage;
                       [UIView animateWithDuration:0.2 
                                             delay:0.0
                                           options:UIViewAnimationOptionAllowUserInteraction
                                        animations:^
                        {
                            self.alpha = 1.0;
                        }
                                        completion:nil];
                       
                       if (success)
                       {
                           success(nil, nil, scaledImage);
                       }
                   });
                
                if (scaledImagePath)
                    [[[self class] af_sharedImageCache] cacheImage:scaledImage forPath:scaledImagePath];
                
                self.af_imageRequestOperation = nil;
            }
            else
            {
                dispatch_async(dispatch_get_main_queue(), ^
                               {
                                   self.image = placeholderImage;
                               });
                
                AFImageRequestOperation *requestOperation = [[AFImageRequestOperation alloc] initWithRequest:urlRequest];
                requestOperation.successCallbackQueue = [[self class] sharedScalerQueue];
                requestOperation.failureCallbackQueue = [[self class] sharedScalerQueue];
                [requestOperation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject)
                 {
                     UIImage  *scaledImage = responseObject;
                     
                     if ([[urlRequest URL] isEqual:[[self.af_imageRequestOperation request] URL]])
                     {
                         scaledImage = [scaledImage aspectScaleToSize:targetSize];
                         
                         dispatch_async(dispatch_get_main_queue(), ^
                            {
                                self.alpha = 0.0;
                                self.image = scaledImage;
                                [UIView animateWithDuration:0.2 
                                                      delay:0.0
                                                    options:UIViewAnimationOptionAllowUserInteraction
                                                 animations:^
                                 {
                                     self.alpha = 1.0;
                                 }
                                                 completion:nil];
                                
                                if (success)
                                {
                                    success(operation.request, operation.response, scaledImage);
                                }
                            });
                     }
                     
                     [[[self class] af_sharedImageCache] cacheImageData:operation.responseData forRequest:urlRequest];
                     if (scaledImagePath)
                         [[[self class] af_sharedImageCache] cacheImage:scaledImage forPath:scaledImagePath];
                     
                     self.af_imageRequestOperation = nil;
                 }
                                                        failure:^(AFHTTPRequestOperation *operation, NSError *error)
                 {
                     if (failure)
                     {
                         dispatch_async(dispatch_get_main_queue(), ^
                                        {
                                            failure(operation.request, operation.response, error);
                                        });
                     }
                     
                     self.af_imageRequestOperation = nil;
                 }];
                
                self.af_imageRequestOperation = requestOperation;
                
                [[[self class] af_sharedImageRequestOperationQueue] addOperation:self.af_imageRequestOperation];
            }
        }        
    });
}


- (void)cancelImageRequestOperation
{
    [self.af_imageRequestOperation cancel];
    self.af_imageRequestOperation = nil;
}


@end



#pragma mark -

static inline NSString * AFImageCacheKeyFromPath(NSString *path)
{
    const char *cstr = [path cStringUsingEncoding:NSUTF8StringEncoding];
    NSData *data = [NSData dataWithBytes:cstr length:path.length];
    
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    
    CC_SHA1(data.bytes, data.length, digest);
    
    NSMutableString* output = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    
    for(int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++)
        [output appendFormat:@"%02x", digest[i]];
    
    return output;
}


@implementation AFImageCache

@synthesize cachePath = _cachePath;

- (id)init
{
    self = [super init];
    if (self)
    {
        NSArray* cachePathArray = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString* cachePath = [cachePathArray lastObject];
        cachePath = [cachePath stringByAppendingPathComponent:@"Images"];
        
        NSFileManager* localFileManager = [[NSFileManager alloc] init];

        if (![localFileManager fileExistsAtPath:cachePath])
        {
            NSError *anError = nil;
            [localFileManager createDirectoryAtPath:cachePath withIntermediateDirectories:YES attributes:nil error:&anError];
        }
        
        self.cachePath = cachePath;
    }
    return self;
}


- (UIImage *)cachedImageForPath:(NSString*)path
{
    NSString    *imageKey = AFImageCacheKeyFromPath(path);
    UIImage *image = [UIImage imageWithData:[self objectForKey:imageKey]];
    
    if (!image)
    {
        NSString    *imagePath = [self.cachePath stringByAppendingPathComponent:imageKey];
        NSData      *imageData = [NSData dataWithContentsOfFile:imagePath];
        if (imageData)
        {
            image = [UIImage imageWithData:imageData];
            
            [self setObject:[NSPurgeableData dataWithData:imageData] forKey:imageKey];
            
            NSFileManager* localFileManager = [[NSFileManager alloc] init];
            [localFileManager setAttributes:@{NSFileModificationDate:[NSDate date]}
                               ofItemAtPath:imagePath
                                      error:nil];
        }
    }
    
    return image;
}


- (UIImage *)cachedImageForRequest:(NSURLRequest *)request
{
    switch ([request cachePolicy])
    {
        case NSURLRequestReloadIgnoringCacheData:
        case NSURLRequestReloadIgnoringLocalAndRemoteCacheData:
            return nil;
        default:
            break;
    }
    
    return [self cachedImageForPath:[[request URL] absoluteString]];
}


- (void)cacheImageData:(NSData *)imageData
               forPath:(NSString *)path
{
    NSString    *imageKey = AFImageCacheKeyFromPath(path);
    
    [self setObject:[NSPurgeableData dataWithData:imageData] forKey:imageKey];
    
    NSString    *imagePath = [self.cachePath stringByAppendingPathComponent:imageKey];
    [imageData writeToFile:imagePath atomically:YES];
    
    if ([self shouldCompress])
        dispatch_async(dispatch_get_main_queue(), ^
                       {
                           [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(compress) object:nil];
                           [self performSelector:@selector(compress) withObject:nil afterDelay:2.0];
                       });
}


- (void)cacheImageData:(NSData *)imageData
            forRequest:(NSURLRequest *)request
{
    [self cacheImageData:imageData forPath:[[request URL] absoluteString]];
}


- (void)cacheImage:(UIImage*)anImage
           forPath:(NSString*)path
{
    [self cacheImageData:UIImagePNGRepresentation(anImage) forPath:path];
}


- (BOOL)shouldCompress
{
    BOOL    should = YES;
    
    if (self.lastCompress)
    {
        NSTimeInterval  delta = -[self.lastCompress timeIntervalSinceNow];
        if (delta < (60 * 60 * 1))
            should = NO;
    }

    if (self.compressing)
        should = NO;
    
    return should;
}


- (void)compress
{
    if (![self shouldCompress])
        return;
    
    self.compressing = YES;
    self.lastCompress = [NSDate date];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^
                   {
                       NSError          *anError = nil;
                       NSDate           *cacheAgeLimit = [NSDate dateWithTimeIntervalSinceNow:-(60 * 60 * 24 * 3)];
                       NSFileManager    *localFileManager = [[NSFileManager alloc] init];
                       
                       /*
                       NSURL    *cachePathURL = [NSURL fileURLWithPath:self.cachePath isDirectory:YES];
                       NSArray  *cachedItems = [localFileManager contentsOfDirectoryAtURL:cachePathURL
                                                               includingPropertiesForKeys:@[NSURLPathKey, NSURLContentAccessDateKey]
                                                                                  options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                    error:&anError];
                       */
                       NSArray  *cachedItems = [localFileManager contentsOfDirectoryAtPath:self.cachePath error:&anError];
                       for (NSString *aCachedItem in cachedItems)
                       {
                           NSString     *itemPath = [self.cachePath stringByAppendingPathComponent:aCachedItem];
                           NSDictionary *attributes = [localFileManager attributesOfItemAtPath:itemPath error:&anError];
                           
                           if (!anError)
                           {
                               NSDate   *lastAccessDate = [attributes objectForKey:NSFileModificationDate];
                               if ([lastAccessDate compare:cacheAgeLimit] != NSOrderedDescending)
                               {
                                   [localFileManager removeItemAtPath:itemPath error:&anError];
                               }
                           }
                       }
                       
                       self.compressing = NO;
                   });
}


@end


#endif
