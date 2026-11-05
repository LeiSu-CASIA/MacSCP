#import <Cocoa/Cocoa.h>
@interface MacSCPDraggingFixture : NSObject <NSDraggingInfo>
@property(nonatomic,strong) NSPasteboard *draggingPasteboard;
@property(nonatomic,weak) NSWindow *draggingDestinationWindow;
@property(nonatomic) NSDragOperation draggingSourceOperationMask;
@property(nonatomic) NSPoint draggingLocation;
@property(nonatomic) NSPoint draggedImageLocation;
@property(nonatomic,strong) NSImage *draggedImage;
@property(nonatomic,strong) id draggingSource;
@property(nonatomic) NSInteger draggingSequenceNumber;
@property NSDraggingFormation draggingFormation;
@property BOOL animatesToDestination;
@property NSInteger numberOfValidItemsForDrop;
@property(nonatomic) NSSpringLoadingHighlight springLoadingHighlight;
@end
