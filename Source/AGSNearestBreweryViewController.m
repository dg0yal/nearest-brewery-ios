//
//  EQSViewController.m
//  Basemaps
//
//  Created by Nicholas Furness on 11/29/12.
//  Copyright (c) 2012 ESRI. All rights reserved.
//

#import "AGSNearestBreweryViewController.h"
#import <ArcGIS/ArcGIS.h>
#import <objc/runtime.h>

// Uncomment in your code to specify username and password
// Or add an "AGOLCredentials.h" file which specifies them.
//#define myUsername @""
//#define myPassword @""

// Only import the file if the above constants have not been defined.
#ifndef myUsername
#import "AGOLCredentials.h"
#endif

@interface AGSNearestBreweryViewController () <AGSWebMapDelegate,
													 AGSMapViewTouchDelegate,
													 AGSClosestFacilityTaskDelegate,
													 AGSServiceAreaTaskDelegate,
													 AGSQueryTaskDelegate,
													 AGSMapViewLayerDelegate>
@property (weak, nonatomic) IBOutlet AGSMapView *mapView;
@property (nonatomic, strong) AGSWebMap *webMap;
@property (nonatomic, strong) AGSPictureMarkerSymbol *symbol;

@property (assign) BOOL isLoading;

@property (nonatomic, strong) AGSClosestFacilityTask *closestFacilityTask;
@property (nonatomic, strong) AGSServiceAreaTask *driveTimeTask;
@property (nonatomic, strong) AGSQueryTask *queryTask;

@property (nonatomic, strong) AGSServiceAreaTaskParameters *defaultDriveTimeParams;
@property (nonatomic, strong) AGSGraphic *driveTimeGraphic;

@property (nonatomic, strong) NSURL *featureServiceURL;
@property (nonatomic, strong) AGSGraphicsLayer *resultsLayer;

@property (nonatomic, strong) NSArray *colorRamp;
@property (weak, nonatomic) IBOutlet UIButton *clearResultsButton;
@end

@implementation AGSNearestBreweryViewController
#define kDriveTimeTaskURL @"https://route.arcgis.com/arcgis/rest/services/World/ServiceAreas/NAServer/ServiceArea_World"
#define kClosestFacilityTaskURL @"http://route.arcgis.com/arcgis/rest/services/World/ClosestFacility/NAServer/ClosestFacility_World"
#define kWebMapID @"8c4288bb0da4493aa85947d7a400a952"

#define kDriveTimeInitialRangeInMinutes 30
#define kDriveTimeExpansionTime 30
#define kDriveTimeMaxRange 300

#define kSearchPointKey @"AGSBrewerySearchPoint"
#define kSearchRangeKey @"AGSBrewerySearchRange"

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.webMap = [AGSWebMap webMapWithItemId:kWebMapID credential:nil];
    [self.webMap openIntoMapView:self.mapView];
    self.webMap.delegate = self;
	
	self.mapView.allowRotationByPinching = YES;
	
	self.mapView.callout.accessoryButtonHidden = YES;
}

-(void)webMap:(AGSWebMap *)webMap didLoadLayer:(AGSLayer *)layer
{
	static BOOL foundLayer = NO;
	
    if (!foundLayer &&
		[layer isKindOfClass:[AGSFeatureLayer class]])
    {
        self.featureServiceURL = ((AGSFeatureLayer *)layer).URL;
		foundLayer = YES;

		self.queryTask = [AGSQueryTask queryTaskWithURL:self.featureServiceURL];
		self.queryTask.delegate = self;
	}
}

