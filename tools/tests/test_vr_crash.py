"""Generated AMD64 dumps exercise crash rules without a game, SDK or external parser."""
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest import mock
from types import SimpleNamespace

TOOLS=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(TOOLS))
import vr_crash as crash
import vr_session as driver


def dump(timestamp=0x6af185ec,marker=True,wrong_thread=False,nvidia=False):
    # Exception RSP and thread-list RSP intentionally point at different memory.
    data=bytearray(4096)
    struct.pack_into('<4sIIIIIQ',data,0,b'MDMP',0xa793,5,32,0,0,0)
    directories=[(7,56,128),(6,168,256),(3,52,448),(4,112,512),(9,48,640)]
    for i,item in enumerate(directories):struct.pack_into('<III',data,32+12*i,*item)
    struct.pack_into('<H',data,128,9)
    struct.pack_into('<I',data,256,77)
    struct.pack_into('<I',data,264,0xc0000005)
    module_base=0x180000000
    ip=module_base+0xe622f8 if nvidia else 0
    struct.pack_into('<Q',data,280,ip)
    struct.pack_into('<II',data,416,256,768)
    struct.pack_into('<I',data,448,1)
    struct.pack_into('<I',data,452,77 if not wrong_thread else 88)
    struct.pack_into('<QII',data,476,0x100000,256,2048)
    struct.pack_into('<II',data,492,256,1024)
    struct.pack_into('<I',data,512,1)
    struct.pack_into('<QIIII',data,516,module_base,0x2000000,0,timestamp,1280)
    name=('nvoglv64.dll' if nvidia else 'gmcl_RTXFixesBinary_win64.dll').encode('utf-16-le')
    struct.pack_into('<I',data,1280,len(name));data[1284:1284+len(name)]=name
    struct.pack_into('<I',data,768+48,0x100001)
    struct.pack_into('<Q',data,768+152,0x100040)
    struct.pack_into('<Q',data,768+248,ip)
    struct.pack_into('<I',data,1024+48,0x100001)
    struct.pack_into('<Q',data,1024+152,0x200000)
    struct.pack_into('<QQ',data,640,2,2048)
    struct.pack_into('<QQ',data,656,0x100000,256)
    struct.pack_into('<QQ',data,672,0x200000,256)
    if marker:struct.pack_into('<Q',data,2048+0x80,module_base+0x41605b)
    return bytes(data)


