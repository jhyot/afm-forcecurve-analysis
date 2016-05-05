AFM Force Curve Analysis Software Package for Wavemetrics IGOR Pro
==================================================================

This software offers a basic user interface for analysis of AFM (atomic force microscopy)
force curves and force volume maps from Bruker (formerly Veeco) Nanoscope files.

It consists of procedure files (i.e. scripts) written for [IGOR Pro][igor], a scientific programming and graphing environment by
Wavemetrics.

  [igor]: https://www.wavemetrics.com/products/igorpro/igorpro.htm


Features:
* Loading of binary AFM data into the Igor format
* Display and plotting of force curve and force volume maps
* Data analysis, classification and review

The software was originally written to perform data analysis for my PhD thesis:
> Hyotyla, Janne T. Nanomechanics of Confined Polymer Systems. 2016, PhD Thesis, University of Basel, Faculty of Science.

(link to online version coming soon)

The main intent of this software package is to allow reproduction of the data analysis and presentation in the thesis.
As such, the analysis functions are mostly tailored for indentation of polymer brush-like samples.
Major parts of the software deal with brush height analysis.

Nevertheless, the software can also be useful as a basis for other AFM force curve analysis.


Requirements
------------
You need to have IGOR Pro in order to run the AFM analysis software.

The software has been tested with IGOR Pro 6.3.4 under Windows 7. It should also run on Igor for Mac, but that
has not been tested.

The software has been tested with data from Bruker Nanoscope versions 7.3 and 8.1x. Nanoscope 9.x seems to work as well, but
has not been thoroughly tested. As long as the Nanoscope data file format does not change, the software should work without
problems.



Installation
------------

* Go to <https://github.com/jhyot/afm-forcecurve-analysis/releases/latest>
* Download the `afm-forcecurve-analysis.zip` file.
* Unpack the contents of the zip file into any directory on your computer.
* Open `force-curve-analysis.ipf` in IGOR and compile the file. You are now ready to use the software.


Manual
------
The manual for this software is included as a PDF file in the release zip file. The source of the manual resides in
Latex format in the `doc` folder of the repository.


Building from source
--------------------
There is no build process, the `.ipf` files can be directly openend with IGOR Pro. The folder structure must be
kept the same so that the individual files can be found from the main `force-curve-analysis.ipf` file.

Run `./build.sh` (currently on Linux only) from the project root folder to automatically generate a zip file in the `build`
folder with the necessary files for easy redistribution.

To also generate the PDF manual from Latex sources, a Tex distribution must be present on the build system.
`build.sh` will generate the PDF and add it to the zip file if pdflatex is present on the system.


Contributing
------------
If you want to contribute to this open source software, the easiest way is to fork the repository on Github into your
own repository, make your modifications, and the submit a pull request.

If you have any questions regarding enhancement or use of the software, open an issue here in Github, or contact me directly at
jhyotyla@gmail.com.



Acknowledgements
----------------
This software was originally developed in Prof. Roderick Lim's [Nanobiology Group][nanobio]
at the University of Basel.

Original contributors:
* Janne Hyötylä, [jhyotyla@gmail.com](mailto:jhyotyla@gmail.com)
* Raphael Wagner, [raphael@wagner-net.ch](mailto:raphael@wagner-net.ch)


  [nanobio]: http://www.biozentrum.unibas.ch/research/groups-platforms/overview/unit/lim/



License
-------
This software is licensed under the Apache License 2.0. See the LICENSE file for full details.

Copyright (c) 2016 Janne Hyötylä
Copyright (c) 2016 University of Basel