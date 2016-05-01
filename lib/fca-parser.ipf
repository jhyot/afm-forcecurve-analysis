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

#pragma rtGlobals=3		// Use modern global access method.
//#pragma IndependentModule=ForceMapAnalysis  // disabled for easier debugging etc


// Extracts section titles (e.g. "\*Ciao scan list") from the header
// and saves them into new text wave (titleswave).
// Also creates wave W_Index with the positions of the section titles within full header
//
// Returns 0 if success, < 0 if error.
Function GetHeaderSectionTitles(headerwave, titleswave)
	String headerwave		// Name of the text wave with the header lines (must exist and be populated)
	String titleswave		// Name of the text wave where the section titles will be written to (will be overwritten)
	
	Make/T/O/N=0 $titleswave = ""

	WAVE/T fullHeader = $headerwave
	WAVE/T subGroupTitles = $titleswave
	
	// Find indices of header subgroups (e.g. "\*Ciao scan list")
	// in fullHeader (created by ReadFCHeaderLines)
	Grep/INDX/E="^\\\\\\*.+$" fullHeader as subGroupTitles
	if (V_flag != 0)
		return -1			// Error
	endif
	
	WAVE W_Index
	Redimension/N=(numpnts(subGroupTitles), 2) subGroupTitles
	subGroupTitles[][1] = num2str(W_Index[p])
	
	return 0	
End


Function/S Header_GetVersion(fullheader, subGroupTitles)
	WAVE/T fullheader, subGroupTitles
	
	FindValue/TEXT="\\*Force file list"/TXOP=4 subGroupTitles
	if (V_value < 0)
		return ""
	endif
	Variable subGroup = V_value
	Variable subGroupOffset = str2num(subGroupTitles[subGroup][1])
	
	FindValue/S=(subGroupOffset)/TEXT="\\Version:" fullheader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return ""
	endif
	String s
	SplitString/E=":\\s(.+)$" fullHeader[V_value], s
	
	return s
End


Function/S Header_GetFiletype(fullheader, subGroupTitles)
	WAVE/T fullheader, subGroupTitles
	
	FindValue/TEXT="\\*Force file list"/TXOP=4 subGroupTitles
	if (V_value < 0)
		return ""
	endif
	Variable subGroup = V_value
	Variable subGroupOffset = str2num(subGroupTitles[subGroup][1])
	
	FindValue/S=(subGroupOffset)/TEXT="\\Start context:" fullHeader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return ""
	endif
	String s
	SplitString/E=":\\s(.+)$" fullHeader[V_value], s

	return s
End


Function Header_GetNumPoints(fullheader, subGroupTitles)
	WAVE/T fullheader, subGroupTitles
	
	FindValue/TEXT="\\*Ciao force image list"/TXOP=4 subGroupTitles
	if (V_value < 0)
		return -1
	endif
	Variable subGroup = V_value
	Variable subGroupOffset = str2num(subGroupTitles[subGroup][1])
	
	FindValue/S=(subGroupOffset)/TEXT="\\Samps/line:" fullHeader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return -1
	endif
	String s
	SplitString/E=":\\s(\\d+)\\s\\d+$" fullHeader[V_value], s

	return str2num(s)
End


Function Header_GetXPos(fullheader, subGroupTitles)
	WAVE/T fullheader, subGroupTitles
	
	FindValue/TEXT="\\*Ciao scan list"/TXOP=4 subGroupTitles
	if (V_value < 0)
		return NaN
	endif
	Variable subGroup = V_value
	Variable subGroupOffset = str2num(subGroupTitles[subGroup][1])
	
	FindValue/S=(subGroupOffset)/TEXT="\\X Offset:" fullHeader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return NaN
	endif
	String s
	SplitString/E=":\\s((-|\\+)?\\d+\\.?\\d*)\\s+nm$" fullHeader[V_value], s

	return str2num(s)
End


