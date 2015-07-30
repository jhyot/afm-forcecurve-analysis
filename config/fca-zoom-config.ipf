#pragma rtGlobals=3		// Use modern global access method.


// Edit the values in the "ZOOM VALUES BLOCK" below to
// customize zoom levels.

// Many graphs in this software package provide 4 fixed zoom levels
// to cycle through (in addition to the standard Igor graph editing and
// zooming tools).

// The zoom levels are defined separately for a "tip-sample-distance"
// and a "Z piezo position" graph type. The zoom levels are designated
// 0 through 3, with usually 3 being the highest zoom.


// Function returns wave with 4 rows in this order:
// y-min; y-max; x-min; x-max
Function/WAVE GetZoom(xtype, level)
	Variable xtype, level
	
	
	Make/FREE/N=(3, 5, 4) zoom = NaN

	
	// ========
	// ZOOM VALUES BLOCK

	// Set zoom levels in a 3D wave:
	// 1D: xtype;  2D: zoom level;  3D: y-min, y-max, x-min, x-max
	// NaN = autoscale (check only "min" value)
	
	
	//          left     ;    bottom
	// TSD, lvl0
	zoom[1][0][0] = NaN; zoom[1][0][2] = NaN
	zoom[1][0][1] = NaN; zoom[1][0][3] = NaN
	// TSD, lvl1
	zoom[1][1][0] = NaN; zoom[1][1][2] = -5
	zoom[1][1][1] = NaN; zoom[1][1][3] = 80
	// TSD, lvl2
	zoom[1][2][0] = -5000; zoom[1][2][2] = -5
	zoom[1][2][1] = 250; zoom[1][2][3] = 60
	// TSD, lvl3
	zoom[1][3][0] = -35; zoom[1][3][2] = -5
	zoom[1][3][1] = 150; zoom[1][3][3] = 75
	// Xsection plot zoom
	zoom[1][4][0] = -200; zoom[1][4][2] = -5
	zoom[1][4][1] = 250; zoom[1][4][3] = 120
	
	//          left     ;    bottom
	// Zp, lvl0
	zoom[2][0][0] = NaN; zoom[2][0][2] = NaN
	zoom[2][0][1] = NaN; zoom[2][0][3] = NaN
	// Zp, lvl1
	zoom[2][1][0] = NaN; zoom[2][1][2] = -5
	zoom[2][1][1] = NaN; zoom[2][1][3] = 350
	// Zp, lvl2
	zoom[2][2][0] = -40; zoom[2][2][2] = 20
	zoom[2][2][1] = 300; zoom[2][2][3] = 120
	// Zp, lvl3
	zoom[2][3][0] = -20; zoom[2][3][2] = 30
	zoom[2][3][1] = 150; zoom[2][3][3] = 100

	// ========
	// END ZOOM VALUES BLOCK
	
	
	Make/FREE/N=4 zoomret
	zoomret = zoom[xtype][level][p]
	
	return zoomret
End



