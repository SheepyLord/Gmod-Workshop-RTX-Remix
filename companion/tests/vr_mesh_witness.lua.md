# Independent posed-mesh witness

Private diagnostic code with no product grip, Model.Pose or NLVR.Weapon dependency.
It reads posed/skinned vertices and the weapon rig bone once per drawn model/scale,
then applies that model's actual rendered transform. Semantic mesh-region selectors
contain no product grip coordinates. Non-shaft grip is the region's measured centre;
shaft grip station comes from the authored rig and the rendered hand's relative
middle-finger circle. Comparing that fixed model station with the rendered hand is
translation-sensitive, including a product grip shift along the shaft.

The SMG barrel witness fits the forward cap plane, independently of production's
two-ring centre fit. End witnesses use raw extreme vertices. Skinning is bounded to
65536 distinct points. No hooks, files, SDK calls or native execution; callers own
captured model lifetime and all live evidence. Unit fixtures contain small measured
vertex subsets and hand-bone reference data, not full game models.


Non-shaft Grip is the authored R_Hand bone, compared with the actual rendered Hand bone via Expected. No grip ROI/product target is used. Shaft witnesses remain geometry/finger based.

Round5 retains all raw vertices. Handle centreline is fitted only from independently selected mesh regions; closest-point station is clamped to the region. A signed asset-bone envelope independently excludes magazines, barrels, muzzles and stocks. Drawn finger bones supply the grasp; product grip data is never read.

Native and offline orientation observation both return the independently recorded authored barrel for every gun, not only SMG. Missing witnesses fail; all pistol/AR2 reversal/roll mutations remain killed.