Function Header_GetScanSize(fullheader, subGroupTitles)
	WAVE/T fullheader, subGroupTitles
	
	FindValue/TEXT="\\*Ciao scan list"/TXOP=4 subGroupTitles
	if (V_value < 0)
		return NaN
	endif
	Variable subGroup = V_value
	Variable subGroupOffset = str2num(subGroupTitles[subGroup][1])
	
	FindValue/S=(subGroupOffset)/TEXT="\\Scan Size:" fullHeader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return NaN
	endif
	String s
	SplitString/E=":\\s+(.+)\\s+nm$" fullHeader[V_value], s

	return str2num(s)
End


Function Header_GetYPos(fullheader, subGroupTitles)
	WAVE/T fullheader, subGroupTitles
	
	FindValue/TEXT="\\*Ciao scan list"/TXOP=4 subGroupTitles
	if (V_value < 0)
		return NaN
	endif
	Variable subGroup = V_value
	Variable subGroupOffset = str2num(subGroupTitles[subGroup][1])
	
	FindValue/S=(subGroupOffset)/TEXT="\\Y Offset:" fullHeader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return NaN
	endif
	String s
	SplitString/E=":\\s((-|\\+)?\\d+\\.?\\d*)\\s+nm$" fullHeader[V_value], s

	return str2num(s)
End


// Returns the data set number where the given data type is found
// (-1 if no match)
Function Header_FindDataType(fullheader, subGroupTitles, type)
	WAVE/T fullheader, subGroupTitles
	String type
	
	Variable start = -1
	Variable groupOffs = -1
	Variable i = -1
	Variable found = 0
	String s = ""
	
	Do
		FindValue/S=(start+1)/TEXT="\\*Ciao force image list"/TXOP=4 subGroupTitles
		if (V_value < 0)
			break
		endif
		
		i += 1
		start = V_value
		groupOffs = str2num(subGroupTitles[start][1])
			
		FindValue/S=(groupOffs)/TEXT="\\@4:Image Data:" fullHeader
		if ((V_value < 0) || ((start < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[start+1][1]))))
			return -1
		endif

		SplitString/E=":.*\\[(.+)\\]" fullHeader[V_value], s
		
		if (cmpstr(s, type) == 0)
			found = 1
			break
		endif
	While (1)
	
	if (found)
		return i
	else
		return -1
	endif
End


Function Header_GetDataOffset(fullheader, subGroupTitles, index)
	WAVE/T fullheader, subGroupTitles
	Variable index		// index'th data set in file (0-based)
	
	Variable start = -1
	Variable i = -1
	
	Do
		FindValue/S=(start+1)/TEXT="\\*Ciao force image list"/TXOP=4 subGroupTitles
		if (V_value < 0)
			break
		endif
		
		i += 1
		start = V_value
	While (i < index)
	
	// Didn't find enough subgroups to get to the index'th one
	if (i != index)
		return -1
	endif
	
	Variable subGroup = V_value
	Variable subGroupOffset = str2num(subGroupTitles[subGroup][1])
		
	FindValue/S=(subGroupOffset)/TEXT="\\Data offset:" fullHeader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return -1
	endif
	String s
	SplitString/E=":\\s(.+)$" fullHeader[V_value], s

	return str2num(s)
End


// Returns ramp size in nm
Function Header_GetRampSize(fullheader, subGroupTitles, index)
	WAVE/T fullheader, subGroupTitles
	Variable index		// index'th data set in file (0-based)
	
	Variable start = -1
	Variable i = -1
	
	Do
		FindValue/S=(start+1)/TEXT="\\*Ciao force image list"/TXOP=4 subGroupTitles
		if (V_value < 0)
			break
		endif
		
		i += 1
		start = V_value
	While (i < index)
	
	// Didn't find enough subgroups to get to the index'th one
	if (i != index)
		return -1
	endif
	
	Variable subGroup = V_value
	Variable subGroupOffset = str2num(subGroupTitles[subGroup][1])
		
	FindValue/S=(subGroupOffset)/TEXT="\\@4:Ramp size:" fullHeader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return -1
	endif
	String s
	SplitString/E="\\)\\s(.+)\\sV$" fullHeader[V_value], s
	Variable rampSizeV = str2num(s)	
	
	// Z piezo sensitivity
	FindValue/TEXT="\\*Scanner list"/TXOP=4 subGroupTitles
	if (V_value < 0)
		return -1
	endif
	subGroup = V_value
	subGroupOffset = str2num(subGroupTitles[subGroup][1])
	
	FindValue/S=(subGroupOffset)/TEXT="\\@Sens. Zsens:" fullHeader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return -1
	endif
	SplitString/E=":\\sV\\s(.+)\\snm/V$" fullHeader[V_value], s

	return rampSizeV * str2num(s)
