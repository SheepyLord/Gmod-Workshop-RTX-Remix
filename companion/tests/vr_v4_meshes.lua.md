# Posed world-model geometry export

Private observer for `vr_v4_geometry.py --export-meshes`. During its first VR frame,
reads the remaining ten stock world models, their bone/attachment transforms, and
their skinned mesh vertices at sequence/cycle zero. These are independent of the
VR hand targets. It uses each vertex's bind matrix and posed bone matrix, retaining
unweighted mesh positions. Temporary client models are removed immediately.

Outputs chunked `NLVR_QMODEL` console records, decoded to `models.json` in evidence.
No game assets, SteamVR files, settings or convars are changed. Standard driver
locks and rollback apply. No process exit status; an assertion fails the session.


The raw exporter covers all16 profiled models without importing product placement tables. Measurement models are never drawn; existing cleanup is unchanged.
