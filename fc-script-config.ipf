#pragma rtGlobals=3		// Use modern global access method and strict wave access.


// **** USER CONFIGURABLE CONSTANTS ****
//
// Change constants to adjust procedure behaviour

// Allowed data file versions, comma separated
// (add versions once they have been tested)
StrConstant ksVersionReq = "0x07300000,0x08100000,0x08150300,0x08150304,0x09000103"

// Points per FC
// only thoroughly tested with 4096, but should work with 2048 etc.
// (too few points may cause bad curve transformations and analysis)
Constant ksFCPoints = 4096

// Force curves per row.
// Tested with 32 and 16 pixels per row
Constant ksFVRowSize = 32

// File types as written in header
StrConstant ksFileTypeFV = "FVOL"
StrConstant ksFileTypeFC = "FOL"

// String to be matched (full match, case insensitive) at header end
StrConstant ksHeaderEnd = "\\*File list end"


// ANALYSIS PARAMETERS:
// Brush height calculation parameters
Constant ksBaselineFitLength = .3		// Fraction of points used for baseline fits
Constant ksBrushCutoff = 45				// height from force in *exponential fit algorithm* (in pN)
Constant ksBrushOverNoise = 2			// height from point on curve above noise multiplied by this factor, in *noise algorithm*

// Deflection sensitivity calculation parameters
Constant ksDeflSens_ContactLen = 25				// ca. contact length (piezo ramp length, in nm)
//Constant ksDeflSens_SmoothCurveLen = 25		// Smoothing range for initial curve smoothing (in nm)  [old param, not used anymore]
//Constant ksDeflSens_SmoothDerivLen = 12  	// Smoothing range for derivative smoothing (in nm)  [old param, not used anymore]
Constant ksDeflSens_EdgeFraction = 0.02	// Defines end of hardwall part, the closer to 0, the less of curve
													// gets fitted (useful values 0.01 - 0.1)

// Further Analysis parameters
Constant ksFixDefl = 1 				// Deflection sensitivity; 0: Fit for each curve; 1: Use fixed from header
Constant ksXDataZSens = 2				// 0: don't use Zsensor data as X axis; 1: use Zsensor data where available;
											// 2: force use of Zsensor data; i.e. abort when not available
Constant ksMaxGoodPt = -1			// (-1: ignore) Manually force the "last good point" to be below this value
											// (e.g. if there are problems with data);


//
// **** END USER CONFIGURABLE CONSTANTS ****
//
