# vr_frames_geometry.py

Pure standard-library model-space metrology: PCA line fitting, finite-span axis distance/RMS/angle, and central Index body.obj handle-section extraction excluding its strap ring. Used by C's diagnostic builder/analyser; no game, SDK initialization or writes. Receipts keep the source OBJ hash and fitted sections. Accepts already-read points or an explicit body OBJ path. Imported only; exceptions fail callers. `axis_error` reports centre, RMS and maximum distances over a 6 cm segment so intersecting infinite lines cannot hide a bad fit.

`cylinder(points,axis)` fits the radial centre and radius to the eight proximal/middle surface joints by least squares. Its direction comes from the line through four finger-arc centres. A PCA line through the surface joints alone is retained only as an audit: it follows the side of a curved grasp rather than its tube centre. A generated eight-joint regression recovers a known tube centre and rejects a laterally displaced grasp.