-(void)didOpenWebMap:(AGSWebMap *)webMap intoMapView:(AGSMapView *)mapView
{
	// Set up a URL and credential for the task
    NSURL *cftURL = [NSURL URLWithString:kClosestFacilityTaskURL];
    AGSCredential *credentials = [[AGSCredential alloc] initWithUser:myUsername password:myPassword];

	// Create the task and listen to callbacks
    self.closestFacilityTask = [AGSClosestFacilityTask closestFacilityTaskWithURL:cftURL credential:credentials];
    self.closestFacilityTask.delegate = self;

	NSURL *dtURL = [NSURL URLWithString:kDriveTimeTaskURL];
	self.driveTimeTask = [AGSServiceAreaTask serviceAreaTaskWithURL:dtURL credential:credentials];
	self.driveTimeTask.delegate = self;
	[self.driveTimeTask retrieveDefaultServiceAreaTaskParameters];

	// Add a graphics layer
    self.resultsLayer = [AGSGraphicsLayer graphicsLayer];
    [self.mapView addMapLayer:self.resultsLayer];

	// Set up a symbol for where I tap
	UIImage *geeknixtaImage = [UIImage imageNamed:@"geeknixta"];
	self.symbol = [AGSPictureMarkerSymbol pictureMarkerSymbolWithImage:geeknixtaImage];

	// Listen for taps
    self.mapView.touchDelegate = self;
}

-(BOOL)mapView:(AGSMapView *)mapView shouldShowCalloutForGraphic:(AGSGraphic *)graphic
{
	return self.clearResultsButton.hidden == NO;
}

-(void)mapView:(AGSMapView *)mapView didClickAtPoint:(CGPoint)screen mapPoint:(AGSPoint *)mappoint graphics:(NSDictionary *)graphics
{
	if (self.clearResultsButton.hidden)
	{
		[self searchAroundMapPoint:mappoint];
	}
}

- (void)searchAroundMapPoint:(AGSPoint *)mappoint
{
    if (self.clearResultsButton.hidden)
	{
		[self.resultsLayer removeAllGraphics];
		
		// Show where I tapped
		AGSGraphic *g = [AGSGraphic graphicWithGeometry:mappoint
												 symbol:self.symbol
											 attributes:nil];
		[self.resultsLayer addGraphic:g];
		
//		[self startAnimation];
		
		// Get a drivetime area first to limit the features we're dealing with.
		[self getConstraintAreaAroundPoint:g withRange:kDriveTimeInitialRangeInMinutes];
	}
}

