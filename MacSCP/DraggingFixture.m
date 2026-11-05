#import "DraggingFixture.h"
@implementation MacSCPDraggingFixture
- (void)slideDraggedImageTo:(NSPoint)point { self.draggedImageLocation=point; }
- (NSArray<NSString *> *)namesOfPromisedFilesDroppedAtDestination:(NSURL *)destination { return nil; }
- (void)enumerateDraggingItemsWithOptions:(NSDraggingItemEnumerationOptions)options forView:(NSView *)view classes:(NSArray<Class> *)classes searchOptions:(NSDictionary<NSPasteboardReadingOptionKey,id> *)search usingBlock:(void (^)(NSDraggingItem *,NSInteger,BOOL *))block { }
- (void)resetSpringLoading { }
@end