End


Function Header_GetSpringConst(fullheader, subGroupTitles, index)
	WAVE/T fullheader, subGroupTitles
	Variable index		// index'th data set in file (0-based)
	
	Variable start = -1
	Variable i = -1
	
	Do
		FindValue/S=(start+1)/TEXT="\\*Ciao force image list"/TXOP=4 subGroupTitles
		if (V_value < 0)
			break
		endif
		
		i += 1
		start = V_value
	While (i < index)
	
	// Didn't find enough subgroups to get to the index'th one
	if (i != index)
		return -1
	endif
	
	Variable subGroup = V_value
	Variable subGroupOffset = str2num(subGroupTitles[subGroup][1])
		
	FindValue/S=(subGroupOffset)/TEXT="\\Spring Constant:" fullHeader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return -1
	endif
	String s
	SplitString/E=":\\s(.+)$" fullHeader[V_value], s

	return str2num(s)
End


Function Header_GetLSBScale(fullheader, subGroupTitles, index)
	WAVE/T fullheader, subGroupTitles
	Variable index		// index'th data set in file (0-based)
	
	Variable start = -1
	Variable i = -1
	
	Do
		FindValue/S=(start+1)/TEXT="\\*Ciao force image list"/TXOP=4 subGroupTitles
		if (V_value < 0)
			break
		endif
		
		i += 1
		start = V_value
	While (i < index)
	
	// Didn't find enough subgroups to get to the index'th one
	if (i != index)
		return -1
	endif
	
	Variable subGroup = V_value
	Variable subGroupOffset = str2num(subGroupTitles[subGroup][1])
		
	FindValue/S=(subGroupOffset)/TEXT="\\@4:Z scale: V" fullHeader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return -1
	endif
	String s
	SplitString/E="\\]\\s\\((.+)\\sV/LSB\\)" fullHeader[V_value], s

	return str2num(s)
End


Function Header_GetSens(fullheader, subGroupTitles, type)
	WAVE/T fullheader, subGroupTitles
	String type
	
	FindValue/TEXT="\\*Ciao scan list"/TXOP=4 subGroupTitles
	if (V_value < 0)
		return -1
	endif
	Variable subGroup = V_value
	Variable subGroupOffset = str2num(subGroupTitles[subGroup][1])
	
	String searchtext = "\\@Sens. " + type + ":"
	
	FindValue/S=(subGroupOffset)/TEXT=(searchtext) fullHeader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return -1
	endif
	String s
	SplitString/E=":\\sV\\s(.+)\\snm/V$" fullHeader[V_value], s

	return str2num(s)
End


