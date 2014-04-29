nearest-brewery-ios
===================

Runtime SDK for iOS demo showing ServiceArea and ClosestFacility Tasks.

###Instructions
To run the iOS Application, you will need an ArcGIS Online account (you can [create a free developer account here](https://developers.arcgis.com/en/sign-up/)).

The iOS application makes use of paid services (specifically, the Closest Facility Task at [http://route.arcgis.com](http://route.arcgis.com)).

Add a file to the iOS project's Source folder named `AGOLCredentials.h` containing your username and password. Be careful not to check this file in to a public repo!!

The `AGOLCredentials.h` file should look like this:
```Objective-C
#define myUsername @"<your ArcGIS Online username>"
#define myPassword @"<your ArcGIS Online password>"
```