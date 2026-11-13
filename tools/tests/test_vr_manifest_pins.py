"""Pinned stock-copy metadata must not follow a separately updated field install."""
from pathlib import Path
from types import SimpleNamespace
import sys
import tempfile
import hashlib
import unittest
from unittest import mock
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import field_snapshot as snapshot
import verify_install


class ManifestPinTests(unittest.TestCase):
    def test_explicit_old_copy_manifest_does_not_follow_new_field_revision(self):
        old=Path('generated-old.manifest')
        data=SimpleNamespace(filenames_encrypted=False,files=[SimpleNamespace(path='bin/win64/client.dll',is_userconfig=False,is_dir=False)])
        with mock.patch.object(snapshot,'locate_install',side_effect=AssertionError('field moved to a different build')) as locate,mock.patch.object(snapshot,'parse_manifest',return_value=data) as parse:
            files,paths,why=snapshot.depot_inventory(Path('generated-copy'),None,[old])
        self.assertEqual(files,{'bin/win64/client.dll':False});self.assertEqual(paths,[old]);self.assertEqual(why,'')
        locate.assert_not_called();parse.assert_called_once_with(old)

    def test_missing_pinned_manifest_fails_closed(self):
        with mock.patch.object(snapshot,'parse_manifest',side_effect=FileNotFoundError('missing pin')):
            files,paths,why=snapshot.depot_inventory(Path('generated-copy'),None,[Path('missing.manifest')])
        self.assertIsNone(files);self.assertEqual(paths,[]);self.assertIn('missing pin',why)

    def test_wrong_explicit_manifest_rejected_before_registry_or_snapshot_write(self):
        scratch=Path(__file__).resolve().parents[2]/'out/tmp';scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as t:
            root=Path(t)/'install';root.mkdir();stock=root/'stock.bin';stock.write_bytes(b'actual bytes')
            folder=Path(t)/'snapshot'
            args=SimpleNamespace(root=root,snapshot=folder,no_depot_check=False,manifests_from='field',manifest=[Path(t)/'wrong.manifest'],registry_key='HKCU\\test')
            file=SimpleNamespace(path='stock.bin',size=len(b'actual bytes'),sha1=hashlib.sha1(b'foreign file').hexdigest(),is_dir=False,is_symlink=False,is_userconfig=False)
            wrong=SimpleNamespace(filenames_encrypted=False,files=[file],depot_id=1,manifest_id=2)
            with mock.patch.object(snapshot,'game_running',return_value=False),mock.patch.object(snapshot,'steam_manager',return_value=None),mock.patch.object(snapshot,'volume',return_value='same'),mock.patch.object(snapshot,'depot_inventory',return_value=({'stock.bin':False},args.manifest,'')),mock.patch.object(snapshot,'parse_manifest',return_value=wrong),mock.patch.object(verify_install,'parse_manifest',return_value=wrong),mock.patch.object(snapshot.subprocess,'run',side_effect=AssertionError('registry touched before pin validation')):
                with self.assertRaisesRegex(snapshot.Failure,'manifest.*match'):
                    snapshot.snapshot(args)
            self.assertFalse(folder.exists());self.assertEqual(stock.read_bytes(),b'actual bytes')


if __name__=='__main__':unittest.main()
