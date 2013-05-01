//
//  EQSViewController.m
//  Basemaps
//
//  Created by Nicholas Furness on 11/29/12.
//  Copyright (c) 2012 ESRI. All rights reserved.
//

#import "AGSCommonPatternsSampleViewController.h"
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

@interface AGSCommonPatternsSampleViewController () <AGSWebMapDelegate,
													 AGSMapViewTouchDelegate,
													 AGSMapViewCalloutDelegate,
													 AGSClosestFacilityTaskDelegate,
													 AGSServiceAreaTaskDelegate,
													 AGSMapViewLayerDelegate>
@property (weak, nonatomic) IBOutlet AGSMapView *mapView;
@property (nonatomic, strong) AGSWebMap *webMap;
@property (nonatomic, strong) AGSPictureMarkerSymbol *symbol;

@property (assign) BOOL isLoading;

@property (nonatomic, strong) AGSClosestFacilityTask *closestFacilityTask;
@property (nonatomic, strong) AGSServiceAreaTask *driveTimeTask;
@property (nonatomic, strong) AGSServiceAreaTaskParameters *defaultDriveTimeParams;
@property (nonatomic, strong) AGSGraphic *driveTimeGraphic;

@property (nonatomic, strong) NSURL *featureServiceURL;
@property (nonatomic, strong) AGSGraphicsLayer *resultsLayer;

@property (nonatomic, strong) NSArray *colorRamp;
@property (weak, nonatomic) IBOutlet UIButton *clearResultsButton;
@end

@implementation AGSCommonPatternsSampleViewController
#define kDriveTimeTaskURL @"https://route.arcgis.com/arcgis/rest/services/World/ServiceAreas/NAServer/ServiceArea_World"
#define kClosestFacilityTaskURL @"http://route.arcgis.com/arcgis/rest/services/World/ClosestFacility/NAServer/ClosestFacility_World"
#define kWebMapID @"8c4288bb0da4493aa85947d7a400a952"

#define kDriveTimeLimitInMinutes 70

#define kSearchPointKey @"AGSBrewerySearchPoint"

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
	self.mapView.calloutDelegate = self;
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
											 attributes:nil
								   infoTemplateDelegate:nil];
		[self.resultsLayer addGraphic:g];
		
		// Get a drivetime area first to limit the features we're dealing with.
		[self getConstraintAreaAroundPoint:g];
	}
}

-(void)getConstraintAreaAroundPoint:(AGSGraphic *)searchGraphic
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
		[breaks addObject:[NSNumber numberWithInt:kDriveTimeLimitInMinutes]];
		serviceAreaParams.defaultBreaks = breaks;

		NSOperation *op = [self.driveTimeTask solveServiceAreaWithParameters:serviceAreaParams];
		
		[self startAnimation];

		objc_setAssociatedObject(op, kSearchPointKey, searchGraphic, OBJC_ASSOCIATION_RETAIN);
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

-(void)serviceAreaTask:(AGSServiceAreaTask *)serviceAreaTask operation:(NSOperation *)op didRetrieveDefaultServiceAreaTaskParameters:(AGSServiceAreaTaskParameters *)serviceAreaParams
{
	NSLog(@"Got default drive time parameters");
	self.defaultDriveTimeParams = serviceAreaParams;
}

-(void)serviceAreaTask:(AGSServiceAreaTask *)serviceAreaTask operation:(NSOperation *)op didFailToRetrieveDefaultServiceAreaTaskParametersWithError:(NSError *)error
{
	NSLog(@"Failed to get default service area parameters: %@", error);
}

-(void)serviceAreaTask:(AGSServiceAreaTask *)serviceAreaTask operation:(NSOperation *)op didSolveServiceAreaWithResult:(AGSServiceAreaTaskResult *)serviceAreaTaskResult
{
	NSLog(@"Got service area…");
	AGSGraphic *searchGraphic = objc_getAssociatedObject(op, kSearchPointKey);
	
	[self.resultsLayer removeAllGraphics];
	
	if (serviceAreaTaskResult.serviceAreaPolygons.count > 0)
	{
		AGSGraphic *serviceArea = serviceAreaTaskResult.serviceAreaPolygons[0];
		self.driveTimeGraphic = serviceArea;
		// Get 3 nearest features
		[self findNearest:3 itemsToMapPointGraphic:searchGraphic within:serviceArea];

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

-(void)serviceAreaTask:(AGSServiceAreaTask *)serviceAreaTask operation:(NSOperation *)op didFailSolveWithError:(NSError *)error
{
	NSLog(@"Failed to find service area: %@", error);
}

-(void)findNearest:(NSUInteger)count itemsToMapPointGraphic:(AGSGraphic *)mapPointGraphic
			within:(AGSGraphic *)constraintGraphic
{
	// INIT PARAMETERS
	AGSClosestFacilityTaskParameters *params = [AGSClosestFacilityTaskParameters closestFacilityTaskParameters];
	params.outSpatialReference = self.mapView.spatialReference;
	
	// START AT MAP TAP
	[params setIncidentsWithFeatures:@[mapPointGraphic]];
	
	// LIMIT FEATURES TO CONSIDER
	AGSQuery *q = [AGSQuery query];
	
	q.geometry = constraintGraphic.geometry.envelope;
	
	AGSNALayerDefinition *facilities = [[AGSNALayerDefinition alloc] initWithURL:self.featureServiceURL query:q];
	
	// END AT FEATURES IN THE FEATURE LAYER
	[params setFacilitiesWithLayerDefinition:facilities];
	
	params.travelDirection = AGSNATravelDirectionToFacility;
	
	params.defaultTargetFacilityCount = count;
	
	NSOperation *op = [self.closestFacilityTask solveClosestFacilityWithParameters:params];
	objc_setAssociatedObject(op, kSearchPointKey, mapPointGraphic, OBJC_ASSOCIATION_RETAIN);
}

#pragma mark - CFS Callbacks
-(void)closestFacilityTask:(AGSClosestFacilityTask *)closestFacilityTask
				 operation:(NSOperation *)op didSolveClosestFacilityWithResult:(AGSClosestFacilityTaskResult *)closestFacilityTaskResult
{
	[self endAnimation];

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
	[self endAnimation];
    NSLog(@"Couldn't find 3 closest features: %@", error.localizedFailureReason);
	self.mapView.layer.borderColor = [UIColor redColor].CGColor;
}


#pragma mark - UI Stuff
-(void)viewWillAppear:(BOOL)animated
{
	[self configUI];
}

-(void)configUI
{
	[self.mapView.layer setMasksToBounds:YES];
    self.mapView.layer.cornerRadius = 20;
    self.mapView.layer.borderWidth = 7.5;
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
	cornerAnimation.toValue = (id)[NSNumber numberWithDouble:50];

	CAAnimationGroup *animation = [CAAnimationGroup animation];
	animation.animations = @[colorAnimation, cornerAnimation];
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

- (void)viewDidUnload {
	[self setClearResultsButton:nil];
	[super viewDidUnload];
}
@end