class CrashTests(unittest.TestCase):
    def setUp(self):
        folder=TOOLS.parent/'out/tmp';folder.mkdir(parents=True,exist_ok=True)
        self.tmp=tempfile.TemporaryDirectory(dir=folder,prefix='crash-rule-')
        self.root=Path(self.tmp.name)
    def tearDown(self):self.tmp.cleanup()
    def inspect(self,content,**kwargs):
        path=self.root/'fixture.dmp';path.write_bytes(content)
        return crash.classify_dump(path,**kwargs)
    def test_exception_context_stack_matches_known_fixes(self):
        r=self.inspect(dump(),startup=False)
        self.assertEqual(r['classification'],'known_fixes_render_entity')
        self.assertEqual(r['rsp'],0x100040)
        self.assertEqual(r['stack_match']['address'],0x100080)
    def test_other_module_build_still_records_and_stops_on_fixes_stack_marker(self):
        self.assertEqual(self.inspect(dump(timestamp=1))['classification'],'fixes_render_stack_signature')
    def test_repeated_unused_directory_padding_is_valid(self):
        data=bytearray(dump());struct.pack_into('<I',data,8,7)
        self.assertEqual(self.inspect(data)['classification'],'known_fixes_render_entity')
    def test_wrong_thread_cannot_match(self):
        self.assertEqual(self.inspect(dump(wrong_thread=True))['classification'],'unknown')
    def test_no_marker_cannot_match(self):
        self.assertEqual(self.inspect(dump(marker=False))['classification'],'unknown')
    def test_nvidia_is_startup_only(self):
        self.assertEqual(self.inspect(dump(marker=False,nvidia=True),startup=True)['classification'],'known_nvidia_startup')
        self.assertEqual(self.inspect(dump(marker=False,nvidia=True),startup=False)['classification'],'unknown')
    def test_truncated_dump_fails_closed(self):
        self.assertEqual(self.inspect(dump()[:300])['classification'],'unknown')
    def test_fixed_package_never_retries_fixes_signature(self):
        self.assertFalse(crash.retry_allowed({'classification':'known_fixes_render_entity'}))
        self.assertTrue(crash.retry_allowed({'classification':'known_nvidia_startup'}))
        self.assertFalse(crash.retry_allowed({'classification':'known_nvidia_startup'},prior_crash=True))
        self.assertFalse(crash.retry_allowed({'classification':'unknown'}))

    def test_copy_preserves_read_only_source_and_validates_pid(self):
        source=self.root/'wer';source.mkdir();original=source/'gmod.exe.77.dmp';original.write_bytes(dump())
        before=original.read_bytes();r=crash.copy_wer_dump(source,self.root/'evidence',77)
        self.assertEqual(original.read_bytes(),before)
        self.assertEqual(Path(r['copy']).read_bytes(),before)
        self.assertEqual(r['sha256'],crash.digest(original))
        with self.assertRaises(ValueError):crash.copy_wer_dump(source,self.root/'evidence','../77')
        with self.assertRaises(ValueError):crash.copy_wer_dump(source,source/'bad-destination',77)
    def test_retry_claim_cannot_be_reused_by_a_later_process(self):
        driver.claim_crash_retry(self.root,self.root/'retry',123,'one')
        driver.claim_crash_retry(self.root,self.root/'retry',123,'one')
        with self.assertRaises(RuntimeError):driver.claim_crash_retry(self.root,self.root/'retry2',124,'two')
    def test_retry_reexecutes_complete_caller_and_skips_parent_reducers(self):
        import json
        parent=self.root/'case';parent.mkdir();entry=self.root/'recipe.py';entry.write_text('# test\n')
        (parent/'crash.json').write_text(json.dumps({'classification':'known_nvidia_startup','retry_eligible':True}))
        (parent/'restoration.json').write_text(json.dumps({'clean':True}))
        with mock.patch.dict('os.environ',{},clear=True),mock.patch.object(driver,'_main_once',return_value=1),\
             mock.patch.object(driver,'main_checkout',return_value=TOOLS.parent),\
             mock.patch.object(sys,'argv',[str(entry),'--evidence',str(parent),'--simulate']),\
             mock.patch.object(driver.subprocess,'run',return_value=SimpleNamespace(returncode=0)) as launch:
            with self.assertRaises(SystemExit) as stopped:driver.main(['--evidence',str(parent)])
        self.assertEqual(stopped.exception.code,0)
        command=launch.call_args.args[0]
        self.assertIn(str(parent.with_name('case-retry1')),command)
        self.assertIn('--simulate',command)
        self.assertEqual(launch.call_args.kwargs['env']['NLVR_CRASH_RETRY_OF'],str(parent))
    def test_old_fixes_retry_receipt_cannot_reauthorize_itself(self):
        import json
        parent=self.root/'stale-fixes';parent.mkdir()
        (parent/'crash.json').write_text(json.dumps({'classification':'known_fixes_render_entity','retry_eligible':True}))
        (parent/'restoration.json').write_text(json.dumps({'clean':True}))
        with mock.patch.dict('os.environ',{},clear=True),mock.patch.object(driver,'_main_once',return_value=1),mock.patch.object(driver,'main_checkout',return_value=TOOLS.parent),mock.patch.object(sys,'argv',[str(TOOLS/'vr_session.py'),'--evidence',str(parent)]),mock.patch.object(driver.subprocess,'run',return_value=SimpleNamespace(returncode=0)) as launch:
            self.assertEqual(driver.main(['--evidence',str(parent)]),1)
        launch.assert_not_called()

    def test_signed_access_violation_is_a_crash(self):
        self.assertTrue(crash.crashed({'exit':-1073741819}))
        self.assertFalse(crash.crashed({'exit':0}))


if __name__=='__main__':unittest.main()
