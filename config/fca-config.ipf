// Copyright 2016 University of Basel
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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
Constant ksFixPointNum = 0	// 0: read number of points from header;
									// 1: use constant below (gives error if number in header differs)
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
Constant ksDeflSens_EdgeFraction = 0.02	// Defines end of hardwall part, the closer to 0, the less of curve
													// gets fitted (useful values 0.01 - 0.1)

// Further Analysis flags
Constant ksFixDefl = 0 				// Deflection sensitivity; 0: Fit for each curve; 1: Use fixed from header
Constant ksXDataZSens = 1				// 0: don't use Zsensor data as X axis; 1: use Zsensor data where available;
											// 2: force use of Zsensor data; i.e. abort when not available
Constant ksMaxGoodPt = -1			// (-1: ignore) Manually force the "last good point" to be below this value
											// (e.g. if there are problems with data);


//
// **** END USER CONFIGURABLE CONSTANTS ****
//