Function ParseFCHeader(filename, headerwave, titleswave, headerData)
	String fileName			// Full Igor-style path to file ("folder:to:file.ext")
	String headerwave		// Name of the text wave where full header will be saved to (will be overwritten)
	String titleswave		// Name of the text wave where the section titles will be written to (will be overwritten)
	String &headerData		// Pass-by-ref string will be filled with header data
	
	Variable result, subGroupOffset
	headerData = ""
	
	result = ReadHeaderLines(fileName, headerwave)
	if (result != 0)
		Print fileName + ": Did not find header end"
		return -1
	endif
	
	result = GetHeaderSectionTitles(headerwave, titleswave)
	if (result != 0)
		print fileName + ": Could not extract sections from header"
		return -1
	endif
	
	WAVE/T fullHeader = $headerwave
	WAVE/T subGroupTitles = $titleswave
	WAVE W_Index
	
	String s = ""
	
	
	// ============================
	// Extract relevant header data
	// ============================
	
	String version = Header_GetVersion(fullheader, subGroupTitles)
	
	if (cmpstr(version, "") == 0)
		Print filename + ": Version info not found"
		return -1
	endif
	if (WhichListItem(version, ksVersionReq, ",") < 0)
		Print filename + ": File version not supported"
		return -1
	endif
		
	String filetype = Header_GetFiletype(fullheader, subGroupTitles)
	if (cmpstr(filetype, ksFileTypeFC) != 0)
		Print filename + ": Wrong file type"
		return -1
	endif
	
	Variable fcpoints = Header_GetNumPoints(fullheader, subGroupTitles)
	if (fcpoints <= 0)
		Print filename + ": Couldn't get number of data points per curve"
		return -1
	endif
	headerData = ReplaceNumberByKey("FCNumPoints", headerData, fcpoints)
	
	// returns NaN if didn't find x/y pos
	Variable xpos = Header_GetXPos(fullheader, subGroupTitles)
	Variable ypos = Header_GetYPos(fullheader, subGroupTitles)
	if (numtype(xpos) == 2 || numtype(ypos) == 2)
		Print filename + ": Didn't find X or Y position"
		return -1
	endif
	headerData += "xpos:" + num2str(xpos) + ";ypos:" + num2str(ypos) + ";"
		
	
	// Deflection Error data
	Variable index = Header_FindDataType(fullheader, subGroupTitles, "DeflectionError")
	if (index < 0)
		Print filename + ": Didn't find Deflection Error data"
		return -1
	endif
	
	Variable offs = Header_GetDataOffset(fullheader, subGroupTitles, index)
	if (offs <= 0)
		Print filename + ": Deflection Error: Data offset invalid"
		return -1
	endif
	headerData += "dataOffset:" + num2str(offs) + ";"
	
	Variable rampSize = Header_GetRampSize(fullheader, subGroupTitles, index)
	if (rampSize <= 0)
		Print filename + ": Deflection Error: Ramp Size invalid"
		return -1
	endif
	headerData += "rampSize:" + num2str(rampSize) + ";"
	
	Variable springConst = Header_GetSpringConst(fullheader, subGroupTitles, index)
	if (springConst <= 0)
		Print filename + ": Deflection Error: Spring Constant invalid"
		return -1
	endif
	headerData += "springConst:" + num2str(springConst) + ";"
	
	Variable VPerLSB = Header_GetLSBScale(fullheader, subGroupTitles, index)
	if (springConst <= 0)
		Print filename + ": Deflection Error: V/LSB scale invalid"
		return -1
	endif
	headerData += "VPerLSB:" + num2str(VPerLSB) + ";"
	
	Variable sens = Header_GetSens(fullheader, subGroupTitles, "DeflSens")
	if (sens <= 0)
		Print filename + ": Deflection Error: Deflection sensitivity invalid"
		return -1
	endif
	headerData += "deflSens:" + num2str(sens) + ";"
	
	
	NVAR loadzsens = :internalvars:loadZSens	
	if (loadzsens)
		// Z sensor channel
		index = Header_FindDataType(fullheader, subGroupTitles, "ZSensor")
		if (index < 0)
			Print filename + ": Didn't find ZSensor data"
			return -1
		endif
		
		offs = Header_GetDataOffset(fullheader, subGroupTitles, index)
		if (offs <= 0)
			Print filename + ": ZSensor: Data offset invalid"
			return -1
		endif
		headerData += "ZdataOffset:" + num2str(offs) + ";"
		
		VPerLSB = Header_GetLSBScale(fullheader, subGroupTitles, index)
		if (springConst <= 0)
			Print filename + ": ZSensor: V/LSB scale invalid"
			return -1
		endif
		headerData += "ZVPerLSB:" + num2str(VPerLSB) + ";"
		
		sens = Header_GetSens(fullheader, subGroupTitles, "ZsensSens")
		if (sens <= 0)
			Print filename + ": ZSensor: Deflection sensitivity invalid"
			return -1
		endif
		headerData += "ZSens:" + num2str(sens) + ";"
	endif
	
	
	NVAR loadfric = :internalvars:loadFriction	
	if (loadfric)
		// Friction channel
		index = Header_FindDataType(fullheader, subGroupTitles, "Lateral")
		if (index < 0)
			Print filename + ": Didn't find Friction data"
			return -1
		endif
		
		offs = Header_GetDataOffset(fullheader, subGroupTitles, index)
		if (offs <= 0)
			Print filename + ": Friction: Data offset invalid"
			return -1
		endif
		headerData += "FricDataOffset:" + num2str(offs) + ";"
		
		VPerLSB = Header_GetLSBScale(fullheader, subGroupTitles, index)
		if (springConst <= 0)
			Print filename + ": Friction: V/LSB scale invalid"
			return -1
		endif
		headerData += "FricVPerLSB:" + num2str(VPerLSB) + ";"
		
		// don't read friction sensitivity, because usually is not calibrated
	endif
	
		
	return 0
