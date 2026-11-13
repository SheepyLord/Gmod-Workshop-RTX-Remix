# vr_feature_suite.py

Shared unittest bridge loader for companion VR feature suites. Imported by the test_companion_vr_* bridges during tools/test.ps1 or unittest discovery. Adds companion/tests to the import path, loads the named module with the supplied loader (including its own load_tests), and prints its exact case count. An explicitly optional suite missing from this branch gives one named skip and a zero-feature count; present empty suites or internal import failures fail the gate. No game, network, file writes or process exit codes; exceptions surface as unittest errors.