-(void)getConstraintAreaAroundPoint:(AGSGraphic *)searchGraphic withRange:(int)range
{
	if (self.defaultDriveTimeParams)
	{
		AGSServiceAreaTaskParameters *serviceAreaParams = self.defaultDriveTimeParams;
		
		serviceAreaParams.travelDirection = AGSNATravelDirectionFromFacility;
		
		//specifying the spatial reference output
		serviceAreaParams.outSpatialReference = self.mapView.spatialReference;
		
		//specify the selected facility for the service area task.
		[serviceAreaParams setFacilitiesWithFeatures:[NSArray arrayWithObject:searchGraphic]];

		NSMutableArray *breaks = [NSMutableArray array];
		NSNumber *rangeNum = [NSNumber numberWithInt:range];
		[breaks addObject:rangeNum];
		serviceAreaParams.defaultBreaks = breaks;

		NSOperation *op = [self.driveTimeTask solveServiceAreaWithParameters:serviceAreaParams];
		
		objc_setAssociatedObject(op, kSearchPointKey, searchGraphic, OBJC_ASSOCIATION_RETAIN);
		objc_setAssociatedObject(op, kSearchRangeKey, rangeNum, OBJC_ASSOCIATION_RETAIN);
	}
	else
	{
		[[[UIAlertView alloc] initWithTitle:@"Uh oh"
								   message:@"Could not get Drive Time Parameters. Trying again now…"
								  delegate:nil
						  cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
		[self.driveTimeTask retrieveDefaultServiceAreaTaskParameters];
	}
}

-(void)serviceAreaTask:(AGSServiceAreaTask *)serviceAreaTask operation:(NSOperation *)op didSolveServiceAreaWithResult:(AGSServiceAreaTaskResult *)serviceAreaTaskResult
{
	NSLog(@"Got service area…");
	AGSGraphic *searchGraphic = objc_getAssociatedObject(op, kSearchPointKey);
	NSNumber *searchRange = objc_getAssociatedObject(op, kSearchRangeKey);
	
	if (serviceAreaTaskResult.serviceAreaPolygons.count > 0)
	{
		AGSGraphic *serviceArea = serviceAreaTaskResult.serviceAreaPolygons[0];
		self.driveTimeGraphic = serviceArea;

		AGSQuery *query = [AGSQuery query];
		query.geometry = serviceArea.geometry;
		query.outSpatialReference = self.mapView.spatialReference;
		query.returnGeometry = YES;

		NSOperation *op = [self.queryTask executeWithQuery:query];
		objc_setAssociatedObject(op, kSearchPointKey, searchGraphic, OBJC_ASSOCIATION_RETAIN);
		objc_setAssociatedObject(op, kSearchRangeKey, searchRange, OBJC_ASSOCIATION_RETAIN);
		
		[self.resultsLayer removeAllGraphics];
		serviceArea.symbol = [AGSSimpleFillSymbol simpleFillSymbolWithColor:[[UIColor greenColor] colorWithAlphaComponent:0.5] outlineColor:nil];
		[self.resultsLayer addGraphic:serviceArea];
		[self.resultsLayer addGraphic:searchGraphic];
		[self.mapView zoomToGeometry:serviceArea.geometry withPadding:10 animated:YES];
	}
	else
	{
		[[[UIAlertView alloc] initWithTitle:@"Uh oh"
									message:@"Could not get Drive Time Coverage."
								   delegate:nil
						  cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
	}
}

-(void)queryTask:(AGSQueryTask *)queryTask
	   operation:(NSOperation *)op didExecuteWithFeatureSetResult:(AGSFeatureSet *)featureSet
{
	AGSGraphic *searchGraphic = objc_getAssociatedObject(op, kSearchPointKey);
	NSNumber *searchRange = objc_getAssociatedObject(op, kSearchRangeKey);

	if (featureSet.features.count >= 3)
	{
		if (featureSet.features.count > 100)
		{
			// Pare down the results
			for (AGSGraphic *g in featureSet.features) {
				double distanceFromSearchGraphic = [[AGSGeometryEngine defaultGeometryEngine] distanceFromGeometry:g.geometry toGeometry:searchGraphic.geometry];
				[g setAttributeWithDouble:distanceFromSearchGraphic forKey:@"distanceToMe"];
			}
			
			NSArray *sortedPoints = [featureSet.features sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2)
			{
				BOOL exists;
				double d1 = [(AGSGraphic *)obj1 attributeAsDoubleForKey:@"distanceToMe" exists:&exists];
				double d2 = [(AGSGraphic *)obj2 attributeAsDoubleForKey:@"distanceToMe" exists:&exists];
				return d1==d2?NSOrderedSame:d1<d2?NSOrderedAscending:NSOrderedDescending;
			}];
			
			NSMutableArray *closestPoints = [NSMutableArray array];
			for (int i=0; i < 100; i++)
			{
				[closestPoints addObject:sortedPoints[i]];
			}
			
			featureSet = [AGSFeatureSet featureSetWithFeatures:closestPoints];
		}

		// Get 3 nearest features
		[self findNearest:3 features:featureSet within:self.driveTimeGraphic from:searchGraphic];
	}
	else
	{
		int range = searchRange.intValue;
		if (range < kDriveTimeMaxRange)
		{
			range = range + kDriveTimeExpansionTime;
			if (range > kDriveTimeMaxRange)
			{
				range = kDriveTimeMaxRange;
			}
			[self getConstraintAreaAroundPoint:searchGraphic withRange:range];
		}
		else
		{
			// Time to stop looking
			NSLog(@"Reached max range and haven't found enough breweries. Giving up.");
		}
	}
}

-(void)queryTask:(AGSQueryTask *)queryTask operation:(NSOperation *)op didFailWithError:(NSError *)error
{
	NSLog(@"Couldn't get features: %@", error);
	[self endAnimation];
	self.mapView.layer.borderColor = [UIColor redColor].CGColor;
}

-(void)serviceAreaTask:(AGSServiceAreaTask *)serviceAreaTask operation:(NSOperation *)op didFailSolveWithError:(NSError *)error
{
	NSLog(@"Failed to find service area: %@", error);
	[self endAnimation];
	self.mapView.layer.borderColor = [UIColor redColor].CGColor;
}

-(void)serviceAreaTask:(AGSServiceAreaTask *)serviceAreaTask operation:(NSOperation *)op didRetrieveDefaultServiceAreaTaskParameters:(AGSServiceAreaTaskParameters *)serviceAreaParams
{
	NSLog(@"Got default drive time parameters");
	self.defaultDriveTimeParams = serviceAreaParams;
}

-(void)serviceAreaTask:(AGSServiceAreaTask *)serviceAreaTask operation:(NSOperation *)op didFailToRetrieveDefaultServiceAreaTaskParametersWithError:(NSError *)error
{
	NSLog(@"Failed to get default service area parameters: %@", error);
	[self endAnimation];
	self.mapView.layer.borderColor = [UIColor redColor].CGColor;
}

-(void)findNearest:(NSUInteger)count
		  features:(AGSFeatureSet *)featureSet
			within:(AGSGraphic *)constraintGraphic
			  from:(AGSGraphic *)mapPointGraphic
{
	// INIT PARAMETERS
	AGSClosestFacilityTaskParameters *params = [AGSClosestFacilityTaskParameters closestFacilityTaskParameters];
	params.outSpatialReference = self.mapView.spatialReference;
	
	// START AT MAP TAP
	[params setIncidentsWithFeatures:@[mapPointGraphic]];
	
	// LIMIT FEATURES TO CONSIDER
	AGSQuery *q = [AGSQuery query];
	
	q.geometry = constraintGraphic.geometry.envelope;
	
//	AGSNALayerDefinition *facilities = [[AGSNALayerDefinition alloc] initWithURL:self.featureServiceURL query:q];
	
	// END AT FEATURES IN THE FEATURE LAYER
//	[params setFacilitiesWithLayerDefinition:facilities];
	[params setFacilitiesWithFeatures:featureSet.features];
	
	params.travelDirection = AGSNATravelDirectionToFacility;
	
	params.defaultTargetFacilityCount = count;
	
	NSOperation *op = [self.closestFacilityTask solveClosestFacilityWithParameters:params];
	objc_setAssociatedObject(op, kSearchPointKey, mapPointGraphic, OBJC_ASSOCIATION_RETAIN);
}

- (IBAction)zoomCtrlTapped:(id)sender {
    UISegmentedControl *ctrl = sender;
    if (ctrl.selectedSegmentIndex == 0)
    {
        [self.mapView zoomOut:YES];
    }
    else
    {
        [self.mapView zoomIn:YES];
    }
}

#pragma mark - CFS Callbacks
-(void)closestFacilityTask:(AGSClosestFacilityTask *)closestFacilityTask
				 operation:(NSOperation *)op didSolveClosestFacilityWithResult:(AGSClosestFacilityTaskResult *)closestFacilityTaskResult
{
	NSMutableArray *allGeoms = [NSMutableArray array];
    for (AGSClosestFacilityResult *result in closestFacilityTaskResult.closestFacilityResults)
    {
		UIColor *routeColor = [UIColor colorWithRed:0.31 green:0.73 blue:1 alpha:0.8];
		AGSSimpleLineSymbol *routeSymbol = [AGSSimpleLineSymbol simpleLineSymbolWithColor:routeColor
																					width:4.5];
        // ADD EACH ROUTE
        result.routeGraphic.symbol = routeSymbol;
		[allGeoms addObject:result.routeGraphic.geometry];
        [self.resultsLayer addGraphic:result.routeGraphic];
    }

	AGSGeometry *totalGeom = [[AGSGeometryEngine defaultGeometryEngine] unionGeometries:allGeoms];
	[self.resultsLayer removeGraphic:self.driveTimeGraphic];
	self.driveTimeGraphic = nil;
	AGSMutableEnvelope *e = [totalGeom.envelope mutableCopy];
	[e expandByFactor:1.3];
	[self.mapView zoomToEnvelope:e animated:YES];

	[self endAnimation];

	self.clearResultsButton.alpha = 0;
	self.clearResultsButton.hidden = NO;
	[UIView animateWithDuration:0.3 animations:^{
		self.clearResultsButton.alpha = 1;
	}];
}

- (IBAction)clearResults:(id)sender
{
	[self.resultsLayer removeAllGraphics];
	[UIView animateWithDuration:0.3 animations:^{
		self.mapView.callout.hidden = YES;
		self.clearResultsButton.alpha = 0;
	} completion:^(BOOL finished) {
		self.clearResultsButton.hidden = YES;
	}];
}


-(void)closestFacilityTask:(AGSClosestFacilityTask *)closestFacilityTask
				 operation:(NSOperation *)op
	 didFailSolveWithError:(NSError *)error
{
    NSLog(@"Couldn't find 3 closest features: %@", error.localizedFailureReason);
	[self endAnimation];
	self.mapView.layer.borderColor = [UIColor redColor].CGColor;
}


- (void)viewDidUnload {
	[self setClearResultsButton:nil];
	[super viewDidUnload];
}


#pragma mark - UI Stuff
-(void)viewWillAppear:(BOOL)animated
{
	[self configUI];
}

-(void)configUI
{
	[self.mapView.layer setMasksToBounds:YES];
    self.mapView.layer.cornerRadius = 10;
    self.mapView.layer.borderWidth = 3;
    self.mapView.layer.borderColor = [UIColor orangeColor].CGColor;
}

-(void)startAnimation
{
	self.isLoading = YES;
    self.mapView.layer.borderColor = [UIColor orangeColor].CGColor;
	[self.mapView.layer addAnimation:[self getAnimation]
							  forKey:@"borderColorLoading"];
}

-(void)endAnimation
{
	self.isLoading = NO;
}

-(CAAnimation *)getAnimation
{
	CABasicAnimation *colorAnimation = [CABasicAnimation animationWithKeyPath:@"borderColor"];
	colorAnimation.toValue = (id)[UIColor colorWithRed:0.41
												 green:0.16
												  blue:0.47
												 alpha:1].CGColor;
	CABasicAnimation *cornerAnimation = [CABasicAnimation animationWithKeyPath:@"cornerRadius"];
	cornerAnimation.toValue = (id)[NSNumber numberWithDouble:20];
    
    CABasicAnimation *widthAnimation = [CABasicAnimation animationWithKeyPath:@"borderWidth"];
	widthAnimation.toValue = (id)[NSNumber numberWithDouble:4];
    
	CAAnimationGroup *animation = [CAAnimationGroup animation];
	animation.animations = @[colorAnimation, cornerAnimation, widthAnimation];
	animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
	animation.autoreverses = YES;
	animation.delegate = self;
	animation.removedOnCompletion = YES;
	return animation;
}

-(void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag
{
	if (self.isLoading)
	{
		// We're still loading. Let's repeat the animation.
		[self.mapView.layer addAnimation:[self getAnimation]
								  forKey:@"borderColorLoading"];
	}
}

#pragma mark - iOS 7 config
-(BOOL)prefersStatusBarHidden
{
    return YES;
}

@end