End


// Read and parse FC file given by fileName
// Write relevant info about FC into String headerData (pass by ref)
// Return 0 if no errors, -1 otherwise
//
// headerData is in "key1:value1;key2:value2;" format
// keys:
// dataOffset		Byte offset to binary data start
// rampSize			Z piezo ramp size in nm
// VPerLSB			Vertical deflection V/LSB
// deflSens			Deflection sensitivity nm/V
// springConst		Spring constant nN/nm
Function ParseFVHeader(fileName, headerwave, titleswave, headerData)
	String fileName			// Full Igor-style path to file ("folder:to:file.ext")
	String headerwave		// Name of the text wave where full header will be saved to (will be overwritten)
	String titleswave		// Name of the text wave where the section titles will be written to (will be overwritten)
	String &headerData		// Pass-by-ref string will be filled with header data
	
	Variable result, subGroupOffset
	headerData = ""
	
	result = ReadHeaderLines(fileName, headerwave)
	if (result != 0)
		Print fileName + ": Did not find header end"
		return -1
	endif
	
	result = GetHeaderSectionTitles(headerwave, titleswave)
	if (result != 0)
		print fileName + ": Could not extract sections from header"
		return -1
	endif
	
	WAVE/T fullHeader = $headerwave
	WAVE/T subGroupTitles = $titleswave
	WAVE W_Index
	
	// ============================
	// Extract relevant header data
	// ============================
	
	String version = Header_GetVersion(fullheader, subGroupTitles)
	
	if (cmpstr(version, "") == 0)
		Print filename + ": Version info not found"
		return -1
	endif
	if (WhichListItem(version, ksVersionReq, ",") < 0)
		Print filename + ": File version not supported"
		return -1
	endif
	
	String filetype = Header_GetFiletype(fullheader, subGroupTitles)
	if (cmpstr(filetype, ksFileTypeFV) != 0)
		Print filename + ": Wrong file type"
		return -1
	endif
	
	Variable fcpoints = Header_GetNumPoints(fullheader, subGroupTitles)
	if (fcpoints <= 0)
		Print filename + ": Couldn't read number of data points per curve"
		return -1
	endif
	headerData = ReplaceNumberByKey("FCNumPoints", headerData, fcpoints)
	
	// Deflection Error channel
	Variable index = Header_FindDataType(fullheader, subGroupTitles, "DeflectionError")
	if (index < 0)
		Print filename + ": Didn't find Deflection Error data"
		return -1
	endif
	
	Variable offs = Header_GetDataOffset(fullheader, subGroupTitles, index)
	if (offs <= 0)
		Print filename + ": Deflection Error: Data offset invalid"
		return -1
	endif
	headerData += "dataOffset:" + num2str(offs) + ";"
	
	Variable rampSize = Header_GetRampSize(fullheader, subGroupTitles, index)
	if (rampSize <= 0)
		Print filename + ": Deflection Error: Ramp size invalid"
		return -1
	endif
	headerData += "rampSize:" + num2str(rampSize) + ";"
	
	Variable springConst = Header_GetSpringConst(fullheader, subGroupTitles, index)
	if (springConst <= 0)
		Print filename + ": Deflection Error: Spring constant invalid"
		return -1
	endif
	headerData += "springConst:" + num2str(springConst) + ";"
	
	Variable VPerLSB = Header_GetLSBScale(fullheader, subGroupTitles, index)
	if (springConst <= 0)
		Print filename + ": Deflection Error: V/LSB scale invalid"
		return -1
	endif
	headerData += "VPerLSB:" + num2str(VPerLSB) + ";"
	
	Variable sens = Header_GetSens(fullheader, subGroupTitles, "DeflSens")
	if (sens <= 0)
		Print filename + ": Deflection Error: Deflection sensitivity invalid"
		return -1
	endif
	headerData += "deflSens:" + num2str(sens) + ";"
	
	return 0
End


// Parses image header and stores values in headerData string (pass by ref)
// headerData content:
// offset1,length1,bytes1,scale1;offset2,length2,bytes2,scale2;...
// offset: start of image in bytes
// length: length of image data in bytes
// bytes: bytes per pixel
// scale: nm/LSB (least significant bit), height scale of image
//
// If one image could not be parsed, headerData will just have "-" in it's place
//
// Returns number of successfully parsed images within the file
Function ParseImageHeader(fileName, headerwave, titleswave, headerData)
	String fileName			// Full Igor-style path to file ("folder:to:file.ext")
	String headerwave		// Name of the text wave where full header will be saved to (will be overwritten)
	String titleswave		// Name of the text wave where the section titles will be written to (will be overwritten)
	String &headerData		// Pass-by-ref string will be filled with header data
	
	Variable result
	headerData = ""

	Variable success = 0
	
	result = ReadHeaderLines(fileName, headerwave)
	if (result != 0)
		Print fileName + ": Did not find header end"
		return success
	endif
	
	result = GetHeaderSectionTitles(headerwave, titleswave)
	if (result != 0)
		print fileName + ": Could not extract sections from header"
		return success
	endif
	
	WAVE/T fullHeader = $headerwave
	WAVE/T subGroupTitles = $titleswave
	WAVE W_Index
	
	Variable subGroupOffset
	String s
	
	// Get Z piezo sensitivity (only 1 value per file)
	FindValue/TEXT="\\*Scanner list"/TXOP=4 subGroupTitles
	if (V_value < 0)
		Print filename + ": \\*Scanner list not found"
		return success
	endif
	subGroupOffset = W_Index[V_value]
	
	FindValue/S=(subGroupOffset)/TEXT="\\@Sens. Zsens:" fullHeader
	if (V_value < 0)
		Print filename + ": Z piezo sens. not found"
		return success
	endif
	SplitString/E=":\\sV\\s(.+)\\snm/V$" fullHeader[V_value], s
	if (strlen(s) == 0)
		Print filename + ": Z piezo sens. invalid"
		return success
	endif
	
	Variable zsens = str2num(s)

	Variable start = 0
	Variable num = 0

	String currentHeader
	Variable bpp
	
	// Loop over image sections in file
	do
		if (start >= numpnts(subGroupTitles))
			// Reached end of header
			break
		endif
		
		// Find image section
		FindValue/S=(start)/TEXT="\\*Ciao image list"/TXOP=4 subGroupTitles
		if (V_value < 0)
			// No more images in this file
			break
		endif
	
		start = V_value + 1
		subGroupOffset = W_Index[V_value]
		
		// Get data offset
		FindValue/S=(subGroupOffset)/TEXT="\\Data offset:" fullHeader
		if ((V_value < 0) || ((start < numpnts(W_Index)) && (V_value >= W_Index[start])))
			Print filename + ": Data offset not found for image " + num2str(num)
			headerData += "-;"
			continue
		endif
		SplitString/E=":\\s(.+)$" fullHeader[V_value], s
		if (str2num(s) <= 0)
			Print filename + ": Data offset <= 0 for image " + num2str(num)
			headerData += "-;"
			continue
		endif
		currentHeader = s + ","
		
		
		// Get data length
		FindValue/S=(subGroupOffset)/TEXT="\\Data length:" fullHeader
		if ((V_value < 0) || ((start < numpnts(W_Index)) && (V_value >= W_Index[start])))
			Print filename + ": Data length not found for image " + num2str(num)
			headerData += "-;"
			continue
		endif
		SplitString/E=":\\s(.+)$" fullHeader[V_value], s
		if (str2num(s) <= 0)
			Print filename + ": Data length <= 0 for image " + num2str(num)
			headerData += "-;"
			continue
		endif
		currentHeader += s + ","
		
		
		// Get bytes per pixel
		FindValue/S=(subGroupOffset)/TEXT="\\Bytes/pixel:" fullHeader
		if ((V_value < 0) || ((start < numpnts(W_Index)) && (V_value >= W_Index[start])))
			Print filename + ": Bytes/pixel not found for image " + num2str(num)
			headerData += "-;"
			continue
		endif
		SplitString/E=":\\s(.+)$" fullHeader[V_value], s
		if (str2num(s) <= 0)
			Print filename + ": Bytes/pixel <= 0 for image " + num2str(num)
			headerData += "-;"
			continue
		endif
		bpp = str2num(s)
		currentHeader += s + ","
		
		
		// Get height scale
		FindValue/S=(subGroupOffset)/TEXT="\\@2:Z scale: V [Sens. Zsens]" fullHeader
		if ((V_value < 0) || ((start < numpnts(W_Index)) && (V_value >= W_Index[start])))
			Print filename + ": Z scale not found for image " + num2str(num)
			headerData += "-;"
			continue
		endif
		SplitString/E="\\)\\s(.+)\\sV$" fullHeader[V_value], s
		//SplitString/E="\\((.+)\\sV/LSB\\)" fullHeader[V_value], s
		if (strlen(s) == 0)
			Print filename + ": Z scale invalid for image " + num2str(num)
			headerData += "-;"
			continue
		endif
		currentHeader += num2str(zsens*str2num(s)/(2^(bpp*8)))
		
		headerData += currentHeader + ";"
		success += 1
		
		num += 1
		
	while (1)
	
	return success

End

// Read file given by fileName.
// Add all lines into a new text wave
// return 0 if end of header found (defined by ksHeaderEnd)
// -1 otherwise.
// Last line of header not included in header wave.
Function ReadHeaderLines(filename, headerwave)
	String filename			// Full Igor-style path to filename ("folder:to:file.ext")
	String headerwave		// Name of the text wave for header data (will be overwritten)
	
	Variable maxlength = 100000		// max length of file to read in bytes
	
	Variable result = -1			// Set to 0 if end of header found
	
	if (strlen(fileName) == 0)
		return -1
	endif
	
	Variable refNum
	Open/R refNum as fileName				
	if (refNum == 0)	
		return -1						// Error
	endif

	Make/T/O/N=0 $headerwave		// Make new text wave, overwrite old if needed
	WAVE/T fullheader=$headerwave
	
	Variable len = 0
	String buffer = ""
	Variable line = 0
	Variable totlength = 0
	
	do
		FReadLine/N=1000 refNum, buffer
		
		len = strlen(buffer)
		if (len == 0)
			break										// No more lines to be read
		endif
		
		if (cmpstr(buffer[0,len-2], ksHeaderEnd) == 0)
			result = 0								// End of header reached
			break
		endif
		
		totlength += len
		if (totlength > maxlength)
			break
		endif
		
		Redimension/N=(line+1) fullheader		// Add one more row to wave
		fullheader[line] = buffer[0,len-2]		// Add line to wave, omit trailing CR char

		line += 1
	while (1)

	Close refNum
	return result
